// Spending Angel — sensor debug + quick-control popup.
//
// The "This site" section is the everyday control: watch / stop-watching (in
// "listed" mode) or pause / resume (in "everywhere" mode) for the current tab.
// Full list management lives in the options page. Everything below it is debug.

const $ = (id) => document.getElementById(id);

// ---- Debug panels (M-F1) ----------------------------------------------------

function renderIntent(intent) {
  $("last-intent").textContent = intent ? JSON.stringify(intent, null, 2) : "none yet";
}

function renderBridge(ok, at) {
  const el = $("bridge-status");
  const when = at ? new Date(at).toLocaleTimeString() : "";
  if (ok === null || ok === undefined) {
    el.textContent = "Not tried yet";
    el.className = "status";
  } else if (ok) {
    el.textContent = `Connected ✓  ${when}`;
    el.className = "status ok";
  } else {
    el.textContent = `App not reachable ✕  ${when}`;
    el.className = "status bad";
  }
}

function renderEvents(logs) {
  if (!logs || !logs.length) { $("events").textContent = "none yet"; return; }
  $("events").textContent = logs.slice(-8).map((l) => {
    const t = l.ts ? l.ts.slice(11, 19) : "";
    return `${t} ${l.level === "error" ? "✕" : "·"} ${l.event} ${l.msg}`;
  }).join("\n");
}

// ---- This-site quick control (M-F2) ----------------------------------------

let currentHost = "";

async function currentTabHost() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return saNormalizeHost(tab && tab.url ? tab.url : "");
}

async function renderSite() {
  currentHost = await currentTabHost();
  const btn = $("site-action");

  if (!currentHost) {
    $("site-host").textContent = "—";
    $("site-state").textContent = "This page can't be watched.";
    btn.hidden = true;
    return;
  }
  $("site-host").textContent = currentHost;

  const { saMode, saAllowlist, saBlocklist } = await chrome.storage.local.get({
    saMode: "listed", saAllowlist: [], saBlocklist: [],
  });
  const granted = await chrome.permissions.contains({ origins: saHostToOrigins(currentHost) });
  btn.hidden = false;

  if (saMode === "everywhere") {
    const paused = saHostInList(currentHost, saBlocklist);
    $("site-state").textContent = paused ? "Paused here." : "Watching everywhere.";
    btn.textContent = paused ? "Resume here" : "Pause on this site";
    btn.dataset.act = paused ? "resume" : "pause";
  } else {
    const listed = saHostInList(currentHost, saAllowlist);
    const active = listed && granted;
    $("site-state").textContent = active ? "Watching this site."
      : listed ? "In your list — needs permission." : "Not watched.";
    btn.textContent = active ? "Stop watching" : "Watch this site";
    btn.dataset.act = active ? "unwatch" : "watch";
  }
}

async function onSiteAction() {
  const act = $("site-action").dataset.act;
  const origins = saHostToOrigins(currentHost);

  if (act === "watch") {
    // Permission request MUST be in this click's gesture — no awaits before it.
    const ok = await chrome.permissions.request({ origins });
    if (!ok) { $("site-state").textContent = "Permission denied — not watched."; return; }
    const { saAllowlist } = await chrome.storage.local.get({ saAllowlist: [] });
    await chrome.storage.local.set({ saAllowlist: saAddToList(saAllowlist, currentHost) });
  } else if (act === "unwatch") {
    const { saAllowlist } = await chrome.storage.local.get({ saAllowlist: [] });
    await chrome.storage.local.set({ saAllowlist: saRemoveFromList(saAllowlist, currentHost) });
    chrome.permissions.remove({ origins }).catch(() => {});
  } else if (act === "pause") {
    const { saBlocklist } = await chrome.storage.local.get({ saBlocklist: [] });
    await chrome.storage.local.set({ saBlocklist: saAddToList(saBlocklist, currentHost) });
  } else if (act === "resume") {
    const { saBlocklist } = await chrome.storage.local.get({ saBlocklist: [] });
    await chrome.storage.local.set({ saBlocklist: saRemoveFromList(saBlocklist, currentHost) });
  }
  await renderSite();
}

// ---- Boot -------------------------------------------------------------------

async function loadDebug() {
  const s = await chrome.storage.local.get({ lastIntent: null, bridgeOk: null, bridgeAt: null, saLogs: [] });
  renderIntent(s.lastIntent);
  renderBridge(s.bridgeOk, s.bridgeAt);
  renderEvents(s.saLogs);
}

document.addEventListener("DOMContentLoaded", async () => {
  await Promise.all([renderSite(), loadDebug()]);

  $("site-action").addEventListener("click", onSiteAction);
  $("open-options").addEventListener("click", (e) => { e.preventDefault(); chrome.runtime.openOptionsPage(); });

  $("simulate").addEventListener("click", async () => {
    const payload = {
      id: crypto.randomUUID(),
      type: "checkout_intent",
      trigger: "simulated",
      hostname: "example-shop.test",
      ts: Date.now(),
    };
    console.log("[SA sensor]", payload);
    await chrome.storage.local.set({ lastIntent: payload });
    renderIntent(payload);
    chrome.runtime.sendMessage(payload).catch(() => {}); // forward to the app via the SW
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes.lastIntent) renderIntent(changes.lastIntent.newValue);
    if (changes.saLogs) renderEvents(changes.saLogs.newValue);
    if (changes.bridgeOk || changes.bridgeAt) loadDebug();
    if (changes.saMode || changes.saAllowlist || changes.saBlocklist) renderSite();
  });
});
