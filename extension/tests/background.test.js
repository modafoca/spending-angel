// Spending Angel — service-worker tests (audit fixes EXT-03, NATIVE-01 client).
// Run with: node --test extension/tests/*.test.js
//
// EXT-03:    content-script reconciles are serialized, so a stale "everywhere"
//            run can never finish after a newer "listed" run and re-register
//            *://*/*. A failing reconcile logs and never wedges the queue.
// NATIVE-01: forward() authenticates to the bridge with the pairing token
//            (Authorization: Bearer <token>); with no/malformed token it does
//            not fetch, leaves no timer behind, and marks the popup unpaired.
// S-03:      the wire body is rebuilt from the five named keys — anything else
//            riding on the runtime message never reaches the bridge.
// R-02b:     a failing token read is contained inside forward() (no log, no
//            write, no fetch, no timer) and the onMessage listener contains a
//            forward() that still rejects; neither ever leaks a rejection.
// Round 3:   200 and 429 carry a JSON body saying what the app did; forward()
//            stores it as `lastResult` (+ `appVersion`) in the SAME set() as
//            bridgeOk, keeps only the listed keys, reads a missing/invalid body
//            as "unknown", and never touches either key on 401/unreachable.
//
// The real background.js is evaluated in a vm context by tests/harness.js.
// The abort timer is Node's real setTimeout there, so every test that reaches
// fetch() uses a fetchImpl that settles immediately — never one that waits.

const { test, describe, after } = require("node:test");
const assert = require("node:assert/strict");
const { loadBackground } = require("./harness.js");
const { saHostToOrigins } = require("../sites.js");

const unhandled = [];
process.on("unhandledRejection", (e) => { unhandled.push(e); });

const HOST = "shop.example.test";
const TOKEN = "0123456789abcdef".repeat(4); // 64 lowercase hex
const LISTED = { saMode: "listed", saAllowlist: [HOST], saBlocklist: [], saInitialized: true };
const EVERYWHERE = { saMode: "everywhere", saAllowlist: [], saBlocklist: [], saInitialized: true };

function intent(overrides = {}) {
  return {
    id: "11111111-2222-4333-8444-555555555555",
    type: "checkout_intent",
    trigger: "click",
    hostname: HOST,
    ts: 1_700_000_000_000,
    ...overrides,
  };
}

async function flush(h, n = 3) {
  for (let i = 0; i < n; i++) await h.tick();
}

// The three connection keys of a bridge write, without the Round 3 result.
function bridgePart(w) {
  return { bridgeOk: w.bridgeOk, bridgeAt: w.bridgeAt, bridgeWhy: w.bridgeWhy };
}

// A permissions impl whose every call parks on a gate the test releases by hand.
function gatedPermissions() {
  const gates = [];
  const impl = () => new Promise((resolve) => { gates.push(resolve); });
  impl.gates = gates;
  return impl;
}

// ---- EXT-03: serialized reconcile ------------------------------------------

describe("EXT-03 serialized syncContentScripts", () => {
  test("an older everywhere reconcile cannot overwrite a newer listed one", async () => {
    let release;
    const gate = new Promise((r) => { release = r; });
    const permissions = (origins) => (origins[0] === "*://*/*" ? gate : Promise.resolve(true));
    const h = loadBackground({ config: EVERYWHERE, permissions });

    const p1 = h.ctx.syncContentScripts();
    await h.tick(); // run 1 has read saMode:"everywhere" and is parked on the gate
    h.setConfig({ saMode: "listed", saAllowlist: [HOST] });
    const p2 = h.ctx.syncContentScripts();
    await h.tick();
    assert.equal(h.active, null, "nothing registered while run 1 is gated");
    assert.equal(h.registrations.length, 0);

    release(true);
    await Promise.all([p1, p2]);

    assert.equal(h.registrations.length, 2);
    assert.deepEqual(Array.from(h.registrations[0].matches), ["*://*/*"], "run 1 registered everywhere");
    assert.deepEqual(Array.from(h.active.matches), saHostToOrigins(HOST), "run 2 won");
    assert.ok(!Array.from(h.active.matches).includes("*://*/*"));
    assert.equal(h.active.id, "sa-detector");
  });

  test("concurrent calls run in order and each reads the latest state at its own start", async () => {
    const permissions = gatedPermissions();
    const h = loadBackground({ config: { ...LISTED, saAllowlist: ["a.test"] }, permissions });

    const p1 = h.ctx.syncContentScripts();
    await h.tick();
    assert.equal(permissions.gates.length, 1, "run 1 is in flight");

    h.setConfig({ saAllowlist: ["b.test"] });
    const p2 = h.ctx.syncContentScripts();
    h.setConfig({ saAllowlist: ["c.test"] });
    const p3 = h.ctx.syncContentScripts();
    await h.tick();
    assert.equal(permissions.gates.length, 1, "runs 2 and 3 wait for run 1");

    permissions.gates[0](true);
    await flush(h);
    assert.equal(h.registrations.length, 1);
    assert.equal(permissions.gates.length, 2, "run 2 starts only after run 1 finished");

    permissions.gates[1](true);
    await flush(h);
    assert.equal(permissions.gates.length, 3);
    permissions.gates[2](true);
    await Promise.all([p1, p2, p3]);

    // Run 2 started after the "c.test" write, so it (correctly) reflects c.test.
    const seen = h.registrations.map((r) => Array.from(r.matches));
    assert.deepEqual(seen, [
      saHostToOrigins("a.test"),
      saHostToOrigins("c.test"),
      saHostToOrigins("c.test"),
    ]);
    assert.deepEqual(Array.from(h.active.matches), saHostToOrigins("c.test"));
  });

  test("a rejecting reconcile logs sites.sync_failed and does not wedge the tail", async () => {
    const h = loadBackground({ config: LISTED });

    // 1. registerContentScripts throws → caught inside reconcile.
    h.failNextRegister(new Error("boom"));
    await h.ctx.syncContentScripts();
    await h.tick();
    assert.ok(h.logEvents().includes("sites.register_failed"));
    assert.ok(!h.logEvents().includes("sites.sync_failed"));
    assert.equal(h.logs().find((l) => l.event === "sites.register_failed").msg, "boom");
    assert.equal(h.active, null);

    // 2. storage.get throws → escapes reconcile, caught by the tail. Scoped to
    //    the DEFAULTS read (saMode) so a pending ring read can't consume it.
    h.failNextGet(new Error("storage gone"), "saMode");
    await h.ctx.syncContentScripts(); // must resolve, never reject
    await h.tick();
    const failed = h.logs().find((l) => l.event === "sites.sync_failed");
    assert.ok(failed, "sites.sync_failed logged");
    assert.equal(failed.level, "error");
    assert.equal(failed.msg, "storage gone");

    // 3. The queue keeps accepting calls.
    await h.ctx.syncContentScripts();
    assert.ok(h.active, "registered after the failures");
    assert.equal(h.registrations.length, 1);
  });

  test("syncContentScripts returns a promise that resolves after its reconcile", async () => {
    const h = loadBackground({ config: LISTED });
    const p = h.ctx.syncContentScripts();
    assert.ok(p && typeof p.then === "function");
    assert.equal(h.active, null, "not registered synchronously");
    await p;
    assert.ok(h.active);
    assert.deepEqual(Array.from(h.active.matches), saHostToOrigins(HOST));
    assert.deepEqual(Array.from(h.active.js), ["domains.js", "log.js", "detect.js", "sites.js", "content.js"]);
    assert.equal(h.active.runAt, "document_idle");
    assert.equal(h.active.persistAcrossSessions, true);
  });

  test("first run tolerates 'Nonexistent script ID' from unregister", async () => {
    const h = loadBackground({ config: LISTED });
    await h.ctx.syncContentScripts();
    assert.equal(h.unregisters, 1);
    assert.ok(h.active);
    assert.ok(!h.logEvents().includes("sites.sync_failed"));
    assert.ok(!h.logEvents().includes("sites.register_failed"));
  });

  test("listed host without a granted permission registers nothing", async () => {
    const h = loadBackground({ config: LISTED, permissions: async () => false });
    await h.ctx.syncContentScripts();
    await h.tick();
    assert.equal(h.active, null);
    assert.equal(h.registrations.length, 0);
    const reg = h.logs().find((l) => l.event === "sites.registered");
    assert.ok(reg);
    assert.match(reg.msg, /^0 patterns/);
    assert.equal(reg.mode, "listed");
  });

  test("everywhere without the broad grant registers nothing", async () => {
    const h = loadBackground({ config: EVERYWHERE, permissions: async () => false });
    await h.ctx.syncContentScripts();
    assert.equal(h.active, null);
  });

  test("a second reconcile replaces the registration wholesale", async () => {
    const h = loadBackground({ config: LISTED });
    await h.ctx.syncContentScripts();
    h.setConfig({ saAllowlist: [HOST, "other.test"] });
    await h.ctx.syncContentScripts();
    assert.equal(h.registrations.length, 2);
    assert.deepEqual(Array.from(h.active.matches),
      [...saHostToOrigins(HOST), ...saHostToOrigins("other.test")]);
  });

  test("storage.onChanged listener triggers a sync only for policy keys", async () => {
    const h = loadBackground({ config: LISTED });
    assert.equal(h.listeners.storageChanged.length, 1);

    h.storageChanged({ bridgeOk: { newValue: true } });
    await flush(h);
    assert.equal(h.registrations.length, 0);

    h.storageChanged({ saBridgeToken: { newValue: TOKEN } });
    await flush(h);
    assert.equal(h.registrations.length, 0, "token changes do not touch registrations");

    h.storageChanged({ saMode: { newValue: "listed" } });
    await flush(h);
    assert.equal(h.registrations.length, 1);

    h.storageChanged({ saAllowlist: { newValue: [] } });
    await flush(h);
    assert.equal(h.registrations.length, 2);

    h.storageChanged({ saBlocklist: { newValue: [] } });
    await flush(h);
    assert.equal(h.registrations.length, 3);

    h.storageChanged({ saMode: { newValue: "listed" } }, "sync");
    await flush(h);
    assert.equal(h.registrations.length, 3, "other storage areas are ignored");
  });

  test("permission and lifecycle listeners are wired to the serialized sync", async () => {
    const h = loadBackground({ config: LISTED });
    for (const name of ["onInstalled", "onStartup", "permissionsAdded", "permissionsRemoved"]) {
      assert.equal(h.listeners[name].length, 1, `${name} listener registered`);
    }
    h.listeners.permissionsAdded[0]();
    h.listeners.permissionsRemoved[0]();
    h.listeners.onStartup[0]();
    await flush(h, 6);
    assert.equal(h.registrations.length, 3);
    assert.ok(h.active);
  });

  test("onInstalled seeds the recommended list once, then syncs", async () => {
    const h = loadBackground({ config: {} });
    h.listeners.onInstalled[0]();
    await flush(h, 6);

    assert.equal(h.store.saInitialized, true);
    assert.equal(h.store.saMode, "listed");
    assert.ok(h.store.saAllowlist.includes("amazon.com"));
    assert.deepEqual(Array.from(h.store.saBlocklist), []);
    assert.ok(h.logEvents().includes("sites.seeded"));
    assert.ok(h.active, "sync ran after seeding");

    // Second install event (e.g. update) must not re-seed over user edits.
    h.setConfig({ saAllowlist: ["only.mine.test"] });
    h.listeners.onInstalled[0]();
    await flush(h, 6);
    assert.deepEqual(Array.from(h.store.saAllowlist), ["only.mine.test"]);
    assert.equal(h.logEvents().filter((e) => e === "sites.seeded").length, 1);
  });

  test("onInstalled is contained when storage rejects at install time (R2-03)", async () => {
    const h = loadBackground({ config: {} });
    h.failNextGet(new Error("storage gone"), "saInitialized"); // seedIfNeeded's read
    const before = unhandled.length;
    h.listeners.onInstalled[0]();
    await flush(h, 6);
    assert.equal(unhandled.length, before, "no unhandled rejection escaped the listener");
    assert.equal(h.writes.length, 0, "nothing seeded");
    assert.equal(h.registrations.length, 0, "sync never ran after a failed seed");
    assert.equal(h.logs().length, 0, "a dead storage takes no log line");
    assert.equal(h.console.length, 0, "and nothing is printed either");

    // The next install event (storage back) seeds and syncs normally.
    h.listeners.onInstalled[0]();
    await flush(h, 6);
    assert.equal(h.store.saInitialized, true);
    assert.ok(h.active, "sync ran after the recovered seed");
  });
});

// ---- NATIVE-01: client side ------------------------------------------------

describe("NATIVE-01 forward() pairing token", () => {
  test("forward without a token does not fetch and marks unpaired", async () => {
    const h = loadBackground({ config: LISTED });
    const msg = intent();
    h.message(msg);
    await flush(h);

    assert.equal(h.fetches.length, 0);
    assert.equal(h.timers.length, 0, "no abort timer may be created on the unpaired path");
    const w = h.bridgeWrites().at(-1);
    assert.deepEqual(w, { bridgeOk: false, bridgeAt: h.clock.now, bridgeWhy: "unpaired" });
    const log = h.logs().find((l) => l.event === "bridge.unpaired");
    assert.ok(log);
    assert.equal(log.level, "info");
    assert.equal(log.intent_id, msg.id);
    assert.match(log.msg, /PAIR SENSOR/);
  });

  test("malformed stored token is treated as unpaired", async () => {
    for (const bad of ["abc", TOKEN.slice(0, 63), TOKEN + "0", "g".repeat(64), null, 42]) {
      const h = loadBackground({ config: { ...LISTED, saBridgeToken: bad } });
      h.message(intent());
      await flush(h);
      assert.equal(h.fetches.length, 0, `no fetch for token ${JSON.stringify(bad)}`);
      assert.equal(h.timers.length, 0);
      assert.equal(h.bridgeWrites().at(-1).bridgeWhy, "unpaired");
      assert.ok(h.logEvents().includes("bridge.unpaired"));
    }
  });

  test("forward with a token sends Authorization: Bearer", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    const msg = intent();
    h.message(msg);
    await flush(h);

    assert.equal(h.fetches.length, 1);
    const { url, init } = h.fetches[0];
    assert.equal(url, "http://127.0.0.1:17865/intent");
    assert.equal(init.method, "POST");
    assert.equal(init.headers.Authorization, "Bearer " + TOKEN);
    assert.equal(init.headers["Content-Type"], "application/json");
    assert.deepEqual(Object.keys(init.headers).sort(), ["Authorization", "Content-Type"]);
    assert.deepEqual(JSON.parse(init.body), msg);
    // S-03: the body is the five-key wire object, in the app's validate() order.
    assert.deepEqual(Object.keys(JSON.parse(init.body)), ["id", "type", "trigger", "hostname", "ts"]);
    assert.ok(init.signal, "abort signal attached");

    // Round 3: the same set() also carries lastResult (the default harness
    // body is {}, so the app "said nothing" → unknown).
    const w = h.bridgeWrites().at(-1);
    assert.deepEqual(bridgePart(w), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
    assert.equal(w.lastResult.result, "unknown");
    const log = h.logs().find((l) => l.event === "bridge.forwarded");
    assert.ok(log);
    assert.equal(log.level, "info");
    assert.equal(log.intent_id, msg.id);
    assert.equal(log.msg, HOST);
    assert.equal(typeof log.ms, "number");
    assert.equal(h.timers.length, 1, "one abort timer for one fetch");
    assert.equal(h.clears, 1, "and it was cleared in finally");
  });

  test("stored token with whitespace / upper-case is normalized before sending", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: "  " + TOKEN.toUpperCase() + "\n" } });
    h.message(intent());
    await flush(h);
    assert.equal(h.fetches.length, 1);
    assert.equal(h.fetches[0].init.headers.Authorization, "Bearer " + TOKEN);
  });

  test("401 marks unauthorized", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async () => ({ ok: false, status: 401 }),
    });
    const msg = intent();
    h.message(msg);
    await flush(h);

    assert.deepEqual(h.bridgeWrites().at(-1), { bridgeOk: false, bridgeAt: h.clock.now, bridgeWhy: "unauthorized" });
    const log = h.logs().find((l) => l.event === "bridge.unauthorized");
    assert.ok(log);
    assert.equal(log.level, "error");
    assert.equal(log.intent_id, msg.id);
    assert.equal(log.status, 401);
    assert.match(log.msg, /re-pair/);
    assert.ok(!h.logEvents().includes("bridge.rejected"));
    assert.equal(h.clears, 1);
  });

  test("429 is rejected-but-reachable", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async () => ({ ok: false, status: 429 }),
    });
    h.message(intent());
    await flush(h);

    const w = h.bridgeWrites().at(-1);
    assert.deepEqual(bridgePart(w), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
    assert.equal(w.lastResult.result, "unknown", "a 429 without a body is still an answer");
    const log = h.logs().find((l) => l.event === "bridge.rejected");
    assert.ok(log);
    assert.equal(log.level, "info");
    assert.equal(log.status, 429);
    assert.ok(!h.logEvents().includes("bridge.unauthorized"));
  });

  test("400 is rejected-but-reachable too", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async () => ({ ok: false, status: 400 }),
    });
    h.message(intent());
    await flush(h);
    assert.equal(h.bridgeWrites().at(-1).bridgeOk, true);
    assert.equal(h.logs().find((l) => l.event === "bridge.rejected").status, 400);
    assert.ok(!("lastResult" in h.bridgeWrites().at(-1)), "a 400 says nothing about an intent");
  });

  test("network failure is unreachable", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async () => { throw new TypeError("Failed to fetch"); },
    });
    const msg = intent();
    h.message(msg);
    await flush(h);

    assert.deepEqual(h.bridgeWrites().at(-1), { bridgeOk: false, bridgeAt: h.clock.now, bridgeWhy: "unreachable" });
    const log = h.logs().find((l) => l.event === "bridge.unreachable");
    assert.ok(log);
    assert.equal(log.level, "error");
    assert.equal(log.intent_id, msg.id);
    assert.match(log.msg, /unreachable/);
    assert.doesNotMatch(log.msg, /timed out/);
    assert.equal(h.clears, 1, "timer cleared even on the error path");
  });

  test("abort (4 s timeout) is unreachable with a 'timed out' message", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async () => { const e = new Error("aborted"); e.name = "AbortError"; throw e; },
    });
    h.message(intent());
    await flush(h);
    assert.equal(h.bridgeWrites().at(-1).bridgeWhy, "unreachable");
    assert.match(h.logs().find((l) => l.event === "bridge.unreachable").msg, /timed out/);
  });

  test("abort timer is armed for the 4 s bridge timeout and wired to the signal", async () => {
    let seenSignal;
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async (url, init) => { seenSignal = init.signal; return { ok: true, status: 200 }; },
    });
    h.message(intent());
    await flush(h);
    assert.equal(h.timers[0].ms, 4000);
    assert.equal(seenSignal.aborted, false, "cleared before it could fire");
  });

  test("non-intent messages are ignored", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    h.message({ type: "other" });
    h.message(null);
    h.message("hello");
    h.message({ id: "x" });
    await flush(h);
    assert.equal(h.fetches.length, 0);
    assert.equal(h.writes.length, 0);
    assert.equal(h.logs().length, 0);
  });

  test("token saved after an unpaired attempt is picked up on the next intent (no restart)", async () => {
    const h = loadBackground({ config: LISTED });
    h.message(intent({ id: "first" }));
    await flush(h);
    assert.equal(h.fetches.length, 0);
    assert.equal(h.bridgeWrites().at(-1).bridgeWhy, "unpaired");

    h.setConfig({ saBridgeToken: TOKEN });
    h.clock.advance(5000);
    h.message(intent({ id: "second" }));
    await flush(h);
    assert.equal(h.fetches.length, 1);
    assert.deepEqual(bridgePart(h.bridgeWrites().at(-1)), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
  });

  test("a rejected bridge-status write is swallowed on the unpaired path", async () => {
    // forward() writes bridgeOk fire-and-forget; the set() must own its .catch
    // (quality review R-01) so a torn-down storage never becomes an unhandled
    // rejection in the worker.
    const h = loadBackground({ config: LISTED });
    h.failNextSet(new Error("storage gone"), "bridgeOk");
    h.message(intent());
    await flush(h);
    assert.equal(h.fetches.length, 0);
    assert.equal(h.bridgeWrites().length, 0, "the failed write was not recorded");
    assert.ok(h.logEvents().includes("bridge.unpaired"));
    assert.equal(unhandled.length, 0);
  });

  test("a rejected bridge-status write is swallowed after a delivered intent", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    h.failNextSet(new Error("storage gone"), "bridgeOk");
    h.message(intent());
    await flush(h);
    assert.equal(h.fetches.length, 1, "the intent was still delivered");
    assert.equal(h.bridgeWrites().length, 0);
    assert.ok(h.logEvents().includes("bridge.forwarded"));
    assert.equal(unhandled.length, 0);
  });

  test("a storage failure while reading the token fetches nothing and arms no timer", async () => {
    // The token read is the first statement of forward(): if it fails, nothing
    // downstream (fetch, AbortController, 4 s timer) may have been created —
    // and nothing may be logged or written either, since that would recurse
    // into the same dead storage (R-02b). Driven through the REAL listener; no
    // test-side .catch masks a production promise.
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    h.failNextGet(new Error("storage gone"), "saBridgeToken");
    h.message(intent());
    await flush(h);

    assert.equal(unhandled.length, 0, "no unhandled rejection from the listener path");
    assert.equal(h.fetches.length, 0);
    assert.equal(h.timers.length, 0, "no abort timer may be created");
    assert.equal(h.writes.length, 0, "containment sets nothing");
    assert.equal(h.bridgeWrites().length, 0);
    assert.equal(h.logs().length, 0, "containment logs nothing");
    assert.equal(h.console.length, 0, "containment prints nothing");

    // Called directly, forward() RESOLVES on the same failure — no .catch here,
    // by contract (design-spec-r2 edge case 21).
    h.failNextGet(new Error("storage gone"), "saBridgeToken");
    const result = await h.ctx.forward(intent());
    assert.equal(result, undefined);
    assert.equal(unhandled.length, 0);
    assert.equal(h.fetches.length, 0);
    assert.equal(h.timers.length, 0);
    assert.equal(h.writes.length, 0);
    assert.equal(h.logs().length, 0);

    // Storage back: the next intent goes through normally.
    h.message(intent({ id: "after" }));
    await flush(h);
    assert.equal(h.fetches.length, 1, "recovered once storage answers again");
  });

  test("onMessage listener contains a forward() that rejects (R-02b)", async () => {
    // Proves the LISTENER's .catch, not forward()'s own try/catch: forward is
    // a function declaration on the vm global, so the listener resolves it by
    // name at call time and this stand-in rejects unconditionally. Dropping
    // `.catch(() => {})` from the listener turns this red.
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    h.ctx.forward = async () => { throw new Error("boom"); };
    h.listeners.onMessage[0](intent(), { id: "sender" }, () => {});
    await flush(h);
    assert.equal(unhandled.length, 0, "the listener must contain a rejecting forward()");
    assert.equal(h.fetches.length, 0);
    assert.equal(h.writes.length, 0);
  });
});

// ---- Round 3: the app's answer body → lastResult ----------------------------

describe("Round 3 forward() stores what the app said it did", () => {
  const LAST_KEYS = ["at", "character", "hostname", "intent_id", "reason", "result", "retry_in_s", "snooze_until", "trigger"];

  function answer(status, body) {
    return async () => ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => {
        if (body instanceof Error) throw body;
        return body;
      },
    });
  }

  test("200 with a shown body writes lastResult + appVersion in the same set as bridgeOk", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: answer(200, { app_version: "0.6.0", character: "mom", result: "shown" }),
    });
    const msg = intent();
    h.message(msg);
    await flush(h);

    const writes = h.writes.filter((w) => "lastResult" in w);
    assert.equal(writes.length, 1, "exactly one write carries lastResult");
    const w = writes[0];
    assert.deepEqual(bridgePart(w), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
    assert.equal(w.appVersion, "0.6.0", "appVersion rides in the same set");
    assert.deepEqual(w.lastResult, {
      result: "shown",
      character: "mom",
      at: h.clock.now,
      intent_id: msg.id,
      hostname: HOST,
      trigger: "click",
    });
    assert.equal(h.store.lastResult.result, "shown");
    assert.equal(h.store.appVersion, "0.6.0");
    const log = h.logs().find((l) => l.event === "bridge.forwarded");
    assert.ok(log, "the Round 1 log event is unchanged");
    assert.equal(log.result, "shown");
  });

  test("200 with a skipped/snoozed body keeps reason and snooze_until", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: answer(200, {
        app_version: "0.6.0", reason: "snoozed", result: "skipped", snooze_until: "2026-09-15T22:43:54Z",
      }),
    });
    h.message(intent());
    await flush(h);
    const r = h.store.lastResult;
    assert.equal(r.result, "skipped");
    assert.equal(r.reason, "snoozed");
    assert.equal(r.snooze_until, "2026-09-15T22:43:54Z");
    assert.ok(!("character" in r));
    assert.ok(!("retry_in_s" in r));
  });

  test("200 with an empty body → result unknown, appVersion untouched", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN, appVersion: "0.5.0" },
      fetchImpl: answer(200, new SyntaxError("Unexpected end of JSON input")),
    });
    const msg = intent();
    h.message(msg);
    await flush(h);
    const w = h.writes.find((x) => "lastResult" in x);
    assert.ok(w);
    assert.equal(w.bridgeOk, true);
    assert.deepEqual(w.lastResult, {
      result: "unknown", at: h.clock.now, intent_id: msg.id, hostname: HOST, trigger: "click",
    });
    assert.ok(!("appVersion" in w), "no version in the body → the stored one is left alone");
    assert.equal(h.store.appVersion, "0.5.0");
  });

  test("200 with an invalid body (not an object, or a Response without json) → unknown", async () => {
    for (const body of ["hello", 42, null, [1, 2]]) {
      const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN }, fetchImpl: answer(200, body) });
      h.message(intent());
      await flush(h);
      assert.equal(h.store.lastResult.result, "unknown", `body ${JSON.stringify(body)}`);
      assert.ok(!("appVersion" in h.store));
    }
    // An older shim / a Response with no json() at all.
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: async () => ({ ok: true, status: 200 }),
    });
    h.message(intent());
    await flush(h);
    assert.equal(h.store.lastResult.result, "unknown");
    assert.ok(h.logEvents().includes("bridge.forwarded"));
    assert.equal(unhandled.length, 0);
  });

  test("429 with a throttled body → reason throttled + retry_in_s, bridge.rejected still logged", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: answer(429, { app_version: "0.6.0", reason: "throttled", result: "skipped", retry_in_s: 5 }),
    });
    const msg = intent();
    h.message(msg);
    await flush(h);

    const w = h.bridgeWrites().at(-1);
    assert.deepEqual(bridgePart(w), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
    assert.equal(w.appVersion, "0.6.0");
    assert.deepEqual(w.lastResult, {
      result: "skipped", reason: "throttled", retry_in_s: 5,
      at: h.clock.now, intent_id: msg.id, hostname: HOST, trigger: "click",
    });
    const log = h.logs().find((l) => l.event === "bridge.rejected");
    assert.ok(log);
    assert.equal(log.status, 429);
    assert.ok(!h.logEvents().includes("bridge.forwarded"));
  });

  test("401 and unreachable leave lastResult and appVersion untouched", async () => {
    const prior = { result: "shown", character: "papi", at: 1, intent_id: "old", hostname: HOST, trigger: "click" };
    const cases = [
      ["401", async () => ({ ok: false, status: 401, json: async () => ({ app_version: "9.9.9", result: "shown" }) })],
      ["network", async () => { throw new TypeError("Failed to fetch"); }],
      ["abort", async () => { const e = new Error("aborted"); e.name = "AbortError"; throw e; }],
    ];
    for (const [name, fetchImpl] of cases) {
      const h = loadBackground({
        config: { ...LISTED, saBridgeToken: TOKEN, lastResult: prior, appVersion: "0.6.0" },
        fetchImpl,
      });
      h.message(intent());
      await flush(h);
      const w = h.bridgeWrites().at(-1);
      assert.equal(w.bridgeOk, false, name);
      assert.ok(!("lastResult" in w), `${name}: lastResult not written`);
      assert.ok(!("appVersion" in w), `${name}: appVersion not written`);
      assert.deepEqual(h.store.lastResult, prior, `${name}: stored lastResult intact`);
      assert.equal(h.store.appVersion, "0.6.0");
    }
    // Unpaired: nothing is sent, nothing about the app changes either.
    const h = loadBackground({ config: { ...LISTED, lastResult: prior, appVersion: "0.6.0" } });
    h.message(intent());
    await flush(h);
    assert.ok(!("lastResult" in h.bridgeWrites().at(-1)));
    assert.deepEqual(h.store.lastResult, prior);
  });

  test("only the listed keys are stored; unknown body keys and wrong types are dropped", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: answer(200, {
        app_version: 6,                 // not a string → not stored
        result: "shown",
        character: "wizard",
        reason: 7,                      // wrong type → dropped
        retry_in_s: "5",                // wrong type → dropped
        snooze_until: 12345,            // wrong type → dropped
        debug: { secret: "x" },         // unknown → dropped
        hostname: "leak.test",          // the body can't rewrite request fields
        intent_id: "spoofed",
        at: 0,
        trigger: "spoofed",
      }),
    });
    const msg = intent();
    h.message(msg);
    await flush(h);
    const r = h.store.lastResult;
    assert.ok(Object.keys(r).every((k) => LAST_KEYS.includes(k)), `keys: ${Object.keys(r)}`);
    assert.deepEqual(Object.keys(r).sort(), ["at", "character", "hostname", "intent_id", "result", "trigger"]);
    assert.equal(r.hostname, HOST);
    assert.equal(r.intent_id, msg.id);
    assert.equal(r.trigger, "click");
    assert.equal(r.at, h.clock.now);
    assert.ok(!("appVersion" in h.store), "a non-string app_version is ignored");
    assert.ok(!JSON.stringify(h.writes).includes("leak.test"));
    assert.ok(!JSON.stringify(h.writes).includes("secret"));
  });

  test("an unknown result value reads as unknown, keeping the request fields", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: answer(200, { result: "danced", app_version: "0.7.0" }),
    });
    h.message(intent());
    await flush(h);
    assert.equal(h.store.lastResult.result, "unknown");
    assert.equal(h.store.appVersion, "0.7.0");
  });

  test("a rejected write that carries lastResult is still swallowed", async () => {
    const h = loadBackground({
      config: { ...LISTED, saBridgeToken: TOKEN },
      fetchImpl: answer(200, { app_version: "0.6.0", character: "mom", result: "shown" }),
    });
    h.failNextSet(new Error("storage gone"), "lastResult");
    h.message(intent());
    await flush(h);
    assert.equal(h.fetches.length, 1);
    assert.equal(h.bridgeWrites().length, 0);
    assert.equal(unhandled.length, 0);
  });
});

// ---- S-03: five-key wire object --------------------------------------------

describe("S-03 wire allowlist", () => {
  test("extra keys on the message never reach the wire (S-03)", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    const msg = intent();
    h.message({ ...msg, extraPrivateField: "synthetic-only", nested: { a: 1 }, hostname2: "leak.test" });
    await flush(h);

    assert.equal(h.fetches.length, 1);
    const body = JSON.parse(h.fetches[0].init.body);
    assert.deepEqual(Object.keys(body).sort(), ["hostname", "id", "trigger", "ts", "type"]);
    assert.deepEqual(body, msg, "the five values are the message's own");
    assert.equal("extraPrivateField" in body, false);
    assert.equal("nested" in body, false);
    assert.ok(!h.fetches[0].init.body.includes("synthetic-only"));
    assert.ok(!h.fetches[0].init.body.includes("leak.test"));

    // Logging still uses the message's id / hostname (same values).
    const log = h.logs().find((l) => l.event === "bridge.forwarded");
    assert.ok(log);
    assert.equal(log.intent_id, msg.id);
    assert.equal(log.msg, HOST);
  });

  test("a message missing id sends four keys, never five with undefined", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    h.message(intent({ id: undefined }));
    await flush(h);

    assert.equal(h.fetches.length, 1, "the fetch still happens — the app's validate() tolerates a nil id");
    const raw = h.fetches[0].init.body;
    const body = JSON.parse(raw);
    assert.equal("id" in body, false, "JSON.stringify drops the undefined key");
    assert.deepEqual(Object.keys(body), ["type", "trigger", "hostname", "ts"]);
    assert.ok(!raw.includes("undefined"));
  });

  test("the wire body carries exactly the five values, in validate() order", async () => {
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    // Keys deliberately shuffled on the message: the wire order is the worker's.
    h.message({ ts: 5, hostname: HOST, trigger: "load", id: "abc", type: "checkout_intent" });
    await flush(h);
    assert.equal(h.fetches[0].init.body,
      JSON.stringify({ id: "abc", type: "checkout_intent", trigger: "load", hostname: HOST, ts: 5 }));
  });
});

after(() => {
  assert.equal(unhandled.length, 0, `unhandled rejections leaked: ${unhandled.map(String).join("; ")}`);
});
