// Spending Angel — sensor debug popup.
//
// Shows the last detected intent + whether the macOS app is reachable, and lets
// you fire a fake intent through the whole pipeline. The real controls (goal,
// character, mute, snooze) live in the macOS app, not here.

const $ = id => document.getElementById(id);

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

// Last few structured log lines (the ring buffer log.js maintains).
function renderEvents(logs) {
  if (!logs || !logs.length) { $("events").textContent = "none yet"; return }
  $("events").textContent = logs.slice(-8).map(l => {
    const t = l.ts ? l.ts.slice(11, 19) : "";
    return `${t} ${l.level === "error" ? "✕" : "·"} ${l.event} ${l.msg}`;
  }).join("\n");
}

async function load() {
  const s = await chrome.storage.local.get({ lastIntent: null, bridgeOk: null, bridgeAt: null, saLogs: [] });
  renderIntent(s.lastIntent);
  renderBridge(s.bridgeOk, s.bridgeAt);
  renderEvents(s.saLogs);
}

document.addEventListener("DOMContentLoaded", async () => {
  await load();

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
    if (changes.bridgeOk || changes.bridgeAt) load();
  });
});
