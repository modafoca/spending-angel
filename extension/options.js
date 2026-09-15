// Spending Angel — options page. Pairing + full site-list management.
//
// Pairing: the one secret in the whole system is the bridge token the macOS
// app mints and shows under PAIR SENSOR; the user pastes it here and the
// service worker sends it as a bearer credential. Listed mode: an allowlist of
// sites; each needs a host-permission grant (a Chrome gesture) before the
// sensor can actually run there. Everywhere mode: a blocklist of sites to leave
// alone. All local — nothing is sent anywhere.

const $ = (id) => document.getElementById(id);

async function state() {
  return chrome.storage.local.get({ saMode: "listed", saAllowlist: [], saBlocklist: [] });
}

// ---- Pairing (NATIVE-01) ----------------------------------------------------

const TOKEN_JUNK_MSG = "hmm, that doesn't look like a token (64 hex characters)";

async function renderToken() {
  const { saBridgeToken } = await chrome.storage.local.get({ saBridgeToken: "" });
  const token = saNormalizeBridgeToken(saBridgeToken);
  const input = $("token-input");
  // The stored token is only ever shown masked, via the placeholder, and the
  // field itself stays empty so a stray keystroke can't corrupt it.
  input.value = "";
  if (token) {
    const tail = token.slice(-4);
    input.placeholder = `••••…${tail}`;
    $("token-state").textContent = `Paired — token ends in …${tail}`;
  } else {
    input.placeholder = "paste the 64-character token";
    $("token-state").textContent = "Not paired — the app will not answer until you paste the token.";
  }
}

async function saveToken(raw) {
  const rawTrimmed = String(raw || "").trim();
  if (rawTrimmed === "") {
    // Empty save = unpair. The popup reads the three bridge keys with null
    // defaults, so removing them is the same as nulling them.
    await chrome.storage.local.remove(["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"]);
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
  // popup reads "Not tried yet" (not a stale "App not reachable") until the
  // next intent or "Simulate intent" proves the pairing.
  await chrome.storage.local.set({ saBridgeToken: t, bridgeOk: null, bridgeAt: null, bridgeWhy: null });
  await renderToken();
}

// ---- Mode -------------------------------------------------------------------

async function renderMode() {
  const { saMode } = await state();
  document.querySelectorAll('input[name="mode"]').forEach((r) => { r.checked = r.value === saMode; });
  $("listed-card").hidden = saMode !== "listed";
  $("everywhere-card").hidden = saMode !== "everywhere";
  $("mode-note").textContent = saMode === "everywhere"
    ? "The Angel is watching every http/https site you open, except the paused ones."
    : "The Angel only runs on the sites you've enabled below — nothing else.";
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
    tag.textContent = granted ? "watching" : "pending";
    li.appendChild(tag);

    if (!granted) {
      const grant = mkBtn("Grant", "link-btn grant", async () => {
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

async function renderAll() {
  await renderToken();
  await renderMode();
  await renderListed();
  await renderBlocked();
}

document.addEventListener("DOMContentLoaded", async () => {
  await renderAll();

  $("token-form").addEventListener("submit", (e) => { e.preventDefault(); saveToken($("token-input").value); });
  document.querySelectorAll('input[name="mode"]').forEach((r) => {
    r.addEventListener("change", () => setMode(r.value));
  });
  $("add-form").addEventListener("submit", (e) => { e.preventDefault(); addSite($("add-input").value); });
  $("pause-form").addEventListener("submit", (e) => { e.preventDefault(); addBlocked($("pause-input").value); });
  $("enable-all").addEventListener("click", enableAll);

  chrome.permissions.onAdded.addListener(renderListed);
  chrome.permissions.onRemoved.addListener(renderListed);
});
