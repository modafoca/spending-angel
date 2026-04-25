// Spending Angel — popup script.
// Reads + writes chrome.storage.local. The content script listens for
// changes, so edits here apply to every open tab without a reload.

const DEFAULTS = {
  enabled: true,
  goal: "",
  selectedSound: "stop.mp3",
  volume: 0.7,
  triggerMode: "both",
  mutedDomains: [],
};

const $ = id => document.getElementById(id);

function debounce(fn, ms) {
  let t;
  return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
}

function hostnameMatches(host, list) {
  return list.some(p => {
    if (p.startsWith("*.")) return host.endsWith(p.slice(1));
    return host === p || host.endsWith("." + p);
  });
}

async function getActiveHost() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url) return null;
  try {
    return new URL(tab.url).hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

async function renderMuteRow(state) {
  const host = await getActiveHost();
  const row = $("mute-row");
  const list = window.SPENDING_ANGEL_DOMAINS || [];
  if (!host || !hostnameMatches(host, list)) {
    row.hidden = true;
    return;
  }
  const muted = (state.mutedDomains || []).includes(host);
  row.hidden = false;
  $("mute-btn").textContent = muted ? `Unmute ${host}` : `Mute ${host}`;
  $("mute-btn").dataset.host = host;
  $("mute-btn").dataset.muted = String(muted);
}

function setEnabledLabel(enabled) {
  $("enabled-label").textContent = enabled ? "Angel is awake" : "Angel is sleeping 😴";
}

async function load() {
  const s = await chrome.storage.local.get(DEFAULTS);
  $("goal").value = s.goal || "";
  $("enabled").checked = !!s.enabled;
  setEnabledLabel(s.enabled);
  $("sound").value = s.selectedSound;
  $("volume").value = s.volume;
  document.querySelectorAll('input[name="trigger"]').forEach(r => {
    r.checked = (r.value === s.triggerMode);
  });
  await renderMuteRow(s);
}

async function save(patch) {
  await chrome.storage.local.set(patch);
}

document.addEventListener("DOMContentLoaded", async () => {
  await load();

  $("goal").addEventListener(
    "input",
    debounce(e => save({ goal: e.target.value.trim() }), 250)
  );

  $("enabled").addEventListener("change", e => {
    setEnabledLabel(e.target.checked);
    save({ enabled: e.target.checked });
  });

  $("sound").addEventListener("change", e => save({ selectedSound: e.target.value }));
  $("volume").addEventListener("input", e => save({ volume: parseFloat(e.target.value) }));

  document.querySelectorAll('input[name="trigger"]').forEach(r => {
    r.addEventListener("change", () => {
      const sel = document.querySelector('input[name="trigger"]:checked');
      if (sel) save({ triggerMode: sel.value });
    });
  });

  $("mute-btn").addEventListener("click", async () => {
    const btn = $("mute-btn");
    const host = btn.dataset.host;
    const wasMuted = btn.dataset.muted === "true";
    const s = await chrome.storage.local.get({ mutedDomains: [] });
    let list = s.mutedDomains || [];
    list = wasMuted
      ? list.filter(h => h !== host)
      : list.includes(host) ? list : [...list, host];
    await save({ mutedDomains: list });
    await renderMuteRow({ mutedDomains: list });
  });
});
