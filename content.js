// Spending Angel — content script.
//
// Runs on every page. Two paths:
//   1. Domain match → maybe pop the angel on page load.
//   2. Click on a buy/checkout button → pop the angel regardless.
//
// State lives in chrome.storage.local; we watch for changes so popup edits
// take effect without a page reload.

(() => {
  const BUTTON_TEXT_RE = /\b(add to cart|add to bag|buy now|checkout|proceed to checkout|place order|complete purchase|comprar|añadir al carrito|agregar al carrito|finalizar compra|pagar)\b/i;

  // Cooldown stops the same click from firing twice and keeps the sound from
  // stacking when buttons are clicked rapidly. Not in the brief, but the
  // alternative is genuinely annoying.
  const COOLDOWN_MS = 1500;

  let state = null;
  let lastTrigger = 0;

  function hostnameMatches(host, list) {
    host = host.replace(/^www\./, "");
    return list.some(p => {
      if (p.startsWith("*.")) return host.endsWith(p.slice(1));
      return host === p || host.endsWith("." + p);
    });
  }

  function isMuted() {
    const host = location.hostname.replace(/^www\./, "");
    return (state.mutedDomains || []).includes(host);
  }

  function angelMessage() {
    const goal = (state.goal || "").trim();
    return goal
      ? `Hey. Stop. You're saving for ${goal}.`
      : "Hey. Stop. Don't do that.";
  }

  function playSound() {
    try {
      const url = chrome.runtime.getURL(`sounds/${state.selectedSound || "stop.mp3"}`);
      const audio = new Audio(url);
      audio.volume = Math.max(0, Math.min(1, state.volume ?? 0.7));
      // .play() returns a promise that rejects if autoplay is blocked or the
      // file is missing/empty. Either way: stay silent and keep the visual.
      audio.play().catch(() => {});
    } catch (_) {}
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]));
  }

  function renderOverlay() {
    document.getElementById("spending-angel-overlay")?.remove();

    const card = document.createElement("div");
    card.id = "spending-angel-overlay";
    card.className = "spending-angel-card";
    card.setAttribute("role", "alert");
    card.innerHTML = `
      <div class="spending-angel-angel" aria-hidden="true">
        <svg viewBox="0 0 100 100" width="92" height="92" xmlns="http://www.w3.org/2000/svg">
          <ellipse cx="50" cy="78" rx="22" ry="5" fill="#1d2f57" opacity="0.14"/>
          <path d="M28 56 Q12 50 16 72 Q26 64 34 64 Z" fill="#fff" stroke="#1d2f57" stroke-width="2.5" stroke-linejoin="round"/>
          <path d="M72 56 Q88 50 84 72 Q74 64 66 64 Z" fill="#fff" stroke="#1d2f57" stroke-width="2.5" stroke-linejoin="round"/>
          <ellipse cx="50" cy="44" rx="22" ry="24" fill="#fde9c9" stroke="#1d2f57" stroke-width="2.5"/>
          <ellipse cx="50" cy="20" rx="18" ry="5" fill="none" stroke="#f4b740" stroke-width="3"/>
          <circle cx="42" cy="44" r="2.6" fill="#1d2f57"/>
          <circle cx="58" cy="44" r="2.6" fill="#1d2f57"/>
          <path d="M40 38 Q42 34 46 36" fill="none" stroke="#1d2f57" stroke-width="2" stroke-linecap="round"/>
          <path d="M54 36 Q58 34 60 38" fill="none" stroke="#1d2f57" stroke-width="2" stroke-linecap="round"/>
          <path d="M42 56 Q50 51 58 56" fill="none" stroke="#1d2f57" stroke-width="2.4" stroke-linecap="round"/>
        </svg>
      </div>
      <div class="spending-angel-bubble">
        <p class="spending-angel-msg">${escapeHtml(angelMessage())}</p>
      </div>
    `;
    card.addEventListener("click", () => card.remove());
    document.documentElement.appendChild(card);

    setTimeout(() => {
      card.classList.add("spending-angel-poof");
      setTimeout(() => card.remove(), 350);
    }, 4000);
  }

  function trigger() {
    if (!state || !state.enabled || !state.onboarded) return;
    if (isMuted()) return;
    const now = Date.now();
    if (now - lastTrigger < COOLDOWN_MS) return;
    lastTrigger = now;
    playSound();
    renderOverlay();
  }

  function isBuyButton(el) {
    if (!el || !el.matches) return false;
    if (!el.matches("button, a, input[type='submit'], input[type='button'], [role='button']")) return false;
    const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").trim();
    if (!text) return false;
    return BUTTON_TEXT_RE.test(text);
  }

  function findBuyButtonAncestor(target) {
    // Walk up a few steps — buy buttons often have icon spans inside.
    let el = target;
    for (let i = 0; i < 4 && el; i++) {
      if (isBuyButton(el)) return el;
      el = el.parentElement;
    }
    return null;
  }

  function attachClickWatcher() {
    document.addEventListener("click", e => {
      if (!state || state.triggerMode === "load") return;
      if (findBuyButtonAncestor(e.target)) trigger();
    }, true);
  }

  async function loadState() {
    state = await chrome.storage.local.get({
      enabled: true,
      goal: "",
      selectedSound: "stop.mp3",
      volume: 0.7,
      triggerMode: "both",
      mutedDomains: [],
      onboarded: false,
    });
  }

  function watchStorage() {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== "local" || !state) return;
      for (const [k, { newValue }] of Object.entries(changes)) {
        state[k] = newValue;
      }
    });
  }

  async function main() {
    await loadState();
    if (!state.onboarded) return;

    watchStorage();
    attachClickWatcher();

    if (state.enabled && state.triggerMode !== "click") {
      const matched = hostnameMatches(
        location.hostname,
        typeof SPENDING_ANGEL_DOMAINS !== "undefined" ? SPENDING_ANGEL_DOMAINS : []
      );
      // Small delay so we don't compete with first paint.
      if (matched) setTimeout(trigger, 800);
    }
  }

  main();
})();
