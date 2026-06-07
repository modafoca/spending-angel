// Spending Angel — SENSOR content script.
//
// This is now a thin, render-nothing sensor. Its only job: detect checkout
// intent (a matched-domain page load, or a buy/checkout button click) and emit
// a structured event. The macOS app is the brain — it owns the goal, the
// character, the sound, mute/snooze, and every pixel of UI. The sensor decides
// nothing and shows nothing.
//
// No overlay, no audio, no goal logic. On intent it calls sendIntent().

(() => {
  const BUTTON_TEXT_RE = /\b(add to cart|add to bag|buy now|checkout|proceed to checkout|place order|complete purchase|comprar|añadir al carrito|agregar al carrito|finalizar compra|pagar)\b/i;

  // Stops the same click/load from firing twice in quick succession.
  const COOLDOWN_MS = 1500;
  let lastTrigger = 0;

  function hostnameMatches(host, list) {
    host = host.replace(/^www\./, "");
    return list.some(p => {
      if (p.startsWith("*.")) return host.endsWith(p.slice(1));
      return host === p || host.endsWith("." + p);
    });
  }

  // The one and only output of the sensor.
  function sendIntent(trigger) {
    const now = Date.now();
    if (now - lastTrigger < COOLDOWN_MS) return;
    lastTrigger = now;

    const payload = {
      type: "checkout_intent",
      trigger,                                       // "click" | "load"
      hostname: location.hostname.replace(/^www\./, ""),
      ts: now,
    };

    // No price, no page content, nothing personal — privacy is a core
    // principle. We emit the signal that intent happened, and that's it.
    console.log("[SA sensor]", payload);
    chrome.storage.local.set({ lastIntent: payload });

    // Forward to the macOS app via the service worker — it can reach
    // http://127.0.0.1 without the page's mixed-content / private-network limits.
    chrome.runtime.sendMessage(payload).catch(() => {});
  }

  function isBuyButton(el) {
    if (!el || !el.matches) return false;
    if (!el.matches("button, a, input[type='submit'], input[type='button'], [role='button']")) return false;
    const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
    if (!text) return false;
    return BUTTON_TEXT_RE.test(text);
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
    if (hostnameMatches(location.hostname, list)) {
      setTimeout(() => sendIntent("load"), 800); // let first paint settle
    }
  }

  main();
})();
