// Spending Angel — pure detection logic.
//
// No chrome.* and no DOM in here: this file is shared by content.js (loaded
// before it via the manifest) and the unit tests in tests/ (loaded via
// require). Detection *semantics* are tuned in M-F2; M-F1 only made them
// testable.

// Unicode-aware word boundaries: JS \b treats accented letters as non-word, so
// plain \b would let "pagar" match inside "pagaré". The lookarounds require a
// real non-letter/non-digit (or string edge) on both sides.
var SA_BUTTON_TEXT_RE = /(?<![\p{L}\p{N}])(add to cart|add to bag|buy now|checkout|proceed to checkout|place order|complete purchase|comprar|añadir al carrito|agregar al carrito|finalizar compra|pagar)(?![\p{L}\p{N}])/iu;

function saIsBuyButtonText(text) {
  if (!text) return false;
  return SA_BUTTON_TEXT_RE.test(text);
}

// Stricter test for links (<a>): the text must BE a buy phrase, not merely
// contain one — so "Checkout our blog" or "Ways to pay" don't summon a
// character, while an actual "Checkout" / "Pagar" link still does. Real buy
// buttons are short; anything long is prose, not a CTA.
var SA_WHOLE_BUY_RE = /^(add to cart|add to bag|buy now|checkout|proceed to checkout|place order|complete purchase|comprar|añadir al carrito|agregar al carrito|finalizar compra|pagar)$/iu;

function saIsWholeBuyPhrase(text) {
  if (!text) return false;
  const t = text.trim().toLowerCase().replace(/[.!¡·•\s]+$/u, "");
  return SA_WHOLE_BUY_RE.test(t) || (t.length <= 24 && SA_BUTTON_TEXT_RE.test(t));
}

// Visibility gate (pure): reject zero-size / hidden elements so buy buttons in
// collapsed menus, hidden templates, or off-screen carousels don't false-fire.
// Caller passes the measured box + computed style.
function saElementIsVisible({ width, height, display, visibility, opacity }) {
  if (display === "none" || visibility === "hidden" || visibility === "collapse") return false;
  if (opacity !== undefined && Number(opacity) === 0) return false;
  return width > 0 && height > 0;
}

function saHostnameMatches(host, list) {
  host = host.replace(/^www\./, "");
  return list.some(p => {
    if (p.startsWith("*.")) return host.endsWith(p.slice(1));
    return host === p || host.endsWith("." + p);
  });
}

if (typeof module !== "undefined") {
  module.exports = {
    SA_BUTTON_TEXT_RE, saIsBuyButtonText, saIsWholeBuyPhrase,
    saElementIsVisible, saHostnameMatches,
  };
}
