// Spending Angel — sensor service worker.
//
// Forwards detected checkout intents to the macOS app's localhost bridge. We do
// the fetch HERE (not in the content script) because the service worker is a
// secure extension context that can reach http://127.0.0.1 without the page's
// mixed-content / private-network restrictions.

const BRIDGE_URL = `http://127.0.0.1:17865/intent`;

chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === "checkout_intent") forward(msg);
  // No async response needed — fire and forget.
});

async function forward(payload) {
  try {
    await fetch(BRIDGE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    chrome.storage.local.set({ bridgeOk: true, bridgeAt: Date.now() });
  } catch (e) {
    // App not running / not reachable. Surfaced in the debug popup.
    chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now() });
  }
}
