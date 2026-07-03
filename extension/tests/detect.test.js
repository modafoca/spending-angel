// Spending Angel — sensor detection tests (M-F1).
// Run with: node --test extension/tests/
// These pin the CURRENT detection semantics; tightening (length caps,
// visibility checks, regex narrowing) is M-F2 and will update these.

const { test } = require("node:test");
const assert = require("node:assert");
const {
  saIsBuyButtonText, saIsWholeBuyPhrase, saElementIsVisible, saHostnameMatches,
} = require("../detect.js");

// --- Buy-button text ---

test("matches the classic buy phrases", () => {
  for (const t of ["Add to Cart", "ADD TO BAG", "Buy Now", "Checkout",
                   "Proceed to checkout", "Place order", "Complete purchase"]) {
    assert.ok(saIsBuyButtonText(t), `should match: ${t}`);
  }
});

test("matches the Spanish buy phrases", () => {
  for (const t of ["Comprar", "Añadir al carrito", "Agregar al carrito",
                   "Finalizar compra", "Pagar"]) {
    assert.ok(saIsBuyButtonText(t), `should match: ${t}`);
  }
});

test("matches phrases embedded in longer button text", () => {
  assert.ok(saIsBuyButtonText("🛒 Add to cart — only 2 left!"));
});

test("ignores ordinary navigation text", () => {
  for (const t of ["Continue shopping", "Sign in", "View details",
                   "Add to wishlist", "Compare", "", null]) {
    assert.ok(!saIsBuyButtonText(t), `should NOT match: ${t}`);
  }
});

test("does not match partial words", () => {
  // \b word boundaries: "pagaré" must not trip the "pagar" rule.
  assert.ok(!saIsBuyButtonText("pagaré mañana"));
  assert.ok(!saIsBuyButtonText("checkouts")); // plural is a different word
});

// --- Hostname matching ---

const LIST = ["amazon.com", "*.myshopify.com", "store.steampowered.com"];

test("matches the bare domain and its subdomains", () => {
  assert.ok(saHostnameMatches("amazon.com", LIST));
  assert.ok(saHostnameMatches("www.amazon.com", LIST));
  assert.ok(saHostnameMatches("smile.amazon.com", LIST));
});

test("wildcard matches subdomains only", () => {
  assert.ok(saHostnameMatches("cool-store.myshopify.com", LIST));
  assert.ok(!saHostnameMatches("myshopify.com", LIST));
});

test("does not match lookalike domains", () => {
  assert.ok(!saHostnameMatches("notamazon.com", LIST));
  assert.ok(!saHostnameMatches("amazon.com.evil.io", LIST));
});

test("path-specific entries match their host", () => {
  assert.ok(saHostnameMatches("store.steampowered.com", LIST));
  assert.ok(!saHostnameMatches("steampowered.com", LIST));
});

// --- Link strictness (M-F2): links must BE a buy phrase, not contain one ---

test("whole-phrase test accepts real buy links", () => {
  for (const t of ["Checkout", "Buy now", "Pagar", "Add to cart", "  Comprar  ", "Checkout!"]) {
    assert.ok(saIsWholeBuyPhrase(t), `should accept link text: ${t}`);
  }
});

test("whole-phrase test rejects marketing prose", () => {
  for (const t of ["Checkout our latest blog post", "Ways to pay", "Learn how to buy now and save",
                   "Comprar guía: cómo elegir"]) {
    assert.ok(!saIsWholeBuyPhrase(t), `should reject prose link: ${t}`);
  }
});

test("buttons still match on contained phrase (looser than links)", () => {
  assert.ok(saIsBuyButtonText("🛒 Add to cart — only 2 left!"));
});

// --- Visibility gate (M-F2) ---

test("visible element passes", () => {
  assert.ok(saElementIsVisible({ width: 120, height: 40, display: "block", visibility: "visible", opacity: "1" }));
});

test("hidden / zero-size / transparent elements fail", () => {
  assert.ok(!saElementIsVisible({ width: 0, height: 0, display: "block", visibility: "visible" }));
  assert.ok(!saElementIsVisible({ width: 120, height: 40, display: "none", visibility: "visible" }));
  assert.ok(!saElementIsVisible({ width: 120, height: 40, display: "block", visibility: "hidden" }));
  assert.ok(!saElementIsVisible({ width: 120, height: 40, display: "block", visibility: "visible", opacity: "0" }));
});
