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

function saHostnameMatches(host, list) {
  host = host.replace(/^www\./, "");
  return list.some(p => {
    if (p.startsWith("*.")) return host.endsWith(p.slice(1));
    return host === p || host.endsWith("." + p);
  });
}

if (typeof module !== "undefined") {
  module.exports = { SA_BUTTON_TEXT_RE, saIsBuyButtonText, saHostnameMatches };
}
