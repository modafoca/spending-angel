// Spending Angel — browser Settings. Setup is expanded until confirmed;
// site controls remain visible, and diagnostics live in a closed disclosure.
// The pairing token and the existing five-field bridge contract stay local.

const $ = (id) => document.getElementById(id);
let setupWasRequired = null;

const fmtTime = (ms) => new Date(ms).toLocaleTimeString();

async function state() {
  return chrome.storage.local.get({ saMode: "listed", saAllowlist: [], saBlocklist: [] });
}

// ---- Pairing (NATIVE-01) ----------------------------------------------------

const TOKEN_STATE_NONE        = "Copy a connection code from the Mac app to get started.";
const TOKEN_STATE_SAVED       = (tail) => `Code saved — waiting for the app to confirm (…${tail}). Choose “Test connection” above.`;
const TOKEN_STATE_UNREACHABLE = (tail) => `Code saved — the app isn't answering yet (…${tail}). Is Spending Angel running?`;
const TOKEN_STATE_PAIRED      = (tail) => `Connected — code ends in …${tail}`;
const TOKEN_STATE_REJECTED    = (tail) => `Code not recognised — copy it again from the Mac app’s Settings (…${tail})`;
const TOKEN_JUNK_MSG          = "That code looks incomplete. Copy the full code from the Mac app.";

// A saved code is not a confirmed connection: the app must answer first. A save resets
// the bridge keys to null, so a fresh save always reads as "waiting". An app
// that stopped answering keeps the "Code saved" prefix (the token is fine)
// and says what to check instead of inviting a retry that fails the same way.
function tokenStateText(bridgeOk, bridgeWhy, tail) {
  if (bridgeOk === true) return TOKEN_STATE_PAIRED(tail);
  if (bridgeWhy === "unauthorized") return TOKEN_STATE_REJECTED(tail);
  if (bridgeWhy === "unreachable") return TOKEN_STATE_UNREACHABLE(tail);
  return TOKEN_STATE_SAVED(tail);
}

async function renderToken() {
  const { saBridgeToken, bridgeOk, bridgeWhy } =
    await chrome.storage.local.get({ saBridgeToken: "", bridgeOk: null, bridgeWhy: null });
  const token = saNormalizeBridgeToken(saBridgeToken);
  const input = $("token-input");
  const needsSetup = !token || bridgeOk === null || bridgeWhy === "unauthorized";
  if (needsSetup) $("pair-card").open = true;
  else if (setupWasRequired !== false && !input.value) $("pair-card").open = false;
  setupWasRequired = needsSetup;
  $("pair-summary").textContent = !token ? "One-time setup" : bridgeOk === true ? "Connected" : "Check connection";
  $("disconnect").hidden = !token;
  // Placeholder + status only. The stored token is only ever shown masked, via
  // the placeholder; the field's value belongs to the user (a paste in
  // progress) and is cleared by saveToken on success, never by a re-render.
  if (!token) {
    input.placeholder = "Paste your connection code";
    $("token-state").textContent = TOKEN_STATE_NONE;
    return;
  }
  const tail = token.slice(-4);
  input.placeholder = `••••…${tail}`;
  $("token-state").textContent = tokenStateText(bridgeOk, bridgeWhy, tail);
}

async function saveToken(raw) {
  const rawTrimmed = String(raw || "").trim();
  if (rawTrimmed === "") {
    // Empty save = unpair. The popup reads the three bridge keys with null
    // defaults, so removing them is the same as nulling them.
    await chrome.storage.local.remove(["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"]);
    $("token-input").value = "";       // the field never carries the real token past a save
    await renderToken();
    return;
  }
  const t = saNormalizeBridgeToken(rawTrimmed);
  if (t === "") {
    // Half-pasted / junk: keep whatever is stored, say so inline.
    $("token-state").textContent = TOKEN_JUNK_MSG;
    return;
  }
  // One write: the new token AND a full reset of the bridge status, so the
  // popup reads "Connection not checked yet" (not a stale "App not reachable") until the
  // next intent or "Test connection" proves the pairing.
  await chrome.storage.local.set({ saBridgeToken: t, bridgeOk: null, bridgeAt: null, bridgeWhy: null });
  $("token-input").value = "";
  await renderToken();
}

// ---- App status card (Round 3) ---------------------------------------------

// Tone is shared with the popup; neutral uses the surrounding text color.
function setKv(id, { text, tone }) {
  const el = $(id);
  el.textContent = text;
  el.className = tone === "neutral" ? "" : tone;
}

async function renderApp() {
  const s = await chrome.storage.local.get({
    bridgeOk: null, bridgeAt: null, bridgeWhy: null, lastResult: null, appVersion: null,
  });
  const sensor = chrome.runtime.getManifest().version;
  setKv("app-connection", saConnectionText(s, fmtTime));
  setKv("app-last-result", saLastResultText(s.lastResult, fmtTime));
  $("app-last-result").hidden = !s.lastResult;
  // The app's version only arrives with a Round 3 body; before that, say so
  // instead of pretending.
  setKv("app-versions", {
    text: typeof s.appVersion === "string"
      ? `Browser v${sensor} · App v${s.appVersion}`
      : `Browser v${sensor} · App version not seen yet`,
    tone: "neutral",
  });
  const hint = saVersionHint(sensor, s.appVersion);
  $("app-version-hint").textContent = hint || "";
  $("app-version-hint").className = "note bad";
  $("app-version-hint").hidden = hint === null;
}

// Test connection follows the real forwarding path and can display a catch.
async function simulateIntent() {
  const payload = saSimulatedIntent(Date.now());
  await chrome.storage.local.set({ lastIntent: payload });
  chrome.runtime.sendMessage(payload).catch(() => {});
}

// ---- Mode -------------------------------------------------------------------

async function renderMode() {
  const { saMode } = await state();
  document.querySelectorAll('input[name="mode"]').forEach((r) => { r.checked = r.value === saMode; });
  $("listed-card").hidden = saMode !== "listed";
  $("everywhere-card").hidden = saMode !== "everywhere";
  $("mode-note").textContent = saMode === "everywhere"
    ? "Paused sites stay quiet, including tabs you already have open."
    : "You can also watch or pause a site from the Chrome toolbar.";
}

async function setMode(mode) {
  if (mode === "everywhere") {
    const ok = await chrome.permissions.request({ origins: ["*://*/*"] });
    if (!ok) { await renderMode(); return; } // denied — stay in listed
  }
  await chrome.storage.local.set({ saMode: mode });
  await renderAll();
}

// ---- Listed mode ------------------------------------------------------------

async function renderListed() {
  const { saAllowlist } = await state();
  const ul = $("site-list");
  ul.innerHTML = "";
  let pending = 0;

  for (const host of saAllowlist) {
    const origins = saHostToOrigins(host);
    const granted = await chrome.permissions.contains({ origins });
    if (!granted) pending++;

    const li = document.createElement("li");
    li.className = "row";

    const name = document.createElement("span");
    name.className = "host";
    name.textContent = host;
    li.appendChild(name);

    const tag = document.createElement("span");
    tag.className = "tag " + (granted ? "on" : "pending");
    tag.textContent = granted ? "Watching" : "Needs access";
    li.appendChild(tag);

    if (!granted) {
      const grant = mkBtn("Allow", "link-btn grant", async () => {
        await chrome.permissions.request({ origins });
        await renderListed();
      });
      li.appendChild(grant);
    }
    li.appendChild(mkBtn("Remove", "link-btn", async () => {
      const { saAllowlist: cur } = await state();
      await chrome.storage.local.set({ saAllowlist: saRemoveFromList(cur, host) });
      chrome.permissions.remove({ origins }).catch(() => {});
      await renderListed();
    }));

    ul.appendChild(li);
  }

  $("listed-empty").hidden = saAllowlist.length > 0;
  $("enable-all").hidden = pending === 0;
  $("enable-all").textContent = `Enable ${pending} recommended`;
}

async function addSite(raw) {
  const host = saNormalizeHost(raw);
  if (!host) { $("add-input").value = ""; $("add-input").placeholder = "hmm, not a valid site"; return; }
  const origins = saHostToOrigins(host);
  // Add to the list first, then offer the grant in the same gesture.
  const { saAllowlist } = await state();
  await chrome.storage.local.set({ saAllowlist: saAddToList(saAllowlist, host) });
  await chrome.permissions.request({ origins }); // ok if denied — stays pending
  $("add-input").value = "";
  await renderListed();
}

async function enableAll() {
  const { saAllowlist } = await state();
  const origins = [];
  for (const host of saAllowlist) {
    if (!(await chrome.permissions.contains({ origins: saHostToOrigins(host) }))) {
      origins.push(...saHostToOrigins(host));
    }
  }
  if (origins.length) await chrome.permissions.request({ origins });
  await renderListed();
}

// ---- Everywhere mode --------------------------------------------------------

async function renderBlocked() {
  const { saBlocklist } = await state();
  const ul = $("block-list");
  ul.innerHTML = "";
  for (const host of saBlocklist) {
    const li = document.createElement("li");
    li.className = "row";
    const name = document.createElement("span");
    name.className = "host";
    name.textContent = host;
    li.appendChild(name);
    li.appendChild(mkBtn("Resume", "link-btn", async () => {
      const { saBlocklist: cur } = await state();
      await chrome.storage.local.set({ saBlocklist: saRemoveFromList(cur, host) });
      await renderBlocked();
    }));
    ul.appendChild(li);
  }
}

async function addBlocked(raw) {
  const host = saNormalizeHost(raw);
  if (!host) { $("pause-input").value = ""; return; }
  const { saBlocklist } = await state();
  await chrome.storage.local.set({ saBlocklist: saAddToList(saBlocklist, host) });
  $("pause-input").value = "";
  await renderBlocked();
}

// ---- Helpers + boot ---------------------------------------------------------

function mkBtn(label, cls, onClick) {
  const b = document.createElement("button");
  b.className = cls;
  b.textContent = label;
  b.addEventListener("click", onClick);
  return b;
}

async function renderDiagnostics() {
  const { lastIntent, saLogs } = await chrome.storage.local.get({ lastIntent: null, saLogs: [] });
  $("last-intent").textContent = lastIntent ? JSON.stringify(lastIntent, null, 2) : "No activity yet.";
  $("events").textContent = Array.isArray(saLogs) && saLogs.length ? saLogs.slice(-8).filter((l) => l && typeof l === "object").map((l) =>
    `${l.ts ? l.ts.slice(11, 19) : ""} ${l.event} ${l.msg}`).join("\n") : "No events yet.";
}

async function renderAll() {
  await renderToken();
  await renderApp();
  await renderMode();
  await renderListed();
  await renderBlocked();
}

document.addEventListener("DOMContentLoaded", async () => {
  await renderAll();
  await renderDiagnostics();

  $("token-form").addEventListener("submit", (e) => { e.preventDefault(); if (!$("token-input").value.trim()) {
    $("token-state").textContent = "Paste a code first, or choose Disconnect below.";
    return;
  }
  saveToken($("token-input").value).catch(() => { $("token-state").textContent = "Couldn’t save the code. Try again."; }); });
  document.querySelectorAll('input[name="mode"]').forEach((r) => {
    r.addEventListener("change", () => setMode(r.value));
  });
  $("add-form").addEventListener("submit", (e) => { e.preventDefault(); addSite($("add-input").value); });
  $("pause-form").addEventListener("submit", (e) => { e.preventDefault(); addBlocked($("pause-input").value); });
  $("enable-all").addEventListener("click", enableAll);
  $("disconnect").addEventListener("click", () => { saveToken("").catch(() => {}); });
  $("app-simulate").addEventListener("click", () => { simulateIntent().catch(() => {}); });

  chrome.permissions.onAdded.addListener(renderListed);
  chrome.permissions.onRemoved.addListener(renderListed);

  // Live status never erases a paste in progress.
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes.saMode) renderMode().catch(() => {});
    if (changes.saMode || changes.saAllowlist) renderListed().catch(() => {});
    if (changes.saMode || changes.saBlocklist) renderBlocked().catch(() => {});
    if (changes.lastIntent || changes.saLogs) renderDiagnostics().catch(() => {});
    // Contained: a storage that rejects while the page is tearing down must
    // not surface as an unhandled rejection (same pattern as the worker).
    if (changes.saBridgeToken || changes.bridgeOk || changes.bridgeWhy) renderToken().catch(() => {});
    // The App card follows the same keys plus the two the worker writes from
    // the app's answer body.
    if (changes.bridgeOk || changes.bridgeAt || changes.bridgeWhy
        || changes.lastResult || changes.appVersion) renderApp().catch(() => {});
  });
});
