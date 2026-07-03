// Spending Angel — options page. Full site-list management.
//
// Listed mode: an allowlist of sites; each needs a host-permission grant (a
// Chrome gesture) before the sensor can actually run there. Everywhere mode: a
// blocklist of sites to leave alone. All local — nothing is sent anywhere.

const $ = (id) => document.getElementById(id);

async function state() {
  return chrome.storage.local.get({ saMode: "listed", saAllowlist: [], saBlocklist: [] });
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
    tag.textContent = granted ? "watching" : "needs permission";
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
  await renderMode();
  await renderListed();
  await renderBlocked();
}

document.addEventListener("DOMContentLoaded", async () => {
  await renderAll();

  document.querySelectorAll('input[name="mode"]').forEach((r) => {
    r.addEventListener("change", () => setMode(r.value));
  });
  $("add-form").addEventListener("submit", (e) => { e.preventDefault(); addSite($("add-input").value); });
  $("pause-form").addEventListener("submit", (e) => { e.preventDefault(); addBlocked($("pause-input").value); });
  $("enable-all").addEventListener("click", enableAll);

  chrome.permissions.onAdded.addListener(renderListed);
  chrome.permissions.onRemoved.addListener(renderListed);
});
