// Spending Angel — SENSOR content script.
//
// This is now a thin, render-nothing sensor. Its only job: detect checkout
// intent (a matched-domain page load, or a buy/checkout button click) and emit
// a structured event. The macOS app is the brain — it owns the goal, the
// character, the sound, mute/snooze, and every pixel of UI. The sensor decides
// nothing and shows nothing.
//
// Detection logic lives in detect.js (pure, unit-tested); structured logging
// in log.js. Both are loaded before this file via the manifest.

(() => {
  // Stops the same click/load from firing twice in quick succession.
  const COOLDOWN_MS = 1500;
  let lastTrigger = 0;

  // The one and only output of the sensor.
  function sendIntent(trigger) {
    const now = Date.now();
    if (now - lastTrigger < COOLDOWN_MS) return;
    lastTrigger = now;

    const payload = {
      // Trace id: minted here at detection time, logged by the app at every
      // step — one catch is traceable end to end across both halves.
      id: crypto.randomUUID(),
      type: "checkout_intent",
      trigger,                                       // "click" | "load"
      hostname: location.hostname.replace(/^www\./, ""),
      ts: now,
    };

    // No price, no page content, nothing personal — privacy is a core
    // principle. We emit the signal that intent happened, and that's it.
    saLog("info", "sensor.intent", `${trigger} on ${payload.hostname}`, { intent_id: payload.id });
    chrome.storage.local.set({ lastIntent: payload });

    // Forward to the macOS app via the service worker — it can reach
    // http://127.0.0.1 without the page's mixed-content / private-network limits.
    chrome.runtime.sendMessage(payload).catch(() => {});
  }

  function isBuyButton(el) {
    if (!el || !el.matches) return false;
    if (!el.matches("button, a, input[type='submit'], input[type='button'], [role='button']")) return false;
    const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
    return saIsBuyButtonText(text);
  }

  function findBuyButtonAncestor(target) {
    // Walk up a few steps — buy buttons often wrap icon spans.
    let el = target;
    for (let i = 0; i < 4 && el; i++) {
      if (isBuyButton(el)) return el;
      el = el.parentElement;
    }
    return null;
  }

  function attachClickWatcher() {
    document.addEventListener("click", e => {
      if (findBuyButtonAncestor(e.target)) sendIntent("click");
    }, true);
  }

  function main() {
    // Click path is always live — it's the reliable, gesture-backed signal.
    attachClickWatcher();

    // Load path: only on a known shopping domain.
    const list = typeof SPENDING_ANGEL_DOMAINS !== "undefined" ? SPENDING_ANGEL_DOMAINS : [];
    if (saHostnameMatches(location.hostname, list)) {
      setTimeout(() => sendIntent("load"), 800); // let first paint settle
    }
  }

  main();
})();
