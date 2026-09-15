// Spending Angel — content-script tests (audit fixes EXT-01, EXT-02).
// Run with: node --test extension/tests/*.test.js
//
// EXT-01: the site policy (mode + lists) is re-read from storage on EVERY
//         event, so a tab paused/unlisted after injection goes quiet without
//         a navigation, and resumes without one too.
// EXT-02: only user-gesture clicks (e.isTrusted) count — a page dispatching
//         synthetic MouseEvents must not produce an intent, a log line, or a
//         storage write.
//
// The real content.js is evaluated in a vm context by tests/harness.js.

const { test, describe, after } = require("node:test");
const assert = require("node:assert/strict");
const { loadContentScript } = require("./harness.js");

// sendIntent's try/catch must swallow a rejecting chrome.storage call; if it
// ever leaks, this guard turns the leak into a failing test instead of a
// process crash whose cause is hard to read.
const unhandled = [];
process.on("unhandledRejection", (e) => { unhandled.push(e); });

const HOST = "shop.example.test";
const LISTED = { saMode: "listed", saAllowlist: [HOST], saBlocklist: [] };
const EVERYWHERE = { saMode: "everywhere", saAllowlist: [], saBlocklist: [] };

const lastIntentWrites = (h) => h.writes.filter((w) => "lastIntent" in w);
const countEvent = (h, ev) => h.logEvents().filter((e) => e === ev).length;

async function flush(h, n = 2) {
  for (let i = 0; i < n; i++) await h.tick();
}

// ---- EXT-01: policy is judged per event -------------------------------------

describe("EXT-01 policy per event", () => {
  test("listed: click on an allowlisted host emits one intent", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);

    assert.equal(h.messages.length, 1);
    const msg = h.messages[0];
    assert.equal(msg.trigger, "click");
    assert.equal(msg.hostname, HOST);
    assert.equal(msg.type, "checkout_intent");
    assert.equal(msg.ts, h.clock.now);
    assert.match(msg.id, /^[0-9a-f-]{36}$/);
    // Privacy stance: exactly these five keys leave the page, nothing else.
    assert.deepEqual(Object.keys(msg).sort(), ["hostname", "id", "trigger", "ts", "type"]);

    assert.equal(lastIntentWrites(h).length, 1);
    assert.deepEqual(lastIntentWrites(h)[0].lastIntent, msg);
    assert.ok(h.logEvents().includes("sensor.intent"));
    const entry = h.logs().find((l) => l.event === "sensor.intent");
    assert.equal(entry.level, "info");
    assert.equal(entry.intent_id, msg.id);
  });

  test("listed: host not in the allowlist is suppressed", async () => {
    const h = loadContentScript({ hostname: HOST, config: { ...LISTED, saAllowlist: ["other.test"] } });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);

    assert.equal(h.messages.length, 0);
    assert.equal(lastIntentWrites(h).length, 0);
    assert.equal(h.lastLog().event, "sensor.suppressed");
    assert.equal(h.lastLog().level, "debug");
  });

  test("everywhere: site paused after injection is suppressed without navigation", async () => {
    const h = loadContentScript({ hostname: HOST, config: EVERYWHERE });
    h.setConfig({ saBlocklist: [HOST] });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);

    assert.equal(h.messages.length, 0);
    assert.equal(lastIntentWrites(h).length, 0);
    assert.equal(h.lastLog().event, "sensor.suppressed");
    assert.equal(h.lastLog().level, "debug");
    assert.equal(countEvent(h, "sensor.intent"), 0);
  });

  test("everywhere: initially paused, resumed later, emits", async () => {
    const h = loadContentScript({ hostname: HOST, config: { ...EVERYWHERE, saBlocklist: [HOST] } });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 0);

    h.setConfig({ saBlocklist: [] });
    h.clock.advance(2000);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
    assert.equal(h.messages[0].trigger, "click");
  });

  test("listed: 'Stop watching' then 'Watch this site' toggles without navigation", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);

    h.setConfig({ saAllowlist: [] });
    h.clock.advance(2000);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1, "unlisted host must not emit");
    assert.equal(h.lastLog().event, "sensor.suppressed");

    h.setConfig({ saAllowlist: [HOST] });
    h.clock.advance(2000);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 2, "re-listed host emits again");
  });

  test("mode flip everywhere→listed is honoured in an already-injected tab", async () => {
    const h = loadContentScript({ hostname: HOST, config: EVERYWHERE });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);

    h.setConfig({ saMode: "listed", saAllowlist: [] });
    h.clock.advance(2000);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
    assert.equal(h.lastLog().event, "sensor.suppressed");
  });

  test("listed: host removed from the list suppresses the queued load AND later clicks", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    await h.tick(); // main() parks on its first storage get; the timer exists after that
    assert.equal(h.timers.length, 1);
    assert.equal(h.timers[0].ms, 800);

    h.setConfig({ saAllowlist: [] });
    h.fireTimers();
    await flush(h);
    h.clock.advance(2000); // judged by policy, not by the cooldown
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);

    assert.equal(h.messages.length, 0);
    assert.equal(lastIntentWrites(h).length, 0);
    assert.equal(countEvent(h, "sensor.suppressed"), 2);
    assert.equal(countEvent(h, "sensor.intent"), 0);
  });

  test("listed: the queued load fires as an intent when the host stays listed", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    await h.tick();
    h.fireTimers();
    await flush(h);
    assert.equal(h.messages.length, 1);
    assert.equal(h.messages[0].trigger, "load");
    assert.equal(h.timers.length, 0, "fireTimers clears the captured timer");
  });

  test("everywhere: load fires only on known shopping domains", async () => {
    const shop = loadContentScript({ hostname: "amazon.com", config: EVERYWHERE });
    await shop.tick();
    assert.equal(shop.timers.length, 1);

    const wwwShop = loadContentScript({ hostname: "www.amazon.com", config: EVERYWHERE });
    await wwwShop.tick();
    assert.equal(wwwShop.timers.length, 1, "www. prefix still matches the domain list");

    const blog = loadContentScript({ hostname: "blog.example.test", config: EVERYWHERE });
    await blog.tick();
    assert.equal(blog.timers.length, 0);

    const listedBlog = loadContentScript({
      hostname: "blog.example.test",
      config: { ...LISTED, saAllowlist: ["blog.example.test"] },
    });
    await listedBlog.tick();
    assert.equal(listedBlog.timers.length, 1);
  });

  test("everywhere: load on a known shop paused during the 800 ms is suppressed at fire time", async () => {
    const h = loadContentScript({ hostname: "amazon.com", config: EVERYWHERE });
    await h.tick();
    assert.equal(h.timers.length, 1);
    h.setConfig({ saBlocklist: ["amazon.com"] });
    h.fireTimers();
    await flush(h);
    assert.equal(h.messages.length, 0);
    assert.equal(h.lastLog().event, "sensor.suppressed");
    assert.match(h.lastLog().msg, /^load on amazon\.com/);
  });

  test("everywhere: click watcher is attached even when the host is paused at injection", () => {
    const h = loadContentScript({ hostname: HOST, config: { ...EVERYWHERE, saBlocklist: [HOST] } });
    assert.ok(Array.isArray(h.listeners.click) && h.listeners.click.length === 1);
    assert.equal(h.listeners.clickCapture, true, "listener is capture-phase");
  });

  test("click watcher is attached synchronously, before any storage read resolves", () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    // No tick: main() has not passed its first await yet.
    assert.equal((h.listeners.click || []).length, 1);
  });

  test("cooldown still applies", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.buyButton(), isTrusted: true });
    h.clock.advance(100);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);

    h.clock.advance(1500);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 2);
  });

  test("cooldown gate is synchronous: two events in the same tick yield one intent", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    // Both clicks land before any await resolves — only the first may pass.
    h.click({ target: h.buyButton(), isTrusted: true });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
    assert.equal(countEvent(h, "sensor.intent"), 1);
  });

  test("a suppressed event still consumes the cooldown (stamp happens before policy)", async () => {
    const h = loadContentScript({ hostname: HOST, config: { ...EVERYWHERE, saBlocklist: [HOST] } });
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.lastLog().event, "sensor.suppressed");

    h.setConfig({ saBlocklist: [] });
    h.clock.advance(100); // inside the cooldown window
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 0, "still within COOLDOWN_MS of the suppressed event");
  });

  test("does not throw when chrome.storage rejects (context invalidated)", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    await h.tick(); // let main() finish its own get so the armed failure hits sendIntent
    const logsBefore = h.logs().length;
    const writesBefore = h.writes.length;

    h.failNextGet(new Error("Extension context invalidated."));
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);

    assert.equal(unhandled.length, 0, "sendIntent must swallow the rejection");
    assert.equal(h.messages.length, 0);
    assert.equal(h.writes.length, writesBefore);
    assert.equal(h.logs().length, logsBefore, "the catch is silent by contract");
  });

  test("a rejected lastIntent write is swallowed and does not block delivery", async () => {
    // The try/catch in sendIntent only catches a synchronous throw; the
    // fire-and-forget set() must carry its own .catch (quality review R-01).
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    await h.tick();
    h.failNextSet(new Error("Extension context invalidated."), "lastIntent");
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);

    assert.equal(unhandled.length, 0, "the lastIntent set() must not leak a rejection");
    assert.equal(lastIntentWrites(h).length, 0, "the failed write was not recorded");
    assert.equal(h.messages.length, 1, "delivery does not depend on the storage write");
  });

  test("the sensor keeps working after a transient storage failure", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    await h.tick();
    h.failNextGet(new Error("Extension context invalidated."));
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 0);

    h.clock.advance(2000);
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
  });

  test("sendMessage rejection (SW asleep / context gone) is swallowed", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.chrome.runtime.sendMessage = () => Promise.reject(new Error("Receiving end does not exist."));
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(unhandled.length, 0);
    assert.equal(lastIntentWrites(h).length, 1, "detection worked even though delivery failed");
  });
});

// ---- EXT-02: isTrusted -----------------------------------------------------

describe("EXT-02 isTrusted", () => {
  test("synthetic click is ignored entirely", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    const logsBefore = h.logs().length;
    h.click({ target: h.buyButton(), isTrusted: false });
    await flush(h);

    assert.equal(h.messages.length, 0);
    assert.equal(h.writes.length, 0, "no storage write at all");
    assert.equal(h.logs().length, logsBefore, "no log line");
  });

  test("trusted click on the same element emits", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    const el = h.buyButton();
    h.click({ target: el, isTrusted: false });
    await flush(h);
    assert.equal(h.messages.length, 0);

    h.click({ target: el, isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
  });

  test("event without isTrusted (undefined) is ignored", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.buyButton() });
    await flush(h);
    assert.equal(h.messages.length, 0);
    assert.equal(h.writes.length, 0);
  });

  test("synthetic click does not consume the cooldown", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.buyButton(), isTrusted: false });
    // A real click right after must still pass — the synthetic one never
    // reached sendIntent, so lastTrigger was not stamped.
    h.click({ target: h.buyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
  });

  test("synthetic click flood does not grow saLogs", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    const logsBefore = h.logs().length;
    for (let i = 0; i < 200; i++) h.click({ target: h.buyButton(), isTrusted: false });
    await flush(h);
    assert.equal(h.logs().length, logsBefore);
    assert.equal(h.writes.length, 0);
    assert.equal(h.messages.length, 0);
  });

  test("trusted click on a non-buy element is ignored", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.plainSpan(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 0);
    assert.equal(h.writes.length, 0);
  });

  test("trusted click on a hidden buy button is ignored", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.hiddenBuyButton(), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 0);
  });

  test("trusted click on a child of a buy button walks up to the ancestor", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    const child = h.plainSpan("icon");
    child.parentElement = h.buyButton();
    h.click({ target: child, isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
  });

  test("links: whole-phrase link emits, prose link does not", async () => {
    const h = loadContentScript({ hostname: HOST, config: LISTED });
    h.click({ target: h.buyLink("Checkout our latest blog post"), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 0);

    h.click({ target: h.buyLink("Checkout"), isTrusted: true });
    await flush(h);
    assert.equal(h.messages.length, 1);
  });
});

after(() => {
  assert.equal(unhandled.length, 0, `unhandled rejections leaked: ${unhandled.map(String).join("; ")}`);
});
