// Spending Angel — options + popup pairing-surface tests (NATIVE-01 client).
// Run with: node --test extension/tests/*.test.js
//
// The options page owns the only secret in the system (saBridgeToken) and the
// popup renders the paired / unpaired / rejected states the service worker
// writes. Both scripts are evaluated against a tiny element-by-id DOM stub in
// tests/harness.js — enough to drive renderToken()/saveToken() and
// renderBridge()/loadDebug() without a browser.

const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const { loadOptions, loadPopup } = require("./harness.js");

const TOKEN = "0123456789abcdef".repeat(4);
const TAIL = TOKEN.slice(-4);
const BRIDGE_KEYS = ["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"];

// ---- Options: token form ---------------------------------------------------

describe("options.js pairing card", () => {
  test("renderToken shows the not-paired state when no token is stored", async () => {
    const h = loadOptions({ config: {} });
    await h.ctx.renderToken();
    assert.equal(h.el("token-state").textContent,
      "Not paired — the app will not answer until you paste the token.");
    assert.equal(h.el("token-input").placeholder, "paste the 64-character token");
    assert.equal(h.el("token-input").value, "");
  });

  test("renderToken masks a stored token and shows only its tail", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN } });
    await h.ctx.renderToken();
    assert.equal(h.el("token-state").textContent, `Paired — token ends in …${TAIL}`);
    assert.equal(h.el("token-input").placeholder, `••••…${TAIL}`);
    assert.equal(h.el("token-input").value, "", "the field never carries the real token");
    assert.ok(!h.el("token-input").placeholder.includes(TOKEN.slice(0, 8)), "no leading bytes leak");
  });

  test("renderToken treats a corrupted stored token as not paired", async () => {
    const h = loadOptions({ config: { saBridgeToken: "abc" } });
    await h.ctx.renderToken();
    assert.match(h.el("token-state").textContent, /^Not paired/);
  });

  test("saveToken with a valid token writes token + bridge reset in ONE set", async () => {
    const h = loadOptions({ config: { bridgeOk: false, bridgeAt: 123, bridgeWhy: "unpaired" } });
    h.el("token-input").value = TOKEN;
    await h.ctx.saveToken(h.el("token-input").value);

    assert.equal(h.writes.length, 1);
    assert.deepEqual(h.writes[0], { saBridgeToken: TOKEN, bridgeOk: null, bridgeAt: null, bridgeWhy: null });
    assert.equal(h.removes.length, 0);
    assert.equal(h.store.saBridgeToken, TOKEN);
    assert.equal(h.el("token-input").value, "", "field cleared after save");
    assert.equal(h.el("token-state").textContent, `Paired — token ends in …${TAIL}`);
  });

  test("saveToken lowercases and trims before storing", async () => {
    const h = loadOptions({ config: {} });
    await h.ctx.saveToken("  " + TOKEN.toUpperCase() + "\n");
    assert.equal(h.store.saBridgeToken, TOKEN);
    assert.equal(h.writes.length, 1);
  });

  test("saveToken with junk stores nothing and shows the inline hint", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN } });
    for (const junk of ["abc", TOKEN.slice(0, 40), "g".repeat(64), TOKEN + "0"]) {
      await h.ctx.saveToken(junk);
    }
    assert.equal(h.writes.length, 0);
    assert.equal(h.removes.length, 0);
    assert.equal(h.store.saBridgeToken, TOKEN, "the previously stored token survives");
    assert.equal(h.el("token-state").textContent, "hmm, that doesn't look like a token (64 hex characters)");
  });

  test("saveToken with an empty string unpairs by removing all four bridge keys", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: true, bridgeAt: 5, bridgeWhy: null } });
    await h.ctx.saveToken("");
    assert.equal(h.writes.length, 0);
    assert.equal(h.removes.length, 1);
    assert.deepEqual([...h.removes[0]].sort(), [...BRIDGE_KEYS].sort());
    for (const k of BRIDGE_KEYS) assert.ok(!(k in h.store), `${k} removed`);
    assert.match(h.el("token-state").textContent, /^Not paired/);
  });

  test("saveToken with whitespace-only input also unpairs", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN } });
    await h.ctx.saveToken("   \n");
    assert.equal(h.removes.length, 1);
    assert.ok(!("saBridgeToken" in h.store));
  });

  test("the submit handler wires the form to saveToken", async () => {
    const h = loadOptions({ config: {} });
    await h.domReady();
    const submit = h.el("token-form").listeners.submit;
    assert.ok(submit && submit.length === 1, "one submit listener on #token-form");

    let prevented = false;
    h.el("token-input").value = TOKEN;
    submit[0]({ preventDefault() { prevented = true; } });
    await h.tick();
    await h.tick();
    assert.equal(prevented, true);
    assert.equal(h.store.saBridgeToken, TOKEN);
  });
});

// ---- Popup: bridge status ----------------------------------------------------

describe("popup.js renderBridge", () => {
  const AT = 1_700_000_000_000;

  test("null / undefined → Not tried yet, hint hidden", () => {
    const h = loadPopup();
    for (const ok of [null, undefined]) {
      h.ctx.renderBridge(ok, null, null);
      assert.equal(h.el("bridge-status").textContent, "Not tried yet");
      assert.equal(h.el("bridge-status").className, "status");
      assert.equal(h.el("bridge-hint").hidden, true);
    }
  });

  test("true → Connected ✓ with time, hint hidden", () => {
    const h = loadPopup();
    h.ctx.renderBridge(true, AT, null);
    assert.match(h.el("bridge-status").textContent, /^Connected ✓/);
    assert.equal(h.el("bridge-status").textContent.includes(new Date(AT).toLocaleTimeString()), true);
    assert.equal(h.el("bridge-status").className, "status ok");
    assert.equal(h.el("bridge-hint").hidden, true);
  });

  test("false + unpaired → Not paired ✕, hint shown", () => {
    const h = loadPopup();
    h.ctx.renderBridge(false, AT, "unpaired");
    assert.equal(h.el("bridge-status").textContent, "Not paired ✕ — paste the app's token");
    assert.equal(h.el("bridge-status").className, "status bad");
    assert.equal(h.el("bridge-hint").hidden, false);
  });

  test("false + unauthorized → Token rejected ✕, hint shown", () => {
    const h = loadPopup();
    h.ctx.renderBridge(false, AT, "unauthorized");
    assert.equal(h.el("bridge-status").textContent, "Token rejected ✕ — re-pair");
    assert.equal(h.el("bridge-status").className, "status bad");
    assert.equal(h.el("bridge-hint").hidden, false);
  });

  test("false + unreachable (or unknown why) → App not reachable ✕, hint hidden", () => {
    const h = loadPopup();
    for (const why of ["unreachable", null, undefined, "something-new"]) {
      h.ctx.renderBridge(false, AT, why);
      assert.match(h.el("bridge-status").textContent, /^App not reachable ✕/);
      assert.equal(h.el("bridge-status").className, "status bad");
      assert.equal(h.el("bridge-hint").hidden, true, `hint hidden for why=${why}`);
    }
  });

  test("the hint hides again once the state recovers", () => {
    const h = loadPopup();
    h.ctx.renderBridge(false, AT, "unauthorized");
    assert.equal(h.el("bridge-hint").hidden, false);
    h.ctx.renderBridge(true, AT, null);
    assert.equal(h.el("bridge-hint").hidden, true);
  });

  test("loadDebug reads bridgeWhy and renders the unpaired state from storage", async () => {
    const h = loadPopup({ config: { bridgeOk: false, bridgeAt: AT, bridgeWhy: "unpaired", saLogs: [] } });
    await h.ctx.loadDebug();
    assert.match(h.el("bridge-status").textContent, /^Not paired ✕/);
    assert.equal(h.el("bridge-hint").hidden, false);
    assert.equal(h.el("last-intent").textContent, "none yet");
  });

  test("loadDebug with nothing stored renders Not tried yet", async () => {
    const h = loadPopup({ config: {} });
    await h.ctx.loadDebug();
    assert.equal(h.el("bridge-status").textContent, "Not tried yet");
  });

  test("storage.onChanged on bridgeWhy re-renders, and the pair link opens Options", async () => {
    const h = loadPopup({ config: { bridgeOk: true, bridgeAt: AT, bridgeWhy: null } });
    await h.domReady();
    assert.match(h.el("bridge-status").textContent, /^Connected ✓/);

    h.setConfig({ bridgeOk: false, bridgeWhy: "unauthorized" });
    h.storageChanged({ bridgeWhy: { oldValue: null, newValue: "unauthorized" } });
    await h.tick();
    await h.tick();
    assert.equal(h.el("bridge-status").textContent, "Token rejected ✕ — re-pair");
    assert.equal(h.el("bridge-hint").hidden, false);

    const click = h.el("open-options-pair").listeners.click;
    assert.ok(click && click.length === 1);
    let prevented = false;
    click[0]({ preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
    assert.equal(h.openedOptions, 1);
  });

  test("storage.onChanged in another area is ignored", async () => {
    const h = loadPopup({ config: { bridgeOk: true, bridgeAt: AT, bridgeWhy: null } });
    await h.domReady();
    h.setConfig({ bridgeOk: false, bridgeWhy: "unpaired" });
    h.storageChanged({ bridgeWhy: { newValue: "unpaired" } }, "sync");
    await h.tick();
    await h.tick();
    assert.match(h.el("bridge-status").textContent, /^Connected ✓/);
  });
});
