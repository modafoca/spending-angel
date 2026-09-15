// Spending Angel — options + popup pairing-surface tests (NATIVE-01 client).
// Run with: node --test extension/tests/*.test.js
//
// The options page owns the only secret in the system (saBridgeToken) and the
// popup renders the paired / unpaired / rejected states the service worker
// writes. Both scripts are evaluated against a tiny element-by-id DOM stub in
// tests/harness.js — enough to drive renderToken()/saveToken() and
// renderBridge()/loadDebug() without a browser.
//
// Pairing wording (review 2026-09, item 4): "Paired" is a claim the app has to
// earn — only bridgeOk === true unlocks it. A fresh save reads "Token saved —
// waiting…", a 401 reads "Token rejected — …", an unreachable app reads
// "Token saved — the app isn't answering yet…". The status line re-renders
// live from storage and never touches the input's value; only a successful
// save clears the field. The TOKEN_STATE_* consts are script-scoped in
// options.js (not on h.ctx), so the expected strings are hardcoded here.

const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const { loadOptions, loadPopup } = require("./harness.js");

const TOKEN = "0123456789abcdef".repeat(4);
const TAIL = TOKEN.slice(-4);
const BRIDGE_KEYS = ["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"];

const STATE_NONE = "Not paired — the app will not answer until you paste the token.";
const STATE_SAVED = `Token saved — waiting for the app to confirm (…${TAIL}). Try "Simulate intent" in the popup.`;
const STATE_UNREACHABLE = `Token saved — the app isn't answering yet (…${TAIL}). Is Spending Angel running?`;
const STATE_PAIRED = `Paired — token ends in …${TAIL}`;
const STATE_REJECTED = `Token rejected — copy it again from PAIR SENSOR (…${TAIL})`;
const JUNK_MSG = "hmm, that doesn't look like a token (64 hex characters)";

const tokenState = (h) => h.el("token-state").textContent;

// ---- Options: token form ---------------------------------------------------

describe("options.js pairing card", () => {
  test("renderToken shows the not-paired state when no token is stored", async () => {
    const h = loadOptions({ config: {} });
    await h.ctx.renderToken();
    assert.equal(tokenState(h), STATE_NONE);
    assert.equal(h.el("token-input").placeholder, "paste the 64-character token");
    assert.equal(h.el("token-input").value, "");
  });

  test("renderToken masks a stored token and shows only its tail", async () => {
    // Only the token is stored: the app has not answered yet, so the line is
    // "Token saved — waiting…", never "Paired".
    const h = loadOptions({ config: { saBridgeToken: TOKEN } });
    await h.ctx.renderToken();
    assert.equal(tokenState(h), STATE_SAVED);
    assert.match(tokenState(h), new RegExp(`^Token saved — waiting for the app to confirm \\(…${TAIL}\\)`));
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
    // saveToken's own reset — renderToken no longer clears the field.
    assert.equal(h.el("token-input").value, "", "field cleared after save");
    // The one-write reset nulls bridgeOk, so a fresh save always reads "waiting".
    assert.equal(tokenState(h), STATE_SAVED);
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
    assert.equal(tokenState(h), JUNK_MSG);
  });

  test("saveToken with junk leaves the user's text in the field to fix", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN } });
    h.el("token-input").value = TOKEN.slice(0, 40);
    await h.ctx.saveToken(h.el("token-input").value);
    assert.equal(h.el("token-input").value, TOKEN.slice(0, 40), "junk path does not clear the field");
    assert.equal(tokenState(h), JUNK_MSG);
  });

  test("saveToken with an empty string unpairs by removing all four bridge keys", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: true, bridgeAt: 5, bridgeWhy: null } });
    h.el("token-input").value = "   ";
    await h.ctx.saveToken("");
    assert.equal(h.writes.length, 0);
    assert.equal(h.removes.length, 1);
    assert.deepEqual([...h.removes[0]].sort(), [...BRIDGE_KEYS].sort());
    for (const k of BRIDGE_KEYS) assert.ok(!(k in h.store), `${k} removed`);
    assert.equal(tokenState(h), STATE_NONE);
    assert.equal(h.el("token-input").value, "", "the unpair path clears the field too");
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

  // ---- Round 2: pairing wording ----------------------------------------------

  test("renderToken says Paired only when bridgeOk is true", async () => {
    const paired = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: true } });
    await paired.ctx.renderToken();
    assert.equal(tokenState(paired), STATE_PAIRED);

    const unpaired = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unpaired" } });
    await unpaired.ctx.renderToken();
    assert.equal(tokenState(unpaired), STATE_SAVED);

    const untried = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: null } });
    await untried.ctx.renderToken();
    assert.equal(tokenState(untried), STATE_SAVED);
    assert.doesNotMatch(tokenState(untried), /^Paired/);
  });

  test("renderToken shows the rejected state for an unauthorized bridge", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unauthorized" } });
    await h.ctx.renderToken();
    assert.equal(tokenState(h), STATE_REJECTED);
    assert.equal(h.el("token-input").placeholder, `••••…${TAIL}`);
  });

  test("renderToken says the app isn't answering for an unreachable bridge (edge 26)", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unreachable" } });
    await h.ctx.renderToken();
    assert.equal(tokenState(h), STATE_UNREACHABLE);
    // The reviewer fixture's regex: both "saved" states share the prefix.
    assert.match(tokenState(h), /^Token saved/);
  });

  test("tokenStateText precedence", () => {
    const h = loadOptions({ config: {} });
    const f = (ok, why) => h.ctx.tokenStateText(ok, why, TAIL);
    // Paired wins over any why.
    assert.equal(f(true, "unauthorized"), STATE_PAIRED);
    assert.equal(f(true, "unreachable"), STATE_PAIRED);
    assert.equal(f(true, null), STATE_PAIRED);
    // Rejected.
    assert.equal(f(false, "unauthorized"), STATE_REJECTED);
    assert.equal(f(null, "unauthorized"), STATE_REJECTED);
    // Unreachable.
    assert.equal(f(false, "unreachable"), STATE_UNREACHABLE);
    assert.equal(f(null, "unreachable"), STATE_UNREACHABLE);
    // Everything else is "saved, waiting".
    assert.equal(f(false, "unpaired"), STATE_SAVED);
    assert.equal(f(null, null), STATE_SAVED);
    assert.equal(f(undefined, undefined), STATE_SAVED);
    assert.equal(f(false, "something-new"), STATE_SAVED);
    assert.equal(f("true", null), STATE_SAVED, "strict === true, not truthy");
  });

  test("renderToken never touches the token field's value (edge 25)", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: null } });
    await h.domReady();
    assert.equal(tokenState(h), STATE_SAVED);

    // Mid-paste when the service worker flips the bridge status.
    h.el("token-input").value = "partial";
    h.setConfig({ bridgeOk: true });
    h.storageChanged({ bridgeOk: { oldValue: null, newValue: true } });
    await h.tick();
    await h.tick();
    assert.equal(tokenState(h), STATE_PAIRED, "the line flipped live");
    assert.equal(h.el("token-input").value, "partial", "the paste in progress survived");

    await h.ctx.renderToken();
    assert.equal(h.el("token-input").value, "partial", "a direct re-render leaves it too");

    await h.ctx.saveToken(TOKEN);
    assert.equal(h.el("token-input").value, "", "only a successful save clears the field");
  });

  test("storage.onChanged on bridgeOk re-renders the pairing line live (edge 16)", async () => {
    const h = loadOptions({ config: { saBridgeToken: TOKEN, bridgeOk: null, bridgeWhy: null } });
    await h.domReady();
    assert.equal(h.listeners.storageChanged.length, 1, "one storage listener registered on DOMContentLoaded");
    assert.equal(tokenState(h), STATE_SAVED);

    // "Simulate intent" → 200 → Paired, without a reload.
    h.setConfig({ bridgeOk: true });
    h.storageChanged({ bridgeOk: { oldValue: null, newValue: true } });
    await h.tick();
    await h.tick();
    assert.equal(tokenState(h), STATE_PAIRED);

    // Regenerated in the app → 401 → Rejected, live (edge 20).
    h.setConfig({ bridgeOk: false, bridgeWhy: "unauthorized" });
    h.storageChanged({ bridgeWhy: { oldValue: null, newValue: "unauthorized" } });
    await h.tick();
    await h.tick();
    assert.equal(tokenState(h), STATE_REJECTED);

    // New token pasted → one-write reset → waiting again.
    h.setConfig({ saBridgeToken: TOKEN, bridgeOk: null, bridgeWhy: null });
    h.storageChanged({ saBridgeToken: { newValue: TOKEN } });
    await h.tick();
    await h.tick();
    assert.equal(tokenState(h), STATE_SAVED);

    // Another storage area is ignored.
    h.setConfig({ bridgeOk: true });
    h.storageChanged({ bridgeOk: { newValue: true } }, "sync");
    await h.tick();
    await h.tick();
    assert.equal(tokenState(h), STATE_SAVED, "sync-area changes do not re-render");

    // An unrelated key does not call renderToken: a sentinel survives.
    h.el("token-state").textContent = "sentinel";
    h.storageChanged({ saMode: { newValue: "everywhere" } });
    await h.tick();
    await h.tick();
    assert.equal(tokenState(h), "sentinel", "saMode changes do not touch the pairing line");
  });

  test("every pairing string keeps the pixel-game voice", async () => {
    const states = [
      {},
      { saBridgeToken: TOKEN },
      { saBridgeToken: TOKEN, bridgeOk: true },
      { saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unauthorized" },
      { saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unreachable" },
    ];
    const seen = new Set();
    for (const config of states) {
      const h = loadOptions({ config });
      await h.ctx.renderToken();
      const text = tokenState(h);
      seen.add(text);
      assert.doesNotMatch(text, /error|failed|exception/i, `system-ese in: ${text}`);
      assert.ok(
        /[.?)]$/.test(text) || text.endsWith(TAIL),
        `ends with a period, a question mark, a parenthesis or the tail: ${text}`,
      );
      assert.ok(!text.includes(TOKEN.slice(0, 8)), "never more than the tail of the token");
    }
    assert.equal(seen.size, 5, "five stored states, five distinct lines");
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
