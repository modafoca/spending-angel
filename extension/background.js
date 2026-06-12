// Spending Angel — sensor service worker.
//
// Forwards detected checkout intents to the macOS app's localhost bridge. We do
// the fetch HERE (not in the content script) because the service worker is a
// secure extension context that can reach http://127.0.0.1 without the page's
// mixed-content / private-network restrictions.

importScripts("log.js");

const BRIDGE_URL = `http://127.0.0.1:17865/intent`;

chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === "checkout_intent") forward(msg);
  // No async response needed — fire and forget.
});

async function forward(payload) {
  const t0 = Date.now();
  try {
    const res = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (res.ok) {
      saLog("info", "bridge.forwarded", payload.hostname,
            { intent_id: payload.id, ms: Date.now() - t0 });
    } else {
      // The app answered but rejected it — 429 = throttled (a catch is already
      // on screen), 400 = the app didn't like the payload.
      saLog("info", "bridge.rejected", `app answered ${res.status}`,
            { intent_id: payload.id, status: res.status });
    }
    chrome.storage.local.set({ bridgeOk: true, bridgeAt: Date.now() });
  } catch (e) {
    // App not running / not reachable. Surfaced in the debug popup.
    saLog("error", "bridge.unreachable", "is the Spending Angel app running?",
          { intent_id: payload.id });
    chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now() });
  }
}
