# Spending Angel — Design Spec, Round 2 (branch `fix/audit-2026-09`, PR #1)

Source brief: `docs/review-validation-r2.md` (binding scope and constraints). Reviewed head `fff0f1a`.
Round 1 contracts this document must stay consistent with: `docs/design-spec.md` (§3a bridge HTTP contract, §3c storage keys, §3d/§3e function contracts) and the decisions in `docs/audit-validation.md`.
Two tracks: **A = `extension/`** (items 1–4), **B = `mac-app/` + CI** (items 5–8). Item 9 (docs) is listed in §6. Every item below is implementable from this file alone; the cross-track invariants are restated in §4.

---

## 1. Goals / non-goals

**Goals.** Close the nine Round 2 items with the smallest correct, testable change:

1. **R-01 / Q-02** — a paused or unlisted site leaves *no trace*: the denied-policy branch of `sendIntent` logs nothing, so its hostname never reaches the console or the `saLogs` ring.
2. **S-03** — `forward()` serializes a freshly built five-key `wire` object, never the message it received, so a key smuggled onto the runtime message cannot reach the bridge.
3. **R-02 / S-02 / S-07** — no promise in the extension can reject unhandled when `chrome.storage` is torn down: the `log.js` ring write is one awaited chain with a terminal `.catch`, the token read in `forward()` is contained, the `onMessage` listener contains `forward()`, and `content.js` boots with `void main().catch(() => {})`. None of the containment paths logs (logging would recurse into the same dead storage).
4. **Options wording** — saving a token says "Token saved — waiting for the app to confirm"; "Paired" appears only once the app has actually answered (`bridgeOk === true`); an app that stopped answering says so in the same "Token saved —" voice. The live re-render that keeps an open Options page current never touches the token input's `value` (a mid-paste must survive a status flip).
5. **R-03** — `validate()` bounds the *raw* hostname (≤ 253 UTF-8 bytes) before trimming, so a padded hostname can no longer pass validation and reach the log sinks unclipped; the two hostname log sites (`catch.skipped_off_duty`, `CatchRunner`) also clip, belt and braces.
6. **S-04 / Q-12** — rejection log lines in `BridgeServer` are bounded in *count*: one line per second per throttle key, with `suppressed: "<n>"` + `suppressed_since: "<ISO ts>"` fields on the first line after a busy window (so a burst followed by hours of silence is still attributable). The key is the event name, except `bridge.unauthorized`, which is keyed per `reason` so a token-guessing `mismatch` is never hidden behind a no-token `missing` flood. Injectable clock; pure enough to unit-test.
7. **Wording** — `BridgeServer` header comment corrected (auth precedes *decode*, not body buffering; a page *can* send a simple POST, it just gets `401` and cannot read the answer; constant time is a source-level property); `tokenMatches` doc comment says "no data-dependent early exit in source; compiler-level timing not guaranteed".
8. **CI** — the macOS job pins `DEVELOPER_DIR` to Xcode 16.4 and keeps `runs-on: macos-15`; no third-party actions.
9. **Docs** — `docs/review-report.md` gains a Round 2 section; the root README's pairing step follows the new Options wording.

**Non-goals.** No change to the wire payload shape (`{id,type,trigger,hostname,ts}`), to any HTTP status code, to the evaluation order pinned by `gate()`, to `Log.clip` semantics, to the popup (`renderBridge`, `renderEvents` untouched), to `saShouldWatch`, to the 8 s / 4 s / 10 s / 1.5 s timings, to `CatchRunner.run`'s signature, or to `Store`. S-05 (respond before overlay work) and Q-11 (parallel permission lookups) stay deferred per the brief. No new visual style; the Options strings keep the pixel-game tone. No new npm/SwiftPM dependency. Not touched: `sounds/`, `extension/preview.html`, `*.ai`, PRM/mission markdown at the repo root. Sub-agents do not commit.

**Baselines that must not dip:** extension 103 pass (`node --test extension/tests/*.test.js`), native 107 tests / 8 suites (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app`). Expected after Round 2: extension ≈ 122 pass, native ≈ 126 tests / 9 suites (counts are indicative; the gate checks "all pass", not the number).

---

## 2. Contracts per item

### Item 1 — R-01 / Q-02: silent suppression in `content.js`

**Change.** In `sendIntent(trigger)`, the denied-policy branch becomes a bare return:

```js
      const cfg = await chrome.storage.local.get({ saMode: "listed", saAllowlist: [], saBlocklist: [] });
      if (!saShouldWatch(host, { mode: cfg.saMode, allowlist: cfg.saAllowlist, blocklist: cfg.saBlocklist })) {
        // Not watched right now: nothing is logged, stored or sent (review R-01).
        // A paused site is the user's "leave me alone" — its name must not land
        // in the console or the saLogs ring, and the popup must not learn of it.
        return;
      }
```

Everything else in `sendIntent` is unchanged: the cooldown stamp still happens before the `await` (a suppressed event still consumes the 1.5 s cooldown — Round 1 contract, `content.test.js` "a suppressed event still consumes the cooldown"), `lastIntent` is still written only after the policy passes, and the `sensor.intent` log line is unchanged.

**Privacy invariant (restated, now complete).** For a host the current policy does not watch, the content script produces: zero `saLog` calls, zero `console.*` calls, zero `chrome.storage.local.set` calls, zero `chrome.runtime.sendMessage` calls. The only observable side effect is the cooldown stamp in the script's own closure. `sensor.suppressed` is **retired** as an event name — nothing emits it; `popup.renderEvents` does not need to know (it renders whatever is in the ring and stays byte-for-byte as is).

Update the `content.js` header comment bullet 2 ("The user's site policy … is re-read from storage on EVERY event") to add: "and a denied event is dropped silently — no log line, so a paused site's name never reaches the ring."

### Item 2 — S-03: five-key `wire` object in `forward()`

**Change.** Immediately before `fetch` (after the token/timer setup), build the outbound body from named keys only:

```js
  // The wire payload is rebuilt from named keys (review S-03): whatever else a
  // runtime message carries — a page can't reach onMessage, but a future popup
  // or a bug could — never leaves the worker. Exactly the five keys the app's
  // validate() knows about, in this order.
  const wire = {
    id: payload.id,
    type: payload.type,
    trigger: payload.trigger,
    hostname: payload.hostname,
    ts: payload.ts,
  };
  ...
      body: JSON.stringify(wire),
```

Logging keeps using `payload.id` / `payload.hostname` (same values). `JSON.stringify` drops keys whose value is `undefined`, so a message missing a key produces a body with fewer than five keys — never more (edge case 18). No type coercion, no validation: the app's `validate()` remains the single validator.

Update the `background.js` header comment (job 2) with one sentence: "Only `{id,type,trigger,hostname,ts}` is serialized to the bridge, rebuilt from named keys."

### Item 3 — R-02 / S-02 / S-07: containment of every storage promise

**(a) `log.js` — the ring write.** Replace the callback-form `get` + bare `set` and the surrounding `try/catch` with one awaited async IIFE:

```js
function saLog(level, event, msg, fields = {}) {
  const entry = Object.assign(
    { ts: new Date().toISOString(), level, event, msg },
    fields
  );
  const print = level === "error" ? console.error : console.log;
  print(`[SA ${level}] ${event} — ${msg}`, fields);

  // Ring write: one awaited chain with a terminal catch (review R-02). A torn-
  // down storage (extension reloaded under a live tab, worker shutting down)
  // must neither surface as an unhandled rejection nor be re-logged — logging
  // the failure would recurse into the same dead storage. Console already has
  // the line. Read-modify-write isn't atomic across tabs; for a debug ring the
  // worst case is a lost line, which is fine. A corrupted ring (not an array)
  // is replaced rather than left wedged.
  void (async () => {
    const s = await chrome.storage.local.get({ saLogs: [] });
    const prior = Array.isArray(s.saLogs) ? s.saLogs : [];
    await chrome.storage.local.set({ saLogs: prior.concat(entry).slice(-SA_LOG_MAX) });
  })().catch(() => {});
}
```

Contract: `saLog` returns `undefined` synchronously; it never throws (a missing `chrome` global becomes a rejection inside the async function and is swallowed); it never calls `saLog`, `console.*`, or any `chrome.*` API from its catch; the console line is printed exactly once per call regardless of storage state. `SA_LOG_MAX = 50` and `module.exports = { saLog, SA_LOG_MAX }` unchanged. Note the switch from the **callback form** to the **promise form** of `storage.local.get` — this matters for the harness (§5, knob `failNextGet(err, key)`).

**Documented race (edge case 28).** Two `saLog` calls in the *same synchronous turn* both read the pre-write ring and each writes `prior.concat(entry)` — the last writer wins and one line is lost. This is true in real Chrome (both `get` IPCs answer before either `set` lands) and it was also true of the callback form outside the harness; it is accepted for a debug ring ("worst case is a lost line"). No shipped path does it: every consecutive pair of `saLog` calls in `background.js` (`sites.seeded` → `sites.registered`, the `forward()` branches) and `content.js` (`sensor.intent`) is separated by an `await` on storage, scripting or `fetch`. Tests that fill the ring therefore `await flush(h)` between calls (§5b, `log.test.js`); the harness does **not** try to serialize back-to-back calls (§5a explains why it cannot).

**(b) `background.js` — `forward()` token read and the listener.**

```js
chrome.runtime.onMessage.addListener((msg) => {
  // Containment: forward() owns its own error handling, but a rejection that
  // still escapes must not become an unhandled rejection in the worker.
  if (msg && msg.type === "checkout_intent") forward(msg).catch(() => {});
  // No async response needed — fire and forget.
});

async function forward(payload) {
  // Token first, before any timer exists: an unpaired call must leave nothing
  // behind that keeps the worker (or a test's event loop) awake for 4 s.
  let token = "";
  try {
    const { saBridgeToken } = await chrome.storage.local.get({ saBridgeToken: "" });
    token = saNormalizeBridgeToken(saBridgeToken);
  } catch (e) {
    // Storage is gone (worker torn down / extension reloaded). Log nothing —
    // saLog would write to the same dead storage — set nothing, send nothing.
    return;
  }
  if (token === "") { ...unchanged unpaired branch... }
  ...unchanged...
}
```

Contract for the failed-token-read path: no `saLog`, no `console.*`, no `chrome.storage.local.set`, no `fetch`, no `AbortController`, no `setTimeout`; `forward()` resolves (does not reject). The unpaired branch, the fetch, the four response branches and `finally { clearTimeout(timer) }` are unchanged from Round 1 §3d.

**(c) `content.js` — entry point.** Last line of the IIFE becomes:

```js
  // Boot is fire-and-forget; a storage read that rejects at injection time
  // (context already invalidated) must not surface in the page's console.
  void main().catch(() => {});
```

`main()` itself is unchanged: `attachClickWatcher()` runs synchronously before the first `await`, so a failed boot read still leaves the click path armed (clicks re-read policy themselves); only the 800 ms load timer is lost.

### Item 4 — Options pairing status wording

**`options.js` `renderToken()`** reads three keys in one call and renders one of five strings into `#token-state`. It no longer touches `input.value`: with the live re-render below, a service-worker write that flips `bridgeOk` while the user is mid-paste must not wipe the field. Clearing the field is `saveToken`'s job (below), on its two success paths only.

```js
async function renderToken() {
  const { saBridgeToken, bridgeOk, bridgeWhy } =
    await chrome.storage.local.get({ saBridgeToken: "", bridgeOk: null, bridgeWhy: null });
  const token = saNormalizeBridgeToken(saBridgeToken);
  const input = $("token-input");
  // Placeholder + status only. The field's value belongs to the user (a paste
  // in progress) and is cleared by saveToken on success, never by a re-render.
  if (!token) {
    input.placeholder = "paste the 64-character token";
    $("token-state").textContent = TOKEN_STATE_NONE;
    return;
  }
  const tail = token.slice(-4);
  input.placeholder = `••••…${tail}`;
  $("token-state").textContent = tokenStateText(bridgeOk, bridgeWhy, tail);
}
```

with the strings and the pure selector. **Reachability from tests:** only `function` declarations become properties of the vm global, so `tokenStateText` is callable as `h.ctx.tokenStateText(...)`; the top-level `const TOKEN_STATE_*` strings are script-scoped and are **not** on `h.ctx` — `ui.test.js` hardcodes the expected strings, as it already does for `Not paired — …` (§5b).

```js
const TOKEN_STATE_NONE        = "Not paired — the app will not answer until you paste the token.";
const TOKEN_STATE_SAVED       = (tail) => `Token saved — waiting for the app to confirm (…${tail}). Try "Simulate intent" in the popup.`;
const TOKEN_STATE_UNREACHABLE = (tail) => `Token saved — the app isn't answering yet (…${tail}). Is Spending Angel running?`;
const TOKEN_STATE_PAIRED      = (tail) => `Paired — token ends in …${tail}`;
const TOKEN_STATE_REJECTED    = (tail) => `Token rejected — copy it again from PAIR SENSOR (…${tail})`;
const TOKEN_JUNK_MSG          = "hmm, that doesn't look like a token (64 hex characters)";   // unchanged

// Which pairing line to show for a stored token. "Paired" is a claim the app
// has to earn: only a real 200 (bridgeOk === true) unlocks it. A save resets
// the bridge keys to null, so a fresh save always reads as "waiting". An app
// that stopped answering keeps the "Token saved" prefix (the token is fine)
// and says what to check instead of inviting a retry that fails the same way.
function tokenStateText(bridgeOk, bridgeWhy, tail) {
  if (bridgeOk === true) return TOKEN_STATE_PAIRED(tail);
  if (bridgeWhy === "unauthorized") return TOKEN_STATE_REJECTED(tail);
  if (bridgeWhy === "unreachable") return TOKEN_STATE_UNREACHABLE(tail);
  return TOKEN_STATE_SAVED(tail);
}
```

Both "Token saved —" strings share that prefix on purpose: the reviewer fixture's `/^Token saved/` assertion (§5d item 2) holds in either state.

**When each string shows (exhaustive):**

| Stored state | `#token-state` |
| --- | --- |
| `saBridgeToken` absent, empty, or not 64 hex | `TOKEN_STATE_NONE` |
| valid token, `bridgeOk === true` (any `bridgeWhy`) | `TOKEN_STATE_PAIRED` |
| valid token, `bridgeOk !== true`, `bridgeWhy === "unauthorized"` | `TOKEN_STATE_REJECTED` |
| valid token, `bridgeOk !== true`, `bridgeWhy === "unreachable"` | `TOKEN_STATE_UNREACHABLE` |
| valid token, otherwise (`bridgeOk` `null`/`undefined`/`false` with `bridgeWhy` `null`/`"unpaired"`/unknown) | `TOKEN_STATE_SAVED` |
| junk submitted (any stored state) | `TOKEN_JUNK_MSG` (set by `saveToken`, not by `renderToken`) |

Options deliberately reports only what the *token* has earned (paired / rejected / waiting) plus the one reachability case the user can act on; the popup stays the authority on bridge health (`renderBridge` untouched). One transient is accepted: a valid token stored while an intent was already in flight (its token read predates the save) can leave `bridgeWhy: "unpaired"` behind for one round — Options reads `TOKEN_STATE_SAVED` while the popup says `Not paired ✕`; the next intent corrects both (edge case 27). Not a bug.

Immediately after `saveToken(valid)` the one-write reset (`bridgeOk: null, bridgeAt: null, bridgeWhy: null`, Round 1 §3d) guarantees the page reads `TOKEN_STATE_SAVED`.

**`saveToken` change (field reset moves here).** The two success paths clear the field before re-rendering; the junk path leaves the user's text in place so it can be fixed, as today:

```js
  if (rawTrimmed === "") {
    await chrome.storage.local.remove(["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"]);
    $("token-input").value = "";       // the field never carries the real token past a save
    await renderToken();
    return;
  }
  ...
  await chrome.storage.local.set({ saBridgeToken: t, bridgeOk: null, bridgeAt: null, bridgeWhy: null });
  $("token-input").value = "";
  await renderToken();
```

The one-write reset, `saNormalizeBridgeToken` and the junk message are unchanged.

**Live update.** `options.js` gains a storage listener registered in `DOMContentLoaded` (same shape as `popup.js`):

```js
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes.saBridgeToken || changes.bridgeOk || changes.bridgeWhy) renderToken();
  });
```

so "Simulate intent" in the popup (or the next real intent) flips an open Options page from "Token saved — waiting…" to "Paired — …" without a reload — and, because `renderToken` no longer writes `input.value`, a paste in progress survives that flip (edge case 25). `options.html` is unchanged (the `#token-state` `<p>` already exists). Popup strings are untouched.

### Item 5 — R-03: raw hostname bound in `validate()` + clipped log sites

**`BridgeServer.validate(_:)`** — the hostname block becomes, in this exact order (type → trigger → id → hostname is preserved):

```swift
        if let id = i.id, id.utf8.count > maxIDLength { return "bad id" }
        // Bound the RAW hostname first (review R-03): trimming used to run before
        // the length check, so 20 KB of padding around a short name passed
        // validation and reached every log sink untouched. Then the trimmed
        // value must be non-empty (whitespace-only is not a hostname).
        guard i.hostname.utf8.count <= maxHostnameLength else { return "bad hostname" }
        let host = i.hostname.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return "bad hostname" }
        return nil
```

with a new pinned constant next to `maxIDLength`:

```swift
    static let maxHostnameLength = 253        // UTF-8 bytes of the RAW value, before trimming (RFC 1035 limit)
```

The problem string `"bad hostname"` is unchanged for both failure modes. The trimmed check no longer needs its own `<= 253` (trimmed ≤ raw). `Intent` is still handed to `onIntent` untouched (surrounding spaces ≤ 253 bytes total are allowed through, as before).

**Belt and braces at the two hostname log sites.** Both go through `Log.clip` so that even a caller that bypasses `validate()` (the manual Test path, a future call site, the reviewer's repro) cannot write more than 259 bytes of hostname:

```swift
// CatchRunner.swift
enum CatchRunner {
    @discardableResult
    static func run(goal:character:source:hostname:intentID:perform:record:log:) -> Bool {   // signature unchanged
        let fields = ["intent_id": intentID ?? "", "character": character.rawValue, "source": source]
        let host = Log.clip(hostname)          // bounded even if validate() was bypassed (review R-03)
        let admitted = perform(goal, character)
        if admitted { record(); log("catch.performed", host, fields) } else { log("catch.skipped_busy", host, fields) }
        return admitted
    }

    /// The bridge's off-duty branch, here rather than inline in AppDelegate so
    /// the hostname bound is one rule in one place and unit-testable.
    static func skipOffDuty(hostname: String, intentID: String?,
                            log: (String, String, [String: String]) -> Void = Log.info) {
        log("catch.skipped_off_duty", Log.clip(hostname), ["intent_id": intentID ?? ""])
    }
}
```

`AppDelegate`'s bridge closure replaces its inline `Log.info("catch.skipped_off_duty", intent.hostname, …)` with `CatchRunner.skipOffDuty(hostname: intent.hostname, intentID: intent.id)`; the rest of the closure is unchanged. `intent_id` is already bounded by `validate()` (≤ 128 bytes) and is not clipped here. `CatchRunner.swift`'s header comment gains one sentence: "Hostnames are clipped here as well as in `validate()`, so no caller can write an unbounded name."

### Item 6 — S-04 / Q-12: bounded rejection logging in `BridgeServer`

**Where the type lives — hard constraint.** The throttle is declared **inside `BridgeServer.swift`** as a nested type. Both reviewer fixtures (§5) compile `BridgeServer.swift` (+ `CatchRunner.swift`) standalone against a stub `Log` that defines only `info`, `error` and `clip(_:max:)`; a separate file or any reference to `Log.Level` / `Log.debug` / `Log.shared` from `BridgeServer.swift` breaks those fixtures and therefore the final gate.

```swift
extension BridgeServer {
    /// Per-key suppression window for rejection lines (review S-04/Q-12).
    /// Anything on this Mac can loop on the port; each rejected request used to
    /// add a line to the day's JSONL with nothing bounding the count. Now each
    /// key emits at most one line per `window`, and the first line after a
    /// busy window carries how many were dropped and when the first drop
    /// happened — a burst followed by hours of silence is still attributable.
    /// Main-queue confined like the rest of the server (no lock). `now` is
    /// injected so the algorithm is unit-tested with a fake clock.
    final class LogThrottle {
        static let defaultWindow: TimeInterval = 1

        private struct Slot { var openedAt: Date; var dropped: Int; var firstDroppedAt: Date? }
        private var slots: [String: Slot] = [:]
        private let window: TimeInterval
        private let now: () -> Date
        /// Same default options as `Log`'s `ts` formatter, so `suppressed_since`
        /// compares lexically with the surrounding lines' timestamps.
        private let iso = ISO8601DateFormatter()

        init(window: TimeInterval = LogThrottle.defaultWindow, now: @escaping () -> Date = Date.init)

        /// Decide whether a line for `key` may be written now.
        /// - Returns: `nil` → drop it. Otherwise the extra fields to merge into
        ///   the line: `[:]` normally, `["suppressed": "<n>", "suppressed_since":
        ///   "<ISO ts>"]` when `n ≥ 1` lines for this key were dropped since the
        ///   previous emitted line (`suppressed_since` = clock of the FIRST drop).
        func admit(_ key: String) -> [String: String]?
    }
}
```

**Algorithm (`admit`, verbatim semantics):**

```
t = now()
if no slot for key:               slots[key] = (openedAt: t, dropped: 0, firstDroppedAt: nil); return [:]   // first line ever: emit
elapsed = t − slot.openedAt
if 0 <= elapsed < window:         slot.dropped += 1; if slot.firstDroppedAt == nil { slot.firstDroppedAt = t }; return nil   // inside the window: drop
n = slot.dropped; since = slot.firstDroppedAt                                                  // window over (or clock went backwards)
slots[key] = (openedAt: t, dropped: 0, firstDroppedAt: nil)                                   // reopen at THIS line
return n > 0 ? ["suppressed": String(n), "suppressed_since": iso.string(from: since!)] : [:]
```

- **Window semantics.** The window opens at the timestamp of an *emitted* line and is `[openedAt, openedAt + window)`. A line at exactly `openedAt + window` (elapsed == 1.000 s) is **emitted** (edge case 10). The window is not sliding: dropped lines do not extend it.
- **`suppressed` field semantics (exact).** String decimal count of lines with the *same key* that were dropped between the previous emitted line for that key and this one. **Absent** (not `"0"`) when nothing was dropped. Present only on the first emitted line after a window in which ≥ 1 line was dropped; the counter resets to 0 at that emission. The emitted line carries its *own* `msg`/fields (the dropped lines' contents are gone; only their number and the time of the first one survive).
- **`suppressed_since` field semantics (exact).** ISO 8601 (`ISO8601DateFormatter()` defaults, e.g. `2023-11-14T22:13:20Z` — the same shape as the line's `ts`) of the clock at the *first* dropped line of the run being reported. Present exactly when `suppressed` is present, never alone. It is the only way to place a burst in time when the reporting line lands hours later (edge case 23); the reader can bound the burst as `[suppressed_since, ts]` of the reporting line. Still no token or body bytes: the value is a clock reading.
- **Clock going backwards** (`elapsed < 0`, wall-clock adjustment): treated as "window over" — emit, report any pending count (with its `suppressed_since`), reopen at `t`. A backwards jump can therefore never mute a key for longer than one real window.
- **Keys** are the event names, with one deliberate exception: `bridge.unauthorized` is keyed per `reason` (`bridge.unauthorized/missing`, `bridge.unauthorized/mismatch`), so the first *mismatch* — the one line a security reader cares about — is emitted even inside a no-token flood's window (edge case 24). The emitted event name is unchanged; only the throttle key carries the suffix. Six keys total, so the dictionary is bounded. Level is decided by the caller, not the throttle.

**Wiring in `BridgeServer`.**

```swift
    /// Rejection lines share one throttle so a local loop can't grow the log by
    /// one line per connection. Injected so a test could pin the wiring with a
    /// fake clock; production uses the default. Not a function type, so the
    /// existing trailing-closure call `BridgeServer(expectedToken:) { intent in … }`
    /// is unaffected.
    private let throttle: LogThrottle

    init(expectedToken: @escaping () -> String,
         throttle: LogThrottle = LogThrottle(),
         onIntent: @escaping (Intent) -> Void)

    /// The one door for rejection lines. `sink` is `Log.info` or `Log.error` —
    /// passed as a value so this file keeps compiling against a minimal `Log`.
    /// `key` defaults to the event name; the 401 site passes the event plus its
    /// public reason word so a mismatch is never hidden behind a missing-token
    /// flood. Never given token or body bytes: callers pass only what they log
    /// today, and the key is built from constants and the reason word only.
    private func logRejected(_ event: String, key: String? = nil,
                             _ msg: String, _ fields: [String: String] = [:],
                             via sink: (String, String, [String: String]) -> Void) {
        guard let extra = throttle.admit(key ?? event) else { return }
        sink(event, msg, fields.merging(extra) { _, new in new })
    }
```

*(As shipped after the Round 2 review, R2-05/R2-06: the property and init label are `logThrottle` — to read unambiguously next to the unrelated 8 s catch throttle — and `logRejected`'s signature keeps the positional trio contiguous: `(_ event, _ msg, _ fields = [:], key: String? = nil, via sink:)`. Behaviour identical.)*

**Call sites converted (exactly these five events / six throttle keys; levels unchanged):**

| Event | Throttle key | Level (sink) | Site | Fields (unchanged) |
| --- | --- | --- | --- | --- |
| `bridge.bad_request` | `bridge.bad_request` | `Log.error` | `read()` ×3 (431 header cap, 400 unparseable Content-Length, 413 body too large) — one shared key | none |
| `bridge.unauthorized` | `bridge.unauthorized/missing`, `bridge.unauthorized/mismatch` (`"bridge.unauthorized/" + reason`) | `Log.info` | `handle()` gate 401 | `reason: "missing" \| "mismatch"` |
| `bridge.bad_payload` | `bridge.bad_payload` | `Log.error` | `handle()` decode failure | none |
| `bridge.invalid_intent` | `bridge.invalid_intent` | `Log.error` | `handle()` validate failure | `intent_id` (clipped) |
| `bridge.intent_throttled` | `bridge.intent_throttled` | `Log.info` | `handle()` 429 | `intent_id`, `hostname` (clipped) |

Not throttled: `bridge.intent_received`, `bridge.listening`, `bridge.port_in_use`, `bridge.listener_failed`, `bridge.start_failed`, `bridge.bad_port`. HTTP status codes and `respond()` are untouched — throttling affects only whether a line is *written*, never what the client receives. The token is never in any field or key (the 401 line still logs only `reason`, and its key is `"bridge.unauthorized/" + reason` where `reason` is one of two constant words); the body is never in any field. The brief's "per event key" is kept for four events and consciously refined for `bridge.unauthorized`; the reason is stated in the header comment (§6) so nobody "simplifies" it back.

Header comment of `BridgeServer` gains a paragraph (see §6) and the `read()` comment above the header-cap check does not change.

### Item 7 — Wording (`BridgeServer.swift` comments)

Exact replacement text in §6. Summary of the three corrections: (1) "before the body is even decoded", not "before the body is buffered" — framing (431/400/413) still reads the body per `Content-Length` before `gate()` runs; (2) a web page *can* send a simple (no-preflight) POST that reaches `handle()`; it is answered `401` and the page cannot read the response (no CORS headers), it cannot attach `Authorization` (non-safelisted header → preflight the bridge never satisfies), and it never sees the token; (5) `tokenMatches` is constant-time *at the source level* — no data-dependent early exit in the loop — with no guarantee about what the optimizer emits.

### Item 8 — CI: pin Xcode

`.github/workflows/ci.yml`, `mac-app` job only; the extension job is untouched.

```yaml
  mac-app:
    name: macOS app (build + test)
    runs-on: macos-15
    env:
      # Pin the toolchain instead of trusting the image default (review 2026-09).
      # The image default is not a contract: macos-14 resolved to a toolchain
      # without the Swift Testing module and this job only went green once it
      # moved to macos-15 (commit fff0f1a). Xcode 16.4 = Swift 6.1.2, the version
      # run 34940554506 passed on. If the image ever drops this Xcode, the
      # "Swift version" step below fails immediately with a missing DEVELOPER_DIR
      # instead of a confusing test-time error.
      DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer
    steps:
      - uses: actions/checkout@v4
      - name: Swift version
        # A real assertion: the first line prints the toolchain for the log, the
        # second fails the job unless it is Swift 6.1.2. Anything else means the
        # pin above no longer matches the runner image — fix the pin, don't unpin.
        run: |
          swift --version
          swift --version 2>&1 | grep -q 'Swift version 6\.1\.2'
      - name: Build
        run: swift build --package-path mac-app
      - name: Test
        run: swift test --package-path mac-app
```

Update the file's header comment line 3 to `(macos-15 + DEVELOPER_DIR pinned to Xcode 16.4 — Swift 6.1.2, needed for the Swift Testing module)`. No `actions/*` version changes, no third-party actions, no `xcode-select`.

---

## 3. Edge cases (expected behaviour)

1. **Failing `get` on `saLogs` inside `saLog`** (storage torn down mid-call). Console line printed once; the async IIFE rejects at the `get`; `.catch` swallows; ring unchanged; no second console line; no `set`; no unhandled rejection; the *next* `saLog` call behaves normally if storage is back.
2. **Failing `set` on `saLogs` inside `saLog`.** Same as 1: console printed once, ring unchanged, nothing else. (This is the reviewer's `FOLLOWUP-LOG` fixture case.)
3. **Failing token read via the real `onMessage` listener.** `forward()` catches, returns without logging, setting, fetching or arming a timer; the listener's `.catch` is a no-op backstop; zero unhandled rejections; `h.timers.length === 0`, `h.fetches.length === 0`, `h.writes.length === 0`, `h.logs().length === 0`, `h.console.length === 0`.
4. **`main()` boot read failing** (`get({ saMode })` rejects at injection). Click listener is already attached (synchronous, before the `await`); no load timer; nothing logged; `void main().catch` swallows; a later trusted click on a watched host still emits (policy is re-read per event).
5. **Extra key on the runtime message** (`{ …intent, extraPrivateField: "x" }`). Fetch body parses to exactly `{id,type,trigger,hostname,ts}` with the five values; `extraPrivateField` absent; `payload.id`/`hostname` still used for the `bridge.forwarded` log.
6. **Paused host with a distinctive name must appear nowhere.** Hostname `zq-private-shop-7731.test`, everywhere + blocklisted (and the listed + not-in-list variant): trusted click and fired load timer → `messages.length === 0`, `writes.length === 0`, `logs().length === 0`, `console.length === 0`, `JSON.stringify(handle.store)` and `JSON.stringify(handle.console)` do not contain the hostname; piping the (empty) `messages` into a background handle yields `fetches.length === 0`.
7. **20,009-byte padded hostname** (`" " × 20 000 + "shop.test"`). `validate()` → `"bad hostname"` (raw > 253) → `400`, `bridge.invalid_intent` with clipped `intent_id`; nothing reaches `onIntent`, `CatchRunner` or `catch.skipped_off_duty`. Called directly, `CatchRunner.run` / `skipOffDuty` with that hostname log a `msg` of exactly 259 UTF-8 bytes ending in `…`.
8. **Exactly 253 bytes raw** (`"a" × 253`, or `" " + "a" × 252`). Passes; `onIntent` receives the raw value.
9. **254 bytes raw made of 253 + one padding space** (`"  " + "a" × 253 + "  "` = 257, and `" " + "a" × 253` = 254). Rejected (`"bad hostname"`). This flips `BridgeHardeningTests.hostnameAtBoundPasses` line 54 — intentional. Whitespace-only `" " × 253` → raw passes, trimmed empty → `"bad hostname"`. Combining-mark bomb → rejected as before.
10. **Suppression window boundary at t = 1.000 s.** Emit at `t0`; calls at `t0 + 0.2`, `t0 + 0.999` dropped; call at exactly `t0 + 1.0` emitted with `suppressed: "2"`, `suppressed_since: iso(t0 + 0.2)`; the window reopens at `t0 + 1.0` (not at `t0 + 2.0`).
11. **Two different keys in the same window.** `bridge.unauthorized/missing` at `t0` and `bridge.bad_payload` at `t0 + 0.1` are both emitted; each key drops independently; neither reports the other's count.
12. **Window reopening emits the suppressed count, once.** `t0` emit · `t0+0.5` drop · `t0+1` emit `suppressed:"1"`, `suppressed_since: iso(t0+0.5)` · `t0+1.5`, `t0+1.7` drop · `t0+2` emit `suppressed:"2"`, `suppressed_since: iso(t0+1.5)` · `t0+3` emit with **neither** field.
13. **Token never logged.** The 401 line's fields are exactly `{reason}` or `{reason, suppressed, suppressed_since}`; `bearer` is never interpolated; the throttle receives only the event name plus the public reason word (`missing` / `mismatch`), never the presented token. `bridge.unpaired` / `bridge.unauthorized` on the extension side log `intent_id`/`status` only (unchanged).
14. **Wall clock jumps backwards** between rejections. The next line is emitted (with any pending count and its `suppressed_since`) and the window reopens at the new time; no multi-hour mute.
15. **`bridge.bad_request` is one key for three causes.** A 431 flood followed within the same second by a 413 hides the 413 line (its count shows on the next emitted `bridge.bad_request`). Accepted: the status code still goes to the client; the key is the event, as the brief specifies — the per-reason refinement is reserved for `bridge.unauthorized` (edge 24), where hiding a line has a security cost.
16. **Options after save, then "Simulate intent".** Save → `Token saved — waiting…`; popup's simulate → SW writes `bridgeOk:true` → the Options `storage.onChanged` listener re-renders `Paired — token ends in …XXXX` live. Wrong token → `401` → `bridgeWhy:"unauthorized"` → Options shows `Token rejected — …` live. Unpair (empty save) → `Not paired — …`.
17. **`saLogs` corrupted to a non-array** (a string in storage). `saLog` replaces it with `[entry]` instead of throwing inside the chain and wedging the ring forever.
18. **Runtime message missing a key** (old sender without `id`). `wire` has four keys (`JSON.stringify` omits `undefined`); the app's `validate()` tolerates a nil `id` (Round 1 §3a). Never more than five keys.
19. **Extension context invalidated while `saLog` is mid-chain.** Console line already printed; `get`/`set` reject or throw inside the async function; swallowed; no page-console error, no retry, no re-log.
20. **Regenerate in the app while Options is open.** Next intent → 401 → `bridgeWhy:"unauthorized"` → Options flips from `Paired` to `Token rejected — copy it again from PAIR SENSOR (…XXXX)` without reload; pasting the new token resets to `Token saved — waiting…` (one-write reset unchanged).
21. **`forward()` called directly (not via the listener) with a failing token read.** Resolves; `await h.ctx.forward(intent())` in a test must not need a `.catch` — that is the contract (b) guarantees.
22. **CI image without `Xcode_16.4.app`.** The "Swift version" step fails first — `xcrun` reports the missing DEVELOPER_DIR, or the `grep` finds no `Swift version 6.1.2` — nothing builds; the fix is to update the pin (and the grep) deliberately, never to remove them.
23. **Burst, then hours of silence.** 500 `bridge.unauthorized/missing` in one second at `t0`, nothing until `t0 + 7200`. The line at `t0 + 7200` carries `suppressed: "499"` and `suppressed_since: iso(t0 + ε)` (the first dropped call), so the reader places the burst at `[suppressed_since, ts]` instead of misattributing 499 drops to the quiet hours. Nothing is emitted *during* the silence — the throttle has no timer, and the count is only delivered by the next line for that key.
24. **Token-guessing probe inside a no-token flood.** `missing` at `t0` (emitted), `missing` × 50 through `t0 + 0.9` (dropped), `mismatch` at `t0 + 0.5` → **emitted** (`reason: "mismatch"`, no `suppressed`) because its key is `bridge.unauthorized/mismatch`; a second `mismatch` at `t0 + 0.7` is dropped and reported by the next `mismatch` line. The event name on both lines is `bridge.unauthorized`.
25. **Mid-paste when the bridge status flips.** `token-input.value === "partial"`, then a service-worker write of `bridgeOk: true` fires the Options `storage.onChanged` listener → `renderToken()` updates `#token-state` and the placeholder; `value` is still `"partial"`. Submitting a valid token afterwards clears it (`saveToken` success path).
26. **App stopped answering after pairing.** `bridgeOk: false, bridgeWhy: "unreachable"` (from `forward()`'s unreachable branch) → Options reads `Token saved — the app isn't answering yet (…XXXX). Is Spending Angel running?`; the popup keeps its `App not reachable ✕` line. A later 200 flips both to paired, live.
27. **Stale `unpaired` after a save (accepted transient).** An intent whose token read predates the save writes `bridgeWhy: "unpaired"` after the save's reset. Options reads `Token saved — waiting…` (correct: the token *is* saved), the popup reads `Not paired ✕` until the next intent. Both self-correct; no code compensates for it.
28. **Two `saLog` calls in one synchronous turn** (nothing shipped does this). Both read the same ring, one line is lost; console has both. Same in real Chrome. Tests that need N lines in the ring `await flush(h)` between calls (`log.test.js`).

---

## 4. Track split and Round 1 consistency

**Track A — `extension/`** (items 1–4): `content.js` (silent suppression, `void main().catch`), `background.js` (`wire`, contained token read, listener `.catch`), `log.js` (async IIFE ring write), `options.js` (`tokenStateText` + five strings, three-key read, storage listener, `renderToken` no longer clears the field — `saveToken` does), `tests/harness.js` (knobs, §5), `tests/content.test.js`, `tests/background.test.js`, `tests/ui.test.js`, **new** `tests/log.test.js`. Untouched: `popup.*`, `options.html`, `sites.js`, `detect.js`, `domains.js`, `manifest.json`, `*.css`, `preview.html`.

**Track B — `mac-app/` + CI** (items 5–8): `BridgeServer.swift` (`maxHostnameLength`, `validate()` order, nested `LogThrottle`, `throttle` init param, `logRejected`, five converted call sites, header + `tokenMatches` comments), `CatchRunner.swift` (`Log.clip` in `run`, new `skipOffDuty`), `AppDelegate.swift` (call `skipOffDuty`), `Tests/SpendingAngelTests/BridgeHardeningTests.swift` (expectation flip + padded cases), `CatchRunnerTests.swift` (bounded hostname), **new** `LogThrottleTests.swift`, `.github/workflows/ci.yml`. Untouched: `Log.swift`, `Store.swift`, `OverlayController.swift`, `DropdownView.swift`, `SpendingAngelApp.swift`, `Package.swift`, every other test file.

Order of work: A: `log.js` → `content.js` → `background.js` → `options.js` → harness knobs → tests. B: `LogThrottle` + tests → `validate()` + tests → `CatchRunner`/`AppDelegate` + tests → call-site conversion → comments → CI. Run the suite after each step. The two tracks are independent; nothing must land together across tracks (unlike Round 1's bearer pairing). Within B, the `validate()` flip and the `hostnameAtBoundPasses` test change land in the same step.

**Round 1 contracts that must hold unchanged after Round 2:**

- Wire payload `{id,type,trigger,hostname,ts}` — item 2 enforces it rather than changing it; `content.test.js` "listed: click on an allowlisted host emits one intent" keeps pinning the five keys at the content side.
- `gate()` order 204 → 405 → 404 → 401 → nil; `respond()`/`responseHead(status:)` bytes; all status codes; `lastAccepted` never moves on 401/400; `bearerToken`/`tokenMatches` bodies (only the comment changes).
- `validate()` problem strings and order type → trigger → id → hostname; `maxIDLength = 128`; `Log.clip` default 256 with the ≤ `max + 3` guarantee; the byte-not-grapheme rule. **Supersedes Round 1 §3a's hostname row ("1…253 UTF-8 bytes after trimming"), the size-caps table entry and the wording of edge case 26:** the 253-byte bound is on the *raw* value; trimming only feeds the non-empty check. `docs/design-spec.md` gets a `(superseded by design-spec-r2 item 5)` note at those three places (§6).
- `CatchRunner.run` signature and `fields` keys; perform → record → log ordering; `catch.performed` / `catch.skipped_busy` names; `msg == hostname` for hostnames ≤ 256 bytes.
- Storage keys and writers/readers table (Round 1 §3c): no key added; `options.js` gains *reads* of `bridgeOk`/`bridgeWhy` (already listed as popup reads) — the table's "read by" column for those two rows gains `options.renderToken`.
- `saveToken` one-write reset; `saNormalizeBridgeToken`; `bridge.unpaired` (no fetch, no timer) path; the four `forward()` response branches; popup states and strings.
- `saLog` entry shape `{ts, level, event, msg, …fields}`, `SA_LOG_MAX = 50`, newest last; `popup.renderEvents` untouched.
- Event-name convention `dotted.snake`; no new event names are introduced in Round 2 (`sensor.suppressed` is retired; `suppressed` / `suppressed_since` are *fields*; `bridge.unauthorized/<reason>` is a throttle *key*, never an emitted event name).

**Fixture-compatibility constraints on Track B (from §5):** `BridgeServer.swift` and `CatchRunner.swift` must keep compiling when concatenated with a stub `enum Log { static func info(_:_:_:); static func error(_:_:_:); static func clip(_:max:) }` and `enum CharacterID: String { case angel }` — so: no `Log.debug`, no `Log.Level`, no `Log.shared`, no new file for the throttle, no new imports beyond `Foundation`/`Network`, and the two-argument `BridgeServer(expectedToken:) { intent in … }` call must still resolve.

---

## 5. Test plan

Commands: extension `node --test extension/tests/*.test.js` (Node 20 in CI, 25 locally — same API subset as Round 1 §6a); native `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app`. Never `xcode-select`.

### 5a. Harness knob changes (`extension/tests/harness.js`)

| Knob | Change | Why |
| --- | --- | --- |
| `failNextGet(err, key)` | Gains an optional `key`, mirroring `failNextSet`: rejects the next **promise-form** `get` that names `key`; without `key` the behaviour is unchanged (next promise-form `get`). `pendingGetError` becomes `{ err, key }`. **Matching rule, by `defaults` form:** object → `key in defaults` (match on the *keys*, never on the default values); string → `defaults === key`; array → `defaults.includes(key)`; `null`/`undefined` (read-everything) → matches any `key`. A non-matching `get` leaves the knob armed. | `log.js` now uses the promise form too, so an unscoped knob could be consumed by the ring read instead of the read under test. Existing unscoped calls keep working; the tests below scope theirs. **Warning:** an unscoped `failNextGet(err)` armed while a `saLog` chain is still pending is consumed by the ring read — unscoped arming is only safe after `await flush(h)`. |
| Promise-form `get` snapshot timing | **Unchanged: eager** (`Promise.resolve(snapshot(defaults))`, snapshot at call time). Considered and rejected: a lazy snapshot (`Promise.resolve().then(() => snapshot(defaults))`) does *not* serialize back-to-back `saLog` calls — the write in the async IIFE lands at least one microtask after the read resolves, so both reads still see the pre-write ring whichever tick the snapshot is taken in. The callback form only serialized because the callback read *and wrote* inside one microtask. The harness therefore mirrors Chrome (edge case 28) and the tests flush between calls. | Keeps `deferred-repros.cjs` semantics identical to Round 1 and avoids a harness behaviour that would only exist in tests. |
| `loadContentScript({ failFirstGet })` | New loader option: `{ err, key }` (or just `err`) armed **before** the scripts are evaluated, so `main()`'s boot read is the one that fails. | Edge case 4 — the handle does not exist before the loader runs, so a test cannot arm it in time otherwise. |
| `handle.console` | Already collected; add `handle.consoleText = () => JSON.stringify(handle.console)` convenience. | Edge case 6 asserts the hostname is absent from console output. |
| Callback-form `get` | Kept (mirrors Chrome) but now unused by shipped code; the comment in `makeStorage` says so. | Fidelity; a future callback-form caller still works. |
| `handle.fetches` / `handle.timers` / `handle.clears` | Unchanged. | — |

No other mocked surface changes. The harness still evaluates the real files.

### 5b. Extension tests

**`tests/content.test.js`** — existing tests that change (all because `sensor.suppressed` no longer exists; the proof of suppression becomes the *absence* of a message, a write and a log line):

| Test (existing name) | Change |
| --- | --- |
| `listed: host not in the allowlist is suppressed` | Replace the two `lastLog()` assertions with `h.logs().length === 0` and `h.console.length === 0`. |
| `everywhere: site paused after injection is suppressed without navigation` | Same replacement; keep `countEvent(h,"sensor.intent") === 0`. |
| `listed: 'Stop watching' then 'Watch this site' toggles without navigation` | Line 109 → `countEvent(h, "sensor.suppressed") === 0` and `countEvent(h, "sensor.intent") === 1` (unchanged since the first click). |
| `mode flip everywhere→listed is honoured in an already-injected tab` | Line 129 → same as above. |
| `listed: host removed from the list suppresses the queued load AND later clicks` | `countEvent(h,"sensor.suppressed") === 2` → `h.logs().length === 0`. |
| `everywhere: load on a known shop paused during the 800 ms is suppressed at fire time` | Lines 190–191 → `h.logs().length === 0` and `!h.consoleText().includes("amazon.com")`. |
| `a suppressed event still consumes the cooldown (stamp happens before policy)` | Line 234 → `h.messages.length === 0 && h.logs().length === 0`; the second assertion (still 0 after the in-cooldown click) is unchanged. |
| `does not throw when chrome.storage rejects (context invalidated)` | `failNextGet(err)` → `failNextGet(err, "saMode")` (scoped; behaviour identical). |
| `the sensor keeps working after a transient storage failure` | Same scoping. |

New tests:

- `paused host leaves no trace anywhere (R-01)` — hostname `zq-private-shop-7731.test`, config everywhere + blocklisted; `await tick()`; `fireTimers()` (no timer expected in everywhere mode for an unknown domain — assert `timers.length === 0` first); trusted click; `flush`; assert `messages.length === 0`, `writes.length === 0`, `logs().length === 0`, `console.length === 0`, `!JSON.stringify(h.store).includes(HOSTNAME)`, `!h.consoleText().includes(HOSTNAME)`. Repeat for listed mode with `saAllowlist: ["other.test"]` where the 800 ms timer *is* scheduled and fired.
- `paused host never reaches the bridge end to end (R-01)` — same content handle plus `loadBackground({ config: { saBridgeToken: TOKEN } })`; `for (const m of c.messages) b.message(m)`; `flush(b)`; `b.fetches.length === 0`, `b.logs().length === 0`.
- `boot read failure is contained (R-02c)` — `loadContentScript({ config: LISTED, failFirstGet: { err: new Error("Extension context invalidated."), key: "saMode" } })`; `flush`; `unhandled.length === 0`; `listeners.click.length === 1`; `timers.length === 0`; `logs().length === 0`; then `setConfig(LISTED)`, trusted click → `messages.length === 1`.

**`tests/background.test.js`** — existing tests that change:

| Test | Change |
| --- | --- |
| `a storage failure while reading the token fetches nothing and arms no timer` | Drive the real listener: `h.failNextGet(err, "saBridgeToken"); h.message(intent()); await flush(h)`; drop the test-side `.catch` (forbidden by the brief); add `unhandled.length === 0`, `h.logs().length === 0`, `h.console.length === 0`, `h.writes.length === 0`. Add a second half: `await h.ctx.forward(intent())` after re-arming — must resolve without a `.catch`. |
| `a rejecting reconcile logs sites.sync_failed and does not wedge the tail` | Step 2 `failNextGet(err)` → `failNextGet(err, "saMode")` (scoped; reconcile reads `DEFAULTS` which contains `saMode`). |
| `forward with a token sends Authorization: Bearer` | Keep `assert.deepEqual(JSON.parse(init.body), msg)`; add `assert.deepEqual(Object.keys(JSON.parse(init.body)), ["id","type","trigger","hostname","ts"])` (order pinned). |

New tests:

- `extra keys on the message never reach the wire (S-03)` — `h.message({ ...intent(), extraPrivateField: "synthetic-only", nested: { a: 1 } })`; body keys sorted deep-equal the five; `"extraPrivateField" in JSON.parse(body) === false`; the `bridge.forwarded` log still carries `intent_id`.
- `a message missing id sends four keys, never five with undefined` — `h.message(intent({ id: undefined }))`; body has no `id` key; fetch still happens.
- `onMessage listener contains a forward() that rejects (R-02b)` — proves the *listener's* `.catch`, not `forward`'s try/catch (which the failNextGet variant above already covers and which would otherwise make this test unable to fail). `forward` is a function declaration evaluated in the vm context, so the listener resolves it by name on the global at call time: `h.ctx.forward = async () => { throw new Error("boom"); }`; invoke `h.listeners.onMessage[0](intent(), {id:"sender"}, () => {})` directly; `await flush(h)`; `unhandled.length === 0`, `h.fetches.length === 0`. Dropping the listener's `.catch(() => {})` must turn this test red.

**`tests/log.test.js` (new)** — loads `loadBackground({ config })` and calls `h.ctx.saLog(...)`:

- `writes a ring entry via the promise form` — one call → `store.saLogs.length === 1`, entry shape `{ts, level, event, msg, ...fields}`, console printed once (`h.console.length === 1`, level `log` for info, `error` for error).
- `ring is capped at SA_LOG_MAX newest-last` — `for (let i = 1; i <= 60; i++) { h.ctx.saLog("info", "t.fill", "call " + i); await flush(h); }` → `store.saLogs.length === 50`, first is call 11, last is call 60. The `await flush(h)` per iteration is load-bearing (edge case 28, §5a): without it the sixty reads all see the empty ring and the ring ends with one entry.
- `back-to-back calls in one tick are not serialized (documented race, edge 28)` — two calls, no flush between, then `flush` → `store.saLogs.length === 1` and `h.console.length === 2`. Pins the harness assumption so the flush in the cap test is not "simplified" away; the comment names it as accepted, not desired.
- `failing get on saLogs is swallowed (edge 1)` — `failNextGet(err, "saLogs")`; `saLog(...)`; `flush`; `unhandled.length === 0`; `store.saLogs` unchanged; `h.console.length === 1` (no second line); no `set` recorded.
- `failing set on saLogs is swallowed (edge 2)` — `failNextSet(err, "saLogs")`; same assertions.
- `does not re-log or recurse on failure` — arm both knobs; assert `h.console.length === 1` and `writes.length === 0` after `flush`.
- `corrupted ring is replaced (edge 17)` — `config: { saLogs: "junk" }` → after one call `Array.isArray(store.saLogs) && length === 1`.
- `missing chrome global does not throw` — `require("../log.js").saLog("info","x","y")` in plain Node (no `chrome`) → returns `undefined`, no throw, `unhandled.length === 0`.

`process.on("unhandledRejection")` guard + `after()` assertion at file level, as in the other two files.

**`tests/ui.test.js`** — existing tests that change:

| Test | Change |
| --- | --- |
| `renderToken masks a stored token and shows only its tail` | Config has only `saBridgeToken` → expect `TOKEN_STATE_SAVED(TAIL)` (i.e. text starts with `Token saved — waiting for the app to confirm (…${TAIL})`); placeholder/value assertions unchanged. |
| `saveToken with a valid token writes token + bridge reset in ONE set` | Final state expectation → `Token saved — …` (the reset nulls `bridgeOk`). The existing `value === ""` ("field cleared after save") assertion is unchanged — it now proves `saveToken`'s reset, since `renderToken` no longer clears. |
| the existing empty-save (unpair) test | Add `h.el("token-input").value = "   "` before the call and assert `value === ""` after — the unpair path clears too. |

All expected strings are **hardcoded** in `ui.test.js` (the `const TOKEN_STATE_*` bindings are not reachable through `h.ctx`, item 4); `tokenStateText` is called as `h.ctx.tokenStateText(...)`.

New tests:

- `renderToken says Paired only when bridgeOk is true` — config `{ saBridgeToken: TOKEN, bridgeOk: true }` → `Paired — token ends in …${TAIL}`; `{ bridgeOk: false, bridgeWhy: "unpaired" }` → `Token saved — waiting…`; `{ bridgeOk: null }` → `Token saved — waiting…`.
- `renderToken shows the rejected state for an unauthorized bridge` — `{ saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unauthorized" }` → `Token rejected — copy it again from PAIR SENSOR (…${TAIL})`.
- `renderToken says the app isn't answering for an unreachable bridge (edge 26)` — `{ saBridgeToken: TOKEN, bridgeOk: false, bridgeWhy: "unreachable" }` → exactly `Token saved — the app isn't answering yet (…${TAIL}). Is Spending Angel running?`; `assert.match(text, /^Token saved/)` (the fixture regex in §5d).
- `tokenStateText precedence` — pure table: `(true, "unauthorized")`, `(true, "unreachable")` → Paired; `(false, "unauthorized")` → Rejected; `(false, "unreachable")`, `(null, "unreachable")` → Unreachable; `(false, "unpaired")`, `(null, null)`, `(undefined, undefined)`, `(false, "something-new")` → Saved.
- `renderToken never touches the token field's value (edge 25)` — `domReady()`; `h.el("token-input").value = "partial"`; `setConfig({ bridgeOk: true }); storageChanged({ bridgeOk: { newValue: true } })`; two ticks → `#token-state` is Paired **and** `h.el("token-input").value === "partial"`; a direct `await h.ctx.renderToken()` also leaves it; then `await h.ctx.saveToken(TOKEN)` → `value === ""`.
- `storage.onChanged on bridgeOk re-renders the pairing line live (edge 16)` — `domReady()`; state Saved; `setConfig({ bridgeOk: true }); storageChanged({ bridgeOk: { newValue: true } })`; two ticks → Paired; then `setConfig({ bridgeOk:false, bridgeWhy:"unauthorized" }); storageChanged({ bridgeWhy: {...} })` → Rejected; a change in area `"sync"` is ignored; a change to an unrelated key (`saMode`) does not call `renderToken` (assert by counting `get` calls or by leaving a sentinel in `textContent`).
- `every pairing string keeps the pixel-game voice` — light lint over the five rendered strings (drive `renderToken` through the five stored states and read `#token-state`): none contains "error", "failed" or "exception"; each ends with a period, a question mark, a parenthesis or the tail (guards against a future rewrite into system-ese). Optional; drop if it reads as noise.

Popup tests are unchanged.

### 5c. Native tests

**`BridgeHardeningTests.swift`** — change:

- `hostnameAtBoundPasses`: line 54 (`"  " + 253×"a" + "  "` → `nil`) is **removed from this test** — a test named "…Passes" must contain only passing inputs. The input moves to `paddedHostnameIsRejectedRaw` below with the flipped expectation (intentional, R-03). Keep `253×"a"` → `nil` and `"a"` → `nil`; add `" " + 252×"a"` → `nil` (raw 253). Update the `// MARK:` above it to `hostname bound (raw ≤ 253 UTF-8 bytes; trimmed non-empty)`.
- `maxIDLengthIsPinned`: add `#expect(BridgeServer.maxHostnameLength == 253)`.

Add (same file, `// MARK: hostname bound is on the RAW value (R-03)`):

- `paddedHostnameIsRejectedRaw` — `" " × 20_000 + "shop.test"` (20 009 bytes) → `"bad hostname"`; `" " + 253×"a"` (254) → `"bad hostname"`; `"  " + 253×"a" + "  "` (257 — the former `hostnameAtBoundPasses` line 54, expectation flipped on purpose) → `"bad hostname"`; `"\t" + 253×"a"` → `"bad hostname"` (any padding counts).
- `whitespaceOnlyHostnameStillRejectedAfterTrim` — `" " × 253` → `"bad hostname"` (raw passes, trimmed empty); `" " × 254` → `"bad hostname"` (raw fails) — both produce the same string, pinned so nobody "improves" one of them.
- `hostnameOrderRawThenTrimmed` — `makeIntent(hostname: " " × 300, id: 200×"a")` → `"bad id"` (id still precedes hostname).

**`CatchRunnerTests.swift`** — add:

- `hostnameIsBoundedEvenWhenValidateWasBypassed` — `hostname: " " × 20_000 + "shop.test"`, `perform: true` → captured `msg.utf8.count == 259`, `hasSuffix("…")`; same with `perform: false` (`catch.skipped_busy`).
- `shortHostnamePassesThroughUnchanged` — `"amazon.com"` → `msg == "amazon.com"` (already covered by `admittedCatchRecordsAfterPerform`; keep as a named guard).
- `skipOffDutyLogsBoundedHostname` — `CatchRunner.skipOffDuty(hostname: 20_009-byte, intentID: "abc", log: capture)` → one event `catch.skipped_off_duty`, `msg.utf8.count == 259`, `fields == ["intent_id": "abc"]`; `intentID: nil` → `["intent_id": ""]`.

**`LogThrottleTests.swift` (new, 9th suite).** Fake clock: `var t = Date(timeIntervalSince1970: 1_700_000_000); let th = BridgeServer.LogThrottle(now: { t })`; offsets are whole/half seconds except the two boundary probes. No `Log` writes anywhere in the file.

- `firstLineIsEmittedWithoutSuppressed` — `admit("bridge.unauthorized") == [:]`.
- `linesInsideTheWindowAreDropped` — `t += 0.2` → `nil`; `t = base + 0.999` → `nil`.
- `boundaryAtExactlyOneSecondEmits` (edge 10) — after two drops, `t = base + 1.0` → `["suppressed": "2"]`.
- `windowReopensAtTheEmittedLine` — continuing: `t = base + 1.5` → `nil`; `t = base + 2.0` → `["suppressed": "1"]`.
- `noSuppressedFieldWhenNothingWasDropped` — emit at `base`, emit at `base + 1` → `[:]`.
- `suppressedCountResetsAfterReport` (edge 12) — the full sequence from §3 item 12.
- `keysAreIndependent` (edge 11) — two keys interleaved as in §3 item 11.
- `clockGoingBackwardsReopens` (edge 14) — emit at `base`; drop at `base + 0.5`; `t = base − 5` → `["suppressed": "1", "suppressed_since": iso(base + 0.5)]`; `t = base − 4.5` → `nil`.
- `customWindow` — `LogThrottle(window: 8, now:)`: `base + 7.9` → `nil`; `base + 8` → emit.
- `suppressedSinceIsTheFirstDroppedLine` — emit at `base`; drops at `base + 0.2`, `base + 0.5`; `base + 1` → `["suppressed": "2", "suppressed_since": iso(base + 0.2)]`. Here and below `iso(d)` means `ISO8601DateFormatter().string(from: d)` computed in the test — compare against that, not a literal, because the default options drop fractional seconds (`base + 0.2` renders as `2023-11-14T22:13:20Z`).
- `burstThenSilenceReportsWhenTheDropsHappened` (edge 23) — emit at `base`; 499 drops at `base + 0.001…0.499`; `t = base + 7200` → `["suppressed": "499", "suppressed_since": iso(base + 0.001)]`; `t = base + 7200.5` → `nil` (window reopened at the reporting line, not at the burst).
- `unauthorizedReasonKeysAreIndependent` (edge 24) — `admit("bridge.unauthorized/missing")` at `base` → `[:]`; `base + 0.1` → `nil`; `admit("bridge.unauthorized/mismatch")` at `base + 0.5` → `[:]` (emitted inside the missing flood's window); `base + 0.7` mismatch → `nil`; `base + 1` missing → `["suppressed": "1", …]` (only its own drop). The test uses the exact key strings `logRejected` builds (`"bridge.unauthorized/" + reason`) so a drift at the 401 call site is caught by grep if not by compile.
- `resultKeysAreSuppressedPair` — for every emitted result, keys are either `[]` or exactly `{"suppressed", "suppressed_since"}` (never one without the other); `suppressed` parses as `Int > 0`; `suppressed_since` parses back through `ISO8601DateFormatter()`.
- `defaultWindowIsOneSecond` — `BridgeServer.LogThrottle.defaultWindow == 1`.

No `BridgeServer`-level test for the wiring (`handle()`/`read()` are private and need `NWConnection`); the wiring is covered by the manual checklist below and by reading `logRejected`'s five call sites.

**Manual checklist addition (PR description):** with the app running and no token in curl, `for i in $(seq 20); do curl -s -o /dev/null -X POST http://127.0.0.1:17865/intent; done; sleep 1.2; curl -s -o /dev/null -X POST http://127.0.0.1:17865/intent` → the day's JSONL shows one `bridge.unauthorized` line (`reason: "missing"`), then one more with `"suppressed":"19"` and a `"suppressed_since"` inside the first second; every request still received `401` (`curl -si … | head -1`). Then, within one second of a fresh no-token burst, one request with `-H 'Authorization: Bearer 0000…0000'` (64 zeros) → a `reason: "mismatch"` line appears immediately, not suppressed.

### 5d. Reviewer fixtures in the final gate

Directory: `<scratch>/pr1review/evidence/` (`repository/` is a symlink to this checkout; run the Node fixtures from that directory so `./repository/extension/tests/harness` resolves).

1. **`deferred-repros.cjs`** — asserts the *old* behaviour. Gate: `node deferred-repros.cjs`; expected exit code 1 with an `AssertionError` from **line 11** (the Q-02 `sensor.suppressed` lookup) — the first assertion. Because it stops there, its S-03 / S-02 / FOLLOWUP-LOG claims are not exercised by the fixture; our suite carries those as `extra keys on the message never reach the wire (S-03)`, `a storage failure while reading the token fetches nothing and arms no timer` + `onMessage listener contains a forward() that rejects (R-02b)`, and `log.test.js` `failing set on saLogs is swallowed`. Its unscoped `failNextGet(err)` / `failNextSet(err, 'saLogs')` calls still work with the extended knobs. `deferred-repro-results.json` is *not* rewritten on failure (the write is after the assertions) — the gate must check the exit code / stderr, not the JSON.
2. **`browser-bridge-check.cjs`** — the gate runs a **copy** with two edits, not one: (i) line 60 inverted per the brief: capture `const cut = new Date().toISOString()` immediately before the unlisting `chrome.storage.local.set({saAllowlist:[]})` (line 57), then assert `!after.saLogs.some(l => l.event === 'sensor.suppressed')` and `!after.saLogs.filter(l => l.ts >= cut).some(l => JSON.stringify(l).includes('127.0.0.1'))` and name the step "Unlisted page leaves no hostname in saLogs"; (ii) line 49's `assert.match(…, /^Paired/)` must become `/^Token saved/` — after item 4 the Options page no longer says "Paired" on save (it says so only after a 200, which in the fixture happens later, at the load-forward step). Expect all nine steps to pass. Compatibility notes: the fixture concatenates the current `BridgeServer.swift` with a stub `Log` (`info`/`error`/`clip` only) and calls `BridgeServer(expectedToken:) { intent in … }` — hence the §4 constraints. Its two back-to-back unauthorized requests (lines 29–30) now print a single `bridge.unauthorized` to `native-wire-events.log` if both carry the same `reason` (two no-token or two wrong-token requests — the second is suppressed), or two lines if one is `missing` and the other `mismatch` (separate keys, item 6); nothing asserts on that count.
3. **`hostname-log-repro.swift`** — a *frozen copy* of the old `BridgeServer.swift` + `CatchRunner.swift` with a stub tail (lines 348–361). Running it unchanged proves nothing about the branch. Gate: regenerate it as `cat mac-app/Sources/SpendingAngel/BridgeServer.swift mac-app/Sources/SpendingAngel/CatchRunner.swift > repro.swift`, append the stub tail with line 356 changed to `precondition(BridgeServer.validate(intent) == "bad hostname")` and line 359 to `precondition(loggedBytes == 259)` (the `CatchRunner.run` call at 358 stays as written — it bypasses `validate()` and must now log a clipped name), compile with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc repro.swift -o repro`, run; expect exit 0 and the two printed lines. A compile error here means Track B broke the stub compatibility rule in §4.

---

## 6. Docs and wording deltas

**`BridgeServer.swift` header comment** — replace the "Paired (audit 2026-09, NATIVE-01)" paragraph with:

```
/// Paired (audit 2026-09, NATIVE-01): the sensor proves it is *our* sensor by
/// sending `Authorization: Bearer <token>`, where the token is the 64-hex value
/// the app generated and shows under PAIR SENSOR in the dropdown. The request
/// is still framed first (header cap, Content-Length, body cap — 431/400/413),
/// but nothing from the body is decoded or logged until the token has matched:
/// a wrong or missing token gets `401` before decode. A web page *can* reach
/// this port with a simple POST (no preflight), but it gets `401`, cannot read
/// the answer (no CORS headers on any response), cannot attach `Authorization`
/// (a non-safelisted header forces a preflight this server never satisfies),
/// and never saw the token in the first place. The expected token is read per
/// request (injected closure) so a regeneration in the dropdown takes effect
/// immediately.
///
/// Rejection lines (401 / 400 / 413 / 431 / 429) are rate-limited per key —
/// one line per second, with `suppressed: "<n>"` + `suppressed_since: "<ts>"`
/// on the first line after a busy window (review 2026-09, S-04) — so a local
/// loop cannot grow the day's log by one line per connection. The key is the
/// event name, except `bridge.unauthorized`, which is keyed per reason so a
/// wrong-token probe is never hidden behind a no-token flood. Status codes are
/// never throttled.
```

The "Evaluation order" paragraph is unchanged.

**`tokenMatches` doc comment** — replace with:

```
    /// Constant-time comparison at the source level: false when `presented` is
    /// nil, when `expected` is empty (never accept an unset token), or when the
    /// lengths differ (token length is public); otherwise ORs the XOR of every
    /// byte pair with no data-dependent early exit in the loop and returns
    /// diff == 0. This is a property of the source, not a guarantee about the
    /// machine code — the optimizer's timing behaviour is not controlled here.
```

**`validate` doc comment** — append: "The hostname bound applies to the raw value *before* trimming, so padding cannot smuggle an oversized name past the check."

**`CatchRunner.swift` header** — append the sentence from item 5; document `skipOffDuty` as in §2.

**`content.js` / `background.js` / `log.js` / `options.js` headers** — the one-sentence additions named in items 1–4; `log.js` header line "Events go to the console AND a small ring buffer…" gains "; the ring write never surfaces a storage failure (it would recurse), and two calls in one synchronous turn may lose a line (accepted; nothing shipped does it)". `options.js` header "Pairing:" sentence gains: "The status line is re-rendered live from storage; the input field is only ever cleared by a successful save."

**`.github/workflows/ci.yml`** — header comment and the two inline comments from item 8.

**Root `README.md`** — step 3 of "Install (dev)" currently ends `The options page should now read "Paired — token ends in …XXXX".` → change to: `The options page now reads "Token saved — waiting for the app to confirm (…XXXX)". Step 4 turns that into "Paired".` Step 4 (Verify) gains: `…and the options page (if open) flips to "Paired — token ends in …XXXX". If it says "the app isn't answering yet", the app is not running — start it and simulate again.` No other README change is required by the pairing wording.

**`mac-app/README.md`** — in the "Logs" paragraph, append one sentence: `Rejection events (`bridge.unauthorized`, `bridge.bad_request`, `bridge.bad_payload`, `bridge.invalid_intent`, `bridge.intent_throttled`) are written at most once per second per event (per reason for `bridge.unauthorized`); the next line after a burst carries `suppressed: "<n>"` with the number dropped and `suppressed_since` with the time of the first drop.` The status table, caps and pairing flow are unchanged.

**`docs/design-spec.md`** (Round 1 spec, same PR) — three one-line notes, no other edits: after the §3a schema row `"hostname": "1..253 UTF-8 bytes after trimming spaces"`, after the size-caps table's `hostname` length row, and at the end of edge case 26, append `(superseded by design-spec-r2 item 5: the 253-byte bound is on the raw value; trimming only feeds the non-empty check)`.

**`docs/review-report.md`** — item 9 (owner/orchestrator): append `## Round 2 (2026-09-15)` from the Round 2 review output, listing the nine items with their outcome and the new test counts; note the `sensor.suppressed` retirement and the `hostnameAtBoundPasses` expectation flip as intentional contract changes.

**PR #1 description** — checklist gains: R-01 silent suppression · S-03 wire allowlist · R-02 containment (log.js / forward / main) · Options "Token saved" / "isn't answering" wording, field value preserved on live re-render · R-03 raw hostname bound (supersedes Round 1 §3a wording) · S-04 log throttle (`suppressed` + `suppressed_since`, per-reason key for 401) · comment corrections · Xcode 16.4 pin with a `grep` assertion; plus the manual checklist lines from §5c.
