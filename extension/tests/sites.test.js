// Spending Angel — site-model tests (M-F2).
// Run with: node --test extension/tests/*.test.js

const { test } = require("node:test");
const assert = require("node:assert");
const {
  saNormalizeHost, saHostToOrigins, saShouldWatch, saHostInList,
  saAddToList, saRemoveFromList,
} = require("../sites.js");

// --- saNormalizeHost ---

test("normalizes full URLs to a bare host", () => {
  assert.equal(saNormalizeHost("https://www.amazon.com/dp/B0123?x=1"), "amazon.com");
  assert.equal(saNormalizeHost("http://Shop.Example.CO.uk/cart"), "shop.example.co.uk");
});

test("normalizes bare hosts with cruft", () => {
  assert.equal(saNormalizeHost("www.ebay.com"), "ebay.com");
  assert.equal(saNormalizeHost("mercadolibre.com.do/p/123"), "mercadolibre.com.do");
  assert.equal(saNormalizeHost("shop.example.com:8443"), "shop.example.com");
});

test("rejects non-watchable inputs", () => {
  for (const bad of ["", null, undefined, "chrome://extensions", "about:blank",
                     "file:///Users/x", "localhost", "newtab", "no dots here"]) {
    assert.equal(saNormalizeHost(bad), "", `should reject: ${bad}`);
  }
});

// --- saHostToOrigins ---

test("bare host covers itself and subdomains", () => {
  assert.deepEqual(saHostToOrigins("amazon.com"), ["*://amazon.com/*", "*://*.amazon.com/*"]);
});

test("wildcard entry covers subdomains only", () => {
  assert.deepEqual(saHostToOrigins("*.myshopify.com"), ["*://*.myshopify.com/*"]);
});

// --- saHostInList ---

const LIST = ["amazon.com", "*.myshopify.com"];

test("matches bare host and its subdomains", () => {
  assert.ok(saHostInList("amazon.com", LIST));
  assert.ok(saHostInList("smile.amazon.com", LIST));
  assert.ok(saHostInList("https://www.amazon.com/cart", LIST));
});

test("wildcard matches subdomains only", () => {
  assert.ok(saHostInList("cool.myshopify.com", LIST));
  assert.ok(!saHostInList("myshopify.com", LIST));
});

test("does not match lookalikes", () => {
  assert.ok(!saHostInList("notamazon.com", LIST));
  assert.ok(!saHostInList("amazon.com.evil.io", LIST));
});

// --- saShouldWatch ---

test("listed mode watches only allowlisted hosts", () => {
  const cfg = { mode: "listed", allowlist: ["amazon.com"], blocklist: [] };
  assert.ok(saShouldWatch("www.amazon.com", cfg));
  assert.ok(!saShouldWatch("ebay.com", cfg));
});

test("everywhere mode watches all but blocklisted hosts", () => {
  const cfg = { mode: "everywhere", allowlist: [], blocklist: ["wikipedia.org"] };
  assert.ok(saShouldWatch("random-shop.com", cfg));
  assert.ok(!saShouldWatch("en.wikipedia.org", cfg));
});

test("never watches non-watchable hosts", () => {
  assert.ok(!saShouldWatch("chrome://extensions", { mode: "everywhere", allowlist: [], blocklist: [] }));
});

// --- add / remove ---

test("add is normalized, sorted, de-duped", () => {
  let list = [];
  list = saAddToList(list, "https://www.ebay.com/x");
  list = saAddToList(list, "amazon.com");
  list = saAddToList(list, "amazon.com"); // dupe
  assert.deepEqual(list, ["amazon.com", "ebay.com"]);
});

test("add ignores junk", () => {
  assert.deepEqual(saAddToList(["amazon.com"], "chrome://x"), ["amazon.com"]);
});

test("remove takes a host or a URL", () => {
  assert.deepEqual(saRemoveFromList(["amazon.com", "ebay.com"], "https://www.amazon.com/"), ["ebay.com"]);
  assert.deepEqual(saRemoveFromList(["amazon.com", "ebay.com"], "ebay.com"), ["amazon.com"]);
});
