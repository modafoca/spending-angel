// Spending Angel — shared logger tests (review 2026-09, R-02 / S-02 / S-07).
// Run with: node --test extension/tests/*.test.js
//
// saLog prints once and writes a 50-entry ring to chrome.storage.local.saLogs
// through ONE awaited chain with a terminal .catch. A torn-down storage must
// neither surface as an unhandled rejection nor be re-logged (that would
// recurse into the same dead storage), and a corrupted ring is replaced rather
// than left wedged. The real log.js is evaluated in the background vm context
// by tests/harness.js; h.ctx.saLog is the shipped function.

const { test, describe, after } = require("node:test");
const assert = require("node:assert/strict");
const { loadBackground } = require("./harness.js");

// Any rejection that escapes saLog's chain lands here and fails the file.
const unhandled = [];
process.on("unhandledRejection", (e) => { unhandled.push(e); });

const CONFIG = { saMode: "listed", saAllowlist: [], saBlocklist: [], saInitialized: true };

async function flush(h, n = 3) {
  for (let i = 0; i < n; i++) await h.tick();
}

describe("saLog ring write", () => {
  test("writes a ring entry via the promise form", async () => {
    const h = loadBackground({ config: CONFIG });
    const ret = h.ctx.saLog("info", "t.one", "hello", { intent_id: "abc" });
    assert.equal(ret, undefined, "saLog returns nothing, synchronously");
    await flush(h);

    assert.equal(h.store.saLogs.length, 1);
    const entry = h.store.saLogs[0];
    assert.deepEqual(Object.keys(entry).sort(), ["event", "intent_id", "level", "msg", "ts"]);
    assert.equal(entry.level, "info");
    assert.equal(entry.event, "t.one");
    assert.equal(entry.msg, "hello");
    assert.equal(entry.intent_id, "abc");
    assert.match(entry.ts, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(h.writes.length, 1, "one set() for one call");
    assert.deepEqual(Object.keys(h.writes[0]), ["saLogs"]);

    assert.equal(h.console.length, 1, "console printed exactly once");
    assert.equal(h.console[0].level, "log", "info goes to console.log");
    assert.match(h.console[0].args[0], /^\[SA info\] t\.one — hello$/);
  });

  test("error level prints through console.error", async () => {
    const h = loadBackground({ config: CONFIG });
    h.ctx.saLog("error", "t.bad", "oops");
    await flush(h);
    assert.equal(h.console.length, 1);
    assert.equal(h.console[0].level, "error");
    assert.equal(h.store.saLogs[0].level, "error");
  });

  test("ring is capped at SA_LOG_MAX newest-last", async () => {
    const h = loadBackground({ config: CONFIG });
    assert.equal(h.ctx.SA_LOG_MAX, 50);
    // The flush per iteration is load-bearing (edge case 28): back-to-back
    // calls in one turn all read the pre-write ring and the last writer wins.
    for (let i = 1; i <= 60; i++) {
      h.ctx.saLog("info", "t.fill", "call " + i);
      await flush(h);
    }
    assert.equal(h.store.saLogs.length, 50);
    assert.equal(h.store.saLogs[0].msg, "call 11", "oldest ten fell off the front");
    assert.equal(h.store.saLogs.at(-1).msg, "call 60", "newest last");
    assert.equal(h.console.length, 60, "every call printed regardless of the cap");
  });

  test("back-to-back calls in one tick are not serialized (documented race, edge 28)", async () => {
    // Accepted, not desired: both reads see the empty ring, the second write
    // wins. Same in real Chrome. Pinned so the flush in the cap test above is
    // never "simplified" away — nothing shipped logs twice in one turn.
    const h = loadBackground({ config: CONFIG });
    h.ctx.saLog("info", "t.a", "first");
    h.ctx.saLog("info", "t.b", "second");
    await flush(h);
    assert.equal(h.store.saLogs.length, 1, "one line lost to the read-modify-write race");
    assert.equal(h.console.length, 2, "console has both");
    assert.equal(unhandled.length, 0);
  });

  test("failing get on saLogs is swallowed (edge 1)", async () => {
    const h = loadBackground({ config: { ...CONFIG, saLogs: [{ event: "t.prior" }] } });
    h.failNextGet(new Error("Extension context invalidated."), "saLogs");
    h.ctx.saLog("info", "t.lost", "storage gone mid-call");
    await flush(h);

    assert.equal(unhandled.length, 0, "the terminal .catch swallows the rejection");
    assert.deepEqual(h.store.saLogs, [{ event: "t.prior" }], "ring unchanged");
    assert.equal(h.writes.length, 0, "no set() after a failed get()");
    assert.equal(h.console.length, 1, "printed once — the failure is not re-logged");

    // Storage back: the next call behaves normally.
    h.ctx.saLog("info", "t.back", "storage answers again");
    await flush(h);
    assert.equal(h.store.saLogs.length, 2);
    assert.equal(h.store.saLogs.at(-1).event, "t.back");
  });

  test("failing set on saLogs is swallowed (edge 2)", async () => {
    const h = loadBackground({ config: { ...CONFIG, saLogs: [] } });
    h.failNextSet(new Error("Extension context invalidated."), "saLogs");
    h.ctx.saLog("info", "t.lost", "storage gone mid-write");
    await flush(h);

    assert.equal(unhandled.length, 0);
    assert.deepEqual(h.store.saLogs, [], "ring unchanged");
    assert.equal(h.writes.length, 0, "the failed write was not recorded");
    assert.equal(h.console.length, 1, "printed once, no second line");
  });

  test("does not re-log or recurse on failure", async () => {
    const h = loadBackground({ config: CONFIG });
    h.failNextGet(new Error("dead"), "saLogs");
    h.failNextSet(new Error("dead"), "saLogs");
    h.ctx.saLog("error", "t.dead", "both halves down");
    await flush(h, 6);

    assert.equal(unhandled.length, 0);
    assert.equal(h.console.length, 1, "exactly one console line — no recursion");
    assert.equal(h.writes.length, 0);
    assert.equal(h.logs().length, 0);
  });

  test("corrupted ring is replaced (edge 17)", async () => {
    const h = loadBackground({ config: { ...CONFIG, saLogs: "junk" } });
    h.ctx.saLog("info", "t.fresh", "ring was a string");
    await flush(h);

    assert.equal(unhandled.length, 0);
    assert.ok(Array.isArray(h.store.saLogs), "non-array ring replaced");
    assert.equal(h.store.saLogs.length, 1);
    assert.equal(h.store.saLogs[0].event, "t.fresh");
  });

  test("missing chrome global does not throw", async () => {
    // Plain Node, no `chrome` at all: the ReferenceError happens inside the
    // async IIFE and is swallowed; the console line is still printed once.
    const { saLog, SA_LOG_MAX } = require("../log.js");
    assert.equal(SA_LOG_MAX, 50);
    assert.equal(typeof globalThis.chrome, "undefined");
    const printed = [];
    const origLog = console.log;
    console.log = (...args) => { printed.push(args); };
    let ret;
    try {
      ret = saLog("info", "t.node", "no chrome here");
    } finally {
      console.log = origLog;
    }
    await new Promise((r) => setImmediate(r));
    await new Promise((r) => setImmediate(r));
    assert.equal(ret, undefined);
    assert.equal(printed.length, 1);
    assert.equal(unhandled.length, 0, "the missing global is contained by the chain's .catch");
  });
});

after(() => {
  assert.equal(unhandled.length, 0, `unhandled rejections leaked: ${unhandled.map(String).join("; ")}`);
});
