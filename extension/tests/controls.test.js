const { test } = require("node:test");
const assert = require("node:assert/strict");
const { loadOptions, loadPopup } = require("./harness");
const TOKEN = "a".repeat(64);

test("popup keeps setup visible until the app confirms the saved code", async () => {
  const h = loadPopup({ tabUrl: "https://shop.test", config: {} });
  await h.domReady();
  assert.equal(h.el("setup-card").hidden, false);
  assert.equal(h.el("site-card").hidden, true);
  h.el("setup-connect").listeners.click[0]();
  assert.equal(h.openedOptions, 1);
  h.setConfig({ saBridgeToken: TOKEN });
  h.storageChanged({ saBridgeToken: { newValue: TOKEN } });
  await h.tick();
  assert.equal(h.el("setup-card").hidden, false);
  h.setConfig({ bridgeOk: true });
  h.storageChanged({ bridgeOk: { newValue: true } });
  await h.tick();
  assert.equal(h.el("setup-card").hidden, true);
  assert.equal(h.el("site-card").hidden, false);
  assert.match(h.el("bridge-status").textContent, /^Last connected/);
});

test("Settings keeps setup open until confirmation and never erases an in-progress paste", async () => {
  const h = loadOptions({ config: {} });
  await h.ctx.renderToken();
  assert.equal(h.el("pair-card").open, true);
  await h.ctx.saveToken(TOKEN);
  assert.equal(h.el("pair-card").open, true);
  h.setConfig({ bridgeOk: true });
  await h.ctx.renderToken();
  assert.equal(h.el("pair-card").open, false);
  h.el("pair-card").open = true;
  h.el("token-input").value = "paste in progress";
  await h.ctx.renderToken();
  assert.equal(h.el("pair-card").open, true);
  assert.equal(h.el("token-input").value, "paste in progress");
});

test("empty Save preserves pairing; explicit Disconnect removes it", async () => {
  const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: true } });
  await h.domReady();
  h.el("token-form").listeners.submit[0]({ preventDefault() {} });
  await h.tick();
  assert.equal(h.store.saBridgeToken, TOKEN);
  assert.equal(h.removes.length, 0);
  h.el("disconnect").listeners.click[0]();
  await h.tick();
  assert.equal(h.store.saBridgeToken, undefined);
  assert.equal(h.el("pair-card").open, true);
});

test("Pause here immediately changes policy and Watch this site restores it", async () => {
  const h = loadPopup({ tabUrl: "https://shop.test", config: {
    saBridgeToken: TOKEN, saMode: "listed", saAllowlist: ["shop.test"],
  } });
  await h.domReady();
  assert.equal(h.el("site-action").textContent, "Pause here");
  await h.ctx.onSiteAction();
  assert.deepEqual([...h.store.saAllowlist], []);
  assert.equal(h.el("site-action").textContent, "Watch this site");
  await h.ctx.onSiteAction();
  assert.deepEqual([...h.store.saAllowlist], ["shop.test"]);
});

test("everywhere Pause here and Resume here retain the existing blocklist behavior", async () => {
  const h = loadPopup({ tabUrl: "https://shop.test", config: {
    saBridgeToken: TOKEN, saMode: "everywhere", saBlocklist: [],
  } });
  await h.domReady();
  await h.ctx.onSiteAction();
  assert.deepEqual([...h.store.saBlocklist], ["shop.test"]);
  assert.equal(h.el("site-action").textContent, "Resume here");
  await h.ctx.onSiteAction();
  assert.deepEqual([...h.store.saBlocklist], []);
});

test("diagnostics remain available in Settings without including the connection code", async () => {
  const h = loadOptions({ config: { saBridgeToken: TOKEN, lastIntent: { hostname: "shop.test" },
    saLogs: [{ ts: "2026-09-20T10:00:00Z", event: "catch.performed", msg: "shop.test" }] } });
  await h.domReady();
  assert.match(h.el("last-intent").textContent, /shop.test/);
  assert.match(h.el("events").textContent, /catch.performed/);
  assert.ok(!h.el("last-intent").textContent.includes(TOKEN));
  assert.ok(!h.el("events").textContent.includes(TOKEN));
});
