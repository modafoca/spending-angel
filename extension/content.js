// Spending Angel — SENSOR content script.
//
// A thin, render-nothing sensor. It only runs where the user has chosen to be
// watched (the service worker injects it per-site — see background.js). Its job:
// detect checkout intent (a matched-domain page load, or a buy/checkout button
// click) and emit a structured event. The macOS app is the brain — it owns the
// goal, the character, the sound, mute/snooze, and every pixel of UI.
//
// The page is hostile. Two rules keep it honest:
//   * Only user-gesture clicks count (e.isTrusted) — a page dispatching
//     synthetic MouseEvents on its own "Buy now" cannot summon a character.
//   * The user's site policy (mode + lists) is re-read from storage on EVERY
//     event, never captured at injection, and a denied event is dropped
//     silently — no log line, so a paused site's name never reaches the ring.
//     Chrome does not remove an already injected script when the service
//     worker unregisters it, so a tab paused or unlisted after load must go
//     quiet without a navigation.
//
// Loaded after domains.js, log.js, detect.js, sites.js (which define the
// globals used below).

(() => {
  const COOLDOWN_MS = 1500;
  let lastTrigger = 0;

  const host = saNormalizeHost(location.hostname) || location.hostname.replace(/^www\./, "");
  const domainList = typeof SPENDING_ANGEL_DOMAINS !== "undefined" ? SPENDING_ANGEL_DOMAINS : [];

  async function sendIntent(trigger) {
    try {
      // Cooldown gate + stamp happen synchronously, before any await, so two
      // events in the same tick cannot both pass.
      const now = Date.now();
      if (now - lastTrigger < COOLDOWN_MS) return;
      lastTrigger = now;

      // Policy is judged now, not at injection (EXT-01). saShouldWatch is the
      // single oracle: listed → host in allowlist; everywhere → not blocklisted.
      const cfg = await chrome.storage.local.get({ saMode: "listed", saAllowlist: [], saBlocklist: [] });
      if (!saShouldWatch(host, { mode: cfg.saMode, allowlist: cfg.saAllowlist, blocklist: cfg.saBlocklist })) {
        // Not watched right now: nothing is logged, stored or sent (review R-01).
        // A paused site is the user's "leave me alone" — its name must not land
        // in the console or the saLogs ring, and the popup must not learn of it.
        return;
      }

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
      // Both calls below are fire-and-forget with their own .catch: the try/catch
      // around us only sees a synchronous throw, not a rejected promise.
      saLog("info", "sensor.intent", `${trigger} on ${payload.hostname}`, { intent_id: payload.id });
      chrome.storage.local.set({ lastIntent: payload }).catch(() => {});
      chrome.runtime.sendMessage(payload).catch(() => {});
    } catch (e) {
      // Extension context invalidated (reload/uninstall) while this tab still
      // holds the old script — chrome.* throws; nothing to do, stay silent.
    }
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
      // Script-dispatched clicks are dropped at the door (EXT-02): no log, no
      // storage write, so a synthetic-click flood cannot thrash saLogs either.
      if (!e.isTrusted) return;
      if (findBuyButtonAncestor(e.target)) void sendIntent("click");
    }, true);
  }

  async function main() {
    // Click path: always attached wherever we run. Policy is evaluated per
    // event, so a tab paused now can be resumed later without a navigation.
    attachClickWatcher();

    // Load path: fire on any watched site in "listed" mode (the user chose it),
    // but only on known shopping domains in "everywhere" mode (so a random blog
    // load doesn't summon a character). The scheduled sendIntent re-checks
    // policy at fire time, so a site unlisted during the 800 ms never fires.
    const cfg = await chrome.storage.local.get({ saMode: "listed" });
    const watchedByChoice = cfg.saMode === "listed";
    const knownShop = saHostnameMatches(location.hostname, domainList);
    if (watchedByChoice || knownShop) {
      setTimeout(() => { void sendIntent("load"); }, 800); // let first paint settle
    }
  }

  // Boot is fire-and-forget; a storage read that rejects at injection time
  // (context already invalidated) must not surface in the page's console.
  void main().catch(() => {});
})();
