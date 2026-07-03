// Spending Angel — SENSOR content script.
//
// A thin, render-nothing sensor. It only runs where the user has chosen to be
// watched (the service worker injects it per-site — see background.js). Its job:
// detect checkout intent (a matched-domain page load, or a buy/checkout button
// click) and emit a structured event. The macOS app is the brain — it owns the
// goal, the character, the sound, mute/snooze, and every pixel of UI.
//
// Loaded after domains.js, log.js, detect.js, sites.js (which define the
// globals used below).

(() => {
  const COOLDOWN_MS = 1500;
  let lastTrigger = 0;

  const host = saNormalizeHost(location.hostname) || location.hostname.replace(/^www\./, "");
  const domainList = typeof SPENDING_ANGEL_DOMAINS !== "undefined" ? SPENDING_ANGEL_DOMAINS : [];

  function sendIntent(trigger) {
    const now = Date.now();
    if (now - lastTrigger < COOLDOWN_MS) return;
    lastTrigger = now;

    const payload = {
      // Trace id: minted here, logged by the app at every step — one catch is
      // traceable end to end across both halves.
      id: crypto.randomUUID(),
      type: "checkout_intent",
      trigger,                                       // "click" | "load"
      hostname: host,
      ts: now,
    };

    // No price, no page content, nothing personal — privacy is a core principle.
    saLog("info", "sensor.intent", `${trigger} on ${payload.hostname}`, { intent_id: payload.id });
    chrome.storage.local.set({ lastIntent: payload });
    chrome.runtime.sendMessage(payload).catch(() => {});
  }

  // Is this element a real, visible buy control? Links are held to a stricter
  // test than buttons (see detect.js) because prose links are the main source
  // of "checkout"/"pagar" false positives.
  function isBuyButton(el) {
    if (!el || !el.matches) return false;
    const isLink = el.matches("a");
    if (!el.matches("button, a, input[type='submit'], input[type='button'], [role='button']")) return false;

    const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
    const textMatch = isLink ? saIsWholeBuyPhrase(text) : saIsBuyButtonText(text);
    if (!textMatch) return false;

    // Visibility gate — skip hidden/zero-size controls.
    const rect = el.getBoundingClientRect();
    const style = getComputedStyle(el);
    return saElementIsVisible({
      width: rect.width, height: rect.height,
      display: style.display, visibility: style.visibility, opacity: style.opacity,
    });
  }

  function findBuyButtonAncestor(target) {
    let el = target;
    for (let i = 0; i < 4 && el; i++) {
      if (isBuyButton(el)) return el;
      el = el.parentElement;
    }
    return null;
  }

  function attachClickWatcher() {
    document.addEventListener("click", (e) => {
      if (findBuyButtonAncestor(e.target)) sendIntent("click");
    }, true);
  }

  async function main() {
    const cfg = await chrome.storage.local.get({ saMode: "listed", saBlocklist: [] });

    // In "everywhere" mode the script runs on all sites; honor the blocklist.
    if (cfg.saMode === "everywhere" && saHostInList(host, cfg.saBlocklist)) {
      saLog("debug", "sensor.blocked", `${host} is on the pause list`);
      return;
    }

    // Click path: always live wherever we run — the reliable, gesture-backed signal.
    attachClickWatcher();

    // Load path: fire on any watched site in "listed" mode (the user chose it),
    // but only on known shopping domains in "everywhere" mode (so a random blog
    // load doesn't summon a character).
    const watchedByChoice = cfg.saMode === "listed";
    const knownShop = saHostnameMatches(location.hostname, domainList);
    if (watchedByChoice || knownShop) {
      setTimeout(() => sendIntent("load"), 800); // let first paint settle
    }
  }

  main();
})();
