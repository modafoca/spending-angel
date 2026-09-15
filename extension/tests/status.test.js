// Spending Angel — status wording tests (Round 3, spec B).
// Run with: node --test extension/tests/*.test.js
//
// status.js is the one place the popup and the Options page get their
// "Connection" / "Last request" / version lines from. Every string here is
// pinned on purpose: both surfaces must say exactly this, and a wording change
// is a decision, not a side effect. fmtTime is injected so the clock never
// enters the assertions.

const { test, describe } = require("node:test");
const assert = require("node:assert/strict");
const {
  saConnectionText, saLastResultText, saVersionHint, saSimulatedIntent, saCharacterName,
} = require("../status.js");

const AT = 1_700_000_000_000;
const fmt = (ms) => `T${ms}`;

// ---- saConnectionText -------------------------------------------------------

describe("saConnectionText", () => {
  test("null / undefined ok → Not tried yet, neutral, no pairing", () => {
    for (const bridgeOk of [null, undefined]) {
      assert.deepEqual(saConnectionText({ bridgeOk, bridgeAt: AT, bridgeWhy: null }, fmt),
        { text: "Not tried yet", tone: "neutral", needsPairing: false });
    }
    assert.deepEqual(saConnectionText({}, fmt), { text: "Not tried yet", tone: "neutral", needsPairing: false });
    assert.deepEqual(saConnectionText(undefined, fmt), { text: "Not tried yet", tone: "neutral", needsPairing: false });
  });

  test("ok → Connected ✓ with the formatted time", () => {
    assert.deepEqual(saConnectionText({ bridgeOk: true, bridgeAt: AT, bridgeWhy: null }, fmt),
      { text: `Connected ✓  T${AT}`, tone: "ok", needsPairing: false });
  });

  test("ok without a time still reads Connected (two spaces, nothing after)", () => {
    assert.equal(saConnectionText({ bridgeOk: true, bridgeAt: null }, fmt).text, "Connected ✓  ");
  });

  test("unpaired → paste the token, needs pairing", () => {
    assert.deepEqual(saConnectionText({ bridgeOk: false, bridgeAt: AT, bridgeWhy: "unpaired" }, fmt),
      { text: "Not paired ✕ — paste the app's token", tone: "bad", needsPairing: true });
  });

  test("unauthorized → re-pair, needs pairing", () => {
    assert.deepEqual(saConnectionText({ bridgeOk: false, bridgeAt: AT, bridgeWhy: "unauthorized" }, fmt),
      { text: "Token rejected ✕ — re-pair", tone: "bad", needsPairing: true });
  });

  test("unreachable / unknown why → App not reachable ✕ with time, no pairing", () => {
    for (const bridgeWhy of ["unreachable", null, undefined, "something-new"]) {
      assert.deepEqual(saConnectionText({ bridgeOk: false, bridgeAt: AT, bridgeWhy }, fmt),
        { text: `App not reachable ✕  T${AT}`, tone: "bad", needsPairing: false });
    }
  });

  test("ok is strictly true/false, never truthy", () => {
    assert.equal(saConnectionText({ bridgeOk: "true", bridgeAt: AT }, fmt).tone, "ok",
      "a string is truthy — same as the popup before Round 3");
    assert.equal(saConnectionText({ bridgeOk: 0, bridgeAt: AT, bridgeWhy: "unpaired" }, fmt).needsPairing, true);
  });
});

// ---- saLastResultText -------------------------------------------------------

describe("saLastResultText", () => {
  const base = { at: AT, intent_id: "abc", hostname: "shop.example.test", trigger: "click" };

  test("nothing stored → No request sent yet", () => {
    for (const v of [null, undefined, "", 0, "shown"]) {
      assert.deepEqual(saLastResultText(v, fmt), { text: "No request sent yet", tone: "neutral" });
    }
  });

  test("shown → Character shown — Name · time, with the four known names", () => {
    const names = { angel: "Angel", papi: "Papi", wizard: "Wizard", mom: "Mom" };
    for (const [id, name] of Object.entries(names)) {
      assert.deepEqual(saLastResultText({ ...base, result: "shown", character: id }, fmt),
        { text: `Character shown — ${name} · T${AT}`, tone: "ok" });
    }
  });

  test("shown with an unknown character id → capitalised as-is", () => {
    assert.equal(saLastResultText({ ...base, result: "shown", character: "robot" }, fmt).text,
      `Character shown — Robot · T${AT}`);
    assert.equal(saLastResultText({ ...base, result: "shown", character: "Robot" }, fmt).text,
      `Character shown — Robot · T${AT}`);
    assert.equal(saCharacterName("mom"), "Mom");
    assert.equal(saCharacterName("x"), "X");
    assert.equal(saCharacterName(""), "");
    assert.equal(saCharacterName(undefined), "");
  });

  test("shown without a character → Character shown · time", () => {
    assert.deepEqual(saLastResultText({ ...base, result: "shown" }, fmt),
      { text: `Character shown · T${AT}`, tone: "ok" });
  });

  test("skipped off → switched off, bad", () => {
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "off" }, fmt),
      { text: "Not shown — the app is switched off (turn it on in the menu bar)", tone: "bad" });
  });

  test("skipped snoozed → until the parsed snooze_until, bad", () => {
    const until = "2026-09-15T22:43:54Z";
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "snoozed", snooze_until: until }, fmt),
      { text: `Not shown — snoozed until T${Date.parse(until)} (Wake up in the menu bar)`, tone: "bad" });
  });

  test("skipped snoozed without (or with an unparsable) snooze_until → snoozed, bad", () => {
    const want = { text: "Not shown — snoozed (Wake up in the menu bar)", tone: "bad" };
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "snoozed" }, fmt), want);
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "snoozed", snooze_until: "soon" }, fmt), want);
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "snoozed", snooze_until: 5 }, fmt), want);
  });

  test("skipped busy → already on screen, neutral", () => {
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "busy" }, fmt),
      { text: "Not shown — a character was already on screen", tone: "neutral" });
  });

  test("skipped throttled → too soon, with the wait when known", () => {
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "throttled", retry_in_s: 5 }, fmt),
      { text: "Not shown — too soon after the last catch (wait 5 s)", tone: "neutral" });
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "throttled" }, fmt),
      { text: "Not shown — too soon after the last catch", tone: "neutral" });
    assert.equal(saLastResultText({ ...base, result: "skipped", reason: "throttled", retry_in_s: "5" }, fmt).text,
      "Not shown — too soon after the last catch", "a non-number wait is not shown");
  });

  test("unknown (older app), or a result/reason this sensor doesn't know → update the app", () => {
    const want = { text: "App answered, but didn't say what it did — update the app", tone: "neutral" };
    assert.deepEqual(saLastResultText({ ...base, result: "unknown" }, fmt), want);
    assert.deepEqual(saLastResultText({ ...base, result: "skipped" }, fmt), want);
    assert.deepEqual(saLastResultText({ ...base, result: "skipped", reason: "tired" }, fmt), want);
    assert.deepEqual(saLastResultText({ ...base, result: "danced" }, fmt), want);
    assert.deepEqual(saLastResultText({ at: AT }, fmt), want);
  });

  test("every line keeps the voice: no exclamation marks, no system-ese", () => {
    const cases = [
      null,
      { ...base, result: "shown", character: "mom" },
      { ...base, result: "skipped", reason: "off" },
      { ...base, result: "skipped", reason: "snoozed", snooze_until: "2026-09-15T22:43:54Z" },
      { ...base, result: "skipped", reason: "snoozed" },
      { ...base, result: "skipped", reason: "busy" },
      { ...base, result: "skipped", reason: "throttled", retry_in_s: 3 },
      { ...base, result: "unknown" },
    ];
    const seen = new Set();
    for (const c of cases) {
      const { text, tone } = saLastResultText(c, fmt);
      seen.add(text);
      assert.ok(!text.includes("!"), text);
      assert.doesNotMatch(text, /error|failed|exception|null|undefined/i, text);
      assert.ok(["ok", "bad", "neutral"].includes(tone));
    }
    assert.equal(seen.size, cases.length, "every case reads differently");
  });
});

// ---- saVersionHint ----------------------------------------------------------

describe("saVersionHint", () => {
  test("null when major.minor agree (patch may differ)", () => {
    assert.equal(saVersionHint("0.6.0", "0.6.0"), null);
    assert.equal(saVersionHint("0.6.0", "0.6.3"), null);
    assert.equal(saVersionHint("0.6.1", "0.6.0"), null);
    assert.equal(saVersionHint("1.2", "1.2.9"), null);
  });

  test("null when the app version is missing or unreadable", () => {
    for (const a of [null, undefined, "", "unknown", 6, {}]) {
      assert.equal(saVersionHint("0.6.0", a), null, `app ${JSON.stringify(a)}`);
    }
    assert.equal(saVersionHint(undefined, "0.6.0"), null, "no sensor version either");
    assert.equal(saVersionHint("dev", "0.6.0"), null);
  });

  test("app older → update the app", () => {
    assert.equal(saVersionHint("0.6.0", "0.5.0"), "Sensor v0.6.0 · App v0.5.0 — update the app");
    assert.equal(saVersionHint("1.0.0", "0.9.9"), "Sensor v1.0.0 · App v0.9.9 — update the app");
    assert.equal(saVersionHint("0.10.0", "0.9.0"), "Sensor v0.10.0 · App v0.9.0 — update the app",
      "numeric, not lexical");
  });

  test("sensor older → reload the extension", () => {
    assert.equal(saVersionHint("0.5.0", "0.6.0"),
      "Sensor v0.5.0 · App v0.6.0 — reload the extension at chrome://extensions");
    assert.equal(saVersionHint("0.9.0", "1.0.0"),
      "Sensor v0.9.0 · App v1.0.0 — reload the extension at chrome://extensions");
  });
});

// ---- saSimulatedIntent ------------------------------------------------------

describe("saSimulatedIntent", () => {
  test("exactly the five wire keys, in validate() order, with the given clock", () => {
    const p = saSimulatedIntent(AT);
    assert.deepEqual(Object.keys(p), ["id", "type", "trigger", "hostname", "ts"]);
    assert.equal(p.type, "checkout_intent");
    assert.equal(p.trigger, "simulated");
    assert.equal(p.hostname, "example-shop.test");
    assert.equal(p.ts, AT);
    assert.match(p.id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  test("a fresh id every call, and now defaults to Date.now()", () => {
    const before = Date.now();
    const a = saSimulatedIntent();
    const b = saSimulatedIntent();
    assert.notEqual(a.id, b.id);
    assert.ok(a.ts >= before && a.ts <= Date.now());
  });
});
