// Spending Angel — service-worker tests (audit fixes EXT-03, NATIVE-01 client).
// Run with: node --test extension/tests/*.test.js
//
// EXT-03:    content-script reconciles are serialized, so a stale "everywhere"
//            run can never finish after a newer "listed" run and re-register
//            *://*/*. A failing reconcile logs and never wedges the queue.
// NATIVE-01: forward() authenticates to the bridge with the pairing token
//            (Authorization: Bearer <token>); with no/malformed token it does
//            not fetch, leaves no timer behind, and marks the popup unpaired.
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

    // 2. storage.get throws → escapes reconcile, caught by the tail.
    h.failNextGet(new Error("storage gone"));
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
    await h.listeners.onInstalled[0]();
    await h.tick();

    assert.equal(h.store.saInitialized, true);
    assert.equal(h.store.saMode, "listed");
    assert.ok(h.store.saAllowlist.includes("amazon.com"));
    assert.deepEqual(Array.from(h.store.saBlocklist), []);
    assert.ok(h.logEvents().includes("sites.seeded"));
    assert.ok(h.active, "sync ran after seeding");

    // Second install event (e.g. update) must not re-seed over user edits.
    h.setConfig({ saAllowlist: ["only.mine.test"] });
    await h.listeners.onInstalled[0]();
    await h.tick();
    assert.deepEqual(Array.from(h.store.saAllowlist), ["only.mine.test"]);
    assert.equal(h.logEvents().filter((e) => e === "sites.seeded").length, 1);
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
    assert.ok(init.signal, "abort signal attached");

    assert.deepEqual(h.bridgeWrites().at(-1), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
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

    assert.deepEqual(h.bridgeWrites().at(-1), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
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
    assert.deepEqual(h.bridgeWrites().at(-1), { bridgeOk: true, bridgeAt: h.clock.now, bridgeWhy: null });
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
    // downstream (fetch, AbortController, 4 s timer) may have been created.
    const h = loadBackground({ config: { ...LISTED, saBridgeToken: TOKEN } });
    h.failNextGet(new Error("storage gone"));
    await h.ctx.forward(intent()).catch(() => {});
    await flush(h);
    assert.equal(h.fetches.length, 0);
    assert.equal(h.timers.length, 0);
    assert.equal(h.bridgeWrites().length, 0);
  });
});

after(() => {
  assert.equal(unhandled.length, 0, `unhandled rejections leaked: ${unhandled.map(String).join("; ")}`);
});
