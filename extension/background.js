// Spending Angel — sensor service worker.
//
// Two jobs:
//   1. Register the detector content script ONLY where the user has chosen to
//      be watched (M-F2). No static <all_urls> injection — the extension asks
//      for nothing at install and gains per-site access by explicit user
//      action, so Chrome Web Store review sees a minimal, honest footprint.
//      Reconciles are serialized (EXT-03): five listeners can fire in the same
//      tick, and without a queue a stale "everywhere" run could finish after a
//      newer "listed" run and re-register *://*/*.
//   2. Forward detected checkout intents to the macOS app's localhost bridge
//      (M-F1). We fetch here (not in the page) because the SW can reach
//      http://127.0.0.1 without the page's mixed-content / private-network limits.
//      The SW authenticates to the bridge with the pairing token the app showed
//      the user (Authorization: Bearer <token>, NATIVE-01). No token stored →
//      nothing is sent and the popup shows the unpaired state. Only
//      {id,type,trigger,hostname,ts} is serialized to the bridge, rebuilt from
//      named keys (review S-03) — nothing else on the message can travel.

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
// permissions actually granted. Only ever registers on hosts we hold. Reads
// storage at its own start, so the last queued run reflects the latest state.
async function reconcileContentScripts() {
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

// Reconciles run strictly one after another. Five listeners can fire within
// the same tick (mode flip + list edit + permission grant); without a queue an
// older "everywhere" run could finish after a newer "listed" run and
// re-register *://*/*. The tail never rejects, so one failure can't wedge it.
let scriptSyncTail = Promise.resolve();
function syncContentScripts() {
  scriptSyncTail = scriptSyncTail
    .then(() => reconcileContentScripts())
    .catch((e) => saLog("error", "sites.sync_failed", String(e && e.message || e)));
  return scriptSyncTail;
}

chrome.runtime.onInstalled.addListener(() => {
  // Contained like every other listener (review R2-03): a storage that rejects
  // at install/update time must not become an unhandled rejection in the
  // worker. Nothing is logged — a dead storage can't take a log line either.
  seedIfNeeded().then(() => syncContentScripts()).catch(() => {});
});
chrome.runtime.onStartup.addListener(() => { syncContentScripts(); });
chrome.permissions.onAdded.addListener(() => { syncContentScripts(); });
chrome.permissions.onRemoved.addListener(() => { syncContentScripts(); });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") return;
  if (changes.saMode || changes.saAllowlist || changes.saBlocklist) syncContentScripts();
});

// ---- Intent forwarding (M-F1) ----------------------------------------------

chrome.runtime.onMessage.addListener((msg) => {
  // Containment: forward() owns its own error handling, but a rejection that
  // still escapes must not become an unhandled rejection in the worker.
  if (msg && msg.type === "checkout_intent") forward(msg).catch(() => {});
  // No async response needed — fire and forget.
});

// Ship one intent to the app. Storage outcome, always written in one set()
// (fire-and-forget with its own .catch — a torn-down storage must not surface
// as an unhandled rejection in the worker):
//   bridgeOk  true  → app answered (200, or a reachable rejection like 429/400)
//   bridgeOk  false → couldn't deliver; bridgeWhy says why:
//                     "unpaired" (no token, nothing sent), "unauthorized" (401),
//                     "unreachable" (timeout / network)
async function forward(payload) {
  // Token first, before any timer exists: an unpaired call must leave nothing
  // behind that keeps the worker (or a test's event loop) awake for 4 s.
  let token = "";
  try {
    const { saBridgeToken } = await chrome.storage.local.get({ saBridgeToken: "" });
    token = saNormalizeBridgeToken(saBridgeToken);
  } catch (e) {
    // Storage is gone (worker torn down / extension reloaded). Log nothing —
    // saLog would write to the same dead storage — set nothing, send nothing.
    return;
  }
  if (token === "") {
    saLog("info", "bridge.unpaired",
      "no bridge token — open Options and paste the token from the app's PAIR SENSOR row",
      { intent_id: payload.id });
    chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now(), bridgeWhy: "unpaired" }).catch(() => {});
    return;
  }

  // The wire payload is rebuilt from named keys (review S-03): whatever else a
  // runtime message carries — a page can't reach onMessage, but a future popup
  // or a bug could — never leaves the worker. Exactly the five keys the app's
  // validate() knows about, in this order.
  const wire = {
    id: payload.id,
    type: payload.type,
    trigger: payload.trigger,
    hostname: payload.hostname,
    ts: payload.ts,
  };

  const t0 = Date.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), BRIDGE_TIMEOUT_MS);
  try {
    const res = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify(wire),
      signal: ctrl.signal,
    });
    if (res.ok) {
      saLog("info", "bridge.forwarded", payload.hostname, { intent_id: payload.id, ms: Date.now() - t0 });
      chrome.storage.local.set({ bridgeOk: true, bridgeAt: Date.now(), bridgeWhy: null }).catch(() => {});
    } else if (res.status === 401) {
      // The app no longer recognises our token (regenerated, or never matched).
      saLog("error", "bridge.unauthorized", "app rejected the token — re-pair in Options",
        { intent_id: payload.id, status: 401 });
      chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now(), bridgeWhy: "unauthorized" }).catch(() => {});
    } else {
      // App answered but rejected — 429 = within 8 s of the last accepted intent, 400 = bad payload.
      saLog("info", "bridge.rejected", `app answered ${res.status}`, { intent_id: payload.id, status: res.status });
      chrome.storage.local.set({ bridgeOk: true, bridgeAt: Date.now(), bridgeWhy: null }).catch(() => {});
    }
  } catch (e) {
    const why = e && e.name === "AbortError" ? "timed out" : "unreachable";
    saLog("error", "bridge.unreachable", `app ${why} — is Spending Angel running?`, { intent_id: payload.id });
    chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now(), bridgeWhy: "unreachable" }).catch(() => {});
  } finally {
    clearTimeout(timer);
  }
}
