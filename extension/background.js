// Spending Angel — sensor service worker.
//
// Two jobs:
//   1. Register the detector content script ONLY where the user has chosen to
//      be watched (M-F2). No static <all_urls> injection — the extension asks
//      for nothing at install and gains per-site access by explicit user
//      action, so Chrome Web Store review sees a minimal, honest footprint.
//   2. Forward detected checkout intents to the macOS app's localhost bridge
//      (M-F1). We fetch here (not in the page) because the SW can reach
//      http://127.0.0.1 without the page's mixed-content / private-network limits.

importScripts("domains.js", "log.js", "sites.js");

const BRIDGE_URL = "http://127.0.0.1:17865/intent";
const SCRIPT_ID = "sa-detector";
const CONTENT_JS = ["domains.js", "log.js", "detect.js", "sites.js", "content.js"];
const BRIDGE_TIMEOUT_MS = 4000;

// ---- Storage defaults -------------------------------------------------------

const DEFAULTS = {
  saMode: "listed",        // "listed" | "everywhere"
  saAllowlist: [],         // hosts to watch in "listed" mode
  saBlocklist: [],         // hosts to never watch in "everywhere" mode
  saInitialized: false,
};

async function seedIfNeeded() {
  const s = await chrome.storage.local.get(DEFAULTS);
  if (s.saInitialized) return;
  // First run: pre-fill the watch list with the curated shopping domains so the
  // options page can offer "enable recommended" in one click. They stay
  // PENDING (no host permission) until the user grants — nothing is watched yet.
  const defaults = (typeof SPENDING_ANGEL_DOMAINS !== "undefined" ? SPENDING_ANGEL_DOMAINS : [])
    .map((h) => h.toLowerCase());
  await chrome.storage.local.set({
    saMode: "listed",
    saAllowlist: Array.from(new Set(defaults)).sort(),
    saBlocklist: [],
    saInitialized: true,
  });
  saLog("info", "sites.seeded", `${defaults.length} recommended sites (pending permission)`);
}

// ---- Content-script registration -------------------------------------------

// Reconcile the registered detector against the current mode + lists + the
// permissions actually granted. Only ever registers on hosts we hold.
async function syncContentScripts() {
  const { saMode, saAllowlist } = await chrome.storage.local.get(DEFAULTS);

  let matches = [];
  if (saMode === "everywhere") {
    if (await chrome.permissions.contains({ origins: ["*://*/*"] })) matches = ["*://*/*"];
  } else {
    for (const host of saAllowlist) {
      const origins = saHostToOrigins(host);
      if (origins.length && (await chrome.permissions.contains({ origins }))) {
        matches.push(...origins);
      }
    }
  }

  // Replace the single registration wholesale (simplest correct reconcile).
  try { await chrome.scripting.unregisterContentScripts({ ids: [SCRIPT_ID] }); } catch (e) { /* none yet */ }

  if (!matches.length) {
    saLog("info", "sites.registered", "0 patterns — grant a site to start watching", { mode: saMode });
    return;
  }
  try {
    await chrome.scripting.registerContentScripts([{
      id: SCRIPT_ID,
      matches,
      js: CONTENT_JS,
      runAt: "document_idle",
      persistAcrossSessions: true,
    }]);
    saLog("info", "sites.registered", `${matches.length} pattern(s)`, { mode: saMode });
  } catch (e) {
    saLog("error", "sites.register_failed", String(e && e.message || e));
  }
}

chrome.runtime.onInstalled.addListener(async () => { await seedIfNeeded(); await syncContentScripts(); });
chrome.runtime.onStartup.addListener(() => { syncContentScripts(); });
chrome.permissions.onAdded.addListener(() => { syncContentScripts(); });
chrome.permissions.onRemoved.addListener(() => { syncContentScripts(); });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") return;
  if (changes.saMode || changes.saAllowlist || changes.saBlocklist) syncContentScripts();
});

// ---- Intent forwarding (M-F1) ----------------------------------------------

chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === "checkout_intent") forward(msg);
  // No async response needed — fire and forget.
});

async function forward(payload) {
  const t0 = Date.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), BRIDGE_TIMEOUT_MS);
  try {
    const res = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    if (res.ok) {
      saLog("info", "bridge.forwarded", payload.hostname, { intent_id: payload.id, ms: Date.now() - t0 });
    } else {
      // App answered but rejected — 429 = a catch is already on screen, 400 = bad payload.
      saLog("info", "bridge.rejected", `app answered ${res.status}`, { intent_id: payload.id, status: res.status });
    }
    chrome.storage.local.set({ bridgeOk: true, bridgeAt: Date.now() });
  } catch (e) {
    const why = e && e.name === "AbortError" ? "timed out" : "unreachable";
    saLog("error", "bridge.unreachable", `app ${why} — is Spending Angel running?`, { intent_id: payload.id });
    chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now() });
  } finally {
    clearTimeout(timer);
  }
}
