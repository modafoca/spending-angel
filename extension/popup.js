// Spending Angel — everyday site controls. Diagnostics live in Settings.
//
// The "This site" section is the everyday control: watch / stop-watching (in
// "listed" mode) or pause / resume (in "everywhere" mode) for the current tab.
// Full list management, connection setup, and diagnostics live in Settings.
// The "App connection" wording comes from status.js, shared with Options, so
// both surfaces say the same thing about the app.

const $ = (id) => document.getElementById(id);
const fmtTime = (ms) => new Date(ms).toLocaleTimeString();

// ---- Debug panels (M-F1) ----------------------------------------------------

// Tone → class on a .status line ("neutral" is the bare class).
function statusClass(tone) {
  return tone === "neutral" ? "status" : `status ${tone}`;
}

// App connection. `ok` is what the SW last saw; `why` disambiguates a false:
// "unpaired" (no token, nothing sent), "unauthorized" (app said 401), or
// anything else = the app wasn't reachable. The pair hint only shows for the
// two states the user can fix in Options. Wording lives in saConnectionText.
function renderBridge(ok, at, why) {
  const el = $("bridge-status");
  const hint = $("bridge-hint");
  const c = saConnectionText({ bridgeOk: ok, bridgeAt: at, bridgeWhy: why }, fmtTime);
  el.textContent = c.text;
  el.className = statusClass(c.tone);
  hint.hidden = !c.needsPairing;
}

// What the app did with the last accepted intent (Round 3 body). Kept apart
// from the connection line: a reachable app can still show nothing.
function renderLastResult(lastResult) {
  const el = $("last-result");
  const r = saLastResultText(lastResult, fmtTime);
  el.textContent = r.text;
  el.className = statusClass(r.tone);
  el.hidden = !lastResult;
}

// Version handshake: only speaks up when sensor and app disagree on major.minor.
function renderVersionHint(appVersion) {
  const el = $("version-hint");
  const hint = saVersionHint(chrome.runtime.getManifest().version, appVersion);
  el.textContent = hint || "";
  el.className = "hint bad";
  el.hidden = hint === null;
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
    $("site-state").textContent = paused ? "Paused here." : "Watching this site.";
    btn.textContent = paused ? "Resume here" : "Pause here";
    btn.dataset.act = paused ? "resume" : "pause";
  } else {
    const listed = saHostInList(currentHost, saAllowlist);
    const active = listed && granted;
    $("site-state").textContent = active ? "Watching this site."
      : listed ? "Allow access to watch this site." : "Not watching this site.";
    btn.textContent = active ? "Pause here" : "Watch this site";
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
  const s = await chrome.storage.local.get({
    saBridgeToken: "", bridgeOk: null, bridgeAt: null, bridgeWhy: null,
    lastResult: null, appVersion: null,
  });
  const needsSetup = !saNormalizeBridgeToken(s.saBridgeToken) || s.bridgeOk === null || s.bridgeWhy === "unauthorized";
  $("setup-card").hidden = !needsSetup;
  $("site-card").hidden = needsSetup;
  $("connection-card").hidden = needsSetup;
  renderBridge(s.bridgeOk, s.bridgeAt, s.bridgeWhy);
  renderLastResult(s.lastResult);
  renderVersionHint(s.appVersion);
}

document.addEventListener("DOMContentLoaded", async () => {
  // Wire controls before reads so Settings remains reachable if storage fails.
  for (const id of ["open-options", "open-settings", "open-options-pair", "setup-connect"]) {
    $(id).addEventListener("click", () => { chrome.runtime.openOptionsPage(); });
  }
  $("site-action").addEventListener("click", () => { onSiteAction().catch(() => {}); });
  await Promise.all([renderSite(), loadDebug()]).catch(() => {});
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes.bridgeOk || changes.bridgeAt || changes.bridgeWhy || changes.saBridgeToken
        || changes.lastResult || changes.appVersion) loadDebug().catch(() => {});
    if (changes.saMode || changes.saAllowlist || changes.saBlocklist) renderSite().catch(() => {});
  });
});
