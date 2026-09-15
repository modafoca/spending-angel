# Spending Angel — Review Report (branch `fix/audit-2026-09`, 2026-09-14)

Inputs: the validated brief (`docs/audit-validation.md`), the design spec (`docs/design-spec.md`), and the two lens reviews (security, quality) run against the working tree. Finding ids below are prefixed **S-** (security lens) and **Q-** (quality lens) because the two lenses both numbered from R-01; the original id is kept in each subsection.

Rules applied: only findings marked `safe_to_auto_apply=true` with severity *minor* were applied, plus one *medium* whose fix is a trivial, clearly correct one-liner per call site (Q-01 — called out explicitly). Nothing behaviour-changing was applied. No commits were made (orchestrator commits). `sounds/`, `extension/preview.html`, `*.ai`, and the root PRM/mission markdown were not touched.

## Summary

| | |
| --- | --- |
| Findings received | 21 (security 7, quality 14) — no high; 3 medium (S-01 process, Q-01, Q-02); 18 minor |
| Applied | 12 — S-06, Q-01, Q-03, Q-04, Q-05, Q-06, Q-07, Q-08, Q-09, Q-10, Q-13, Q-14 |
| Deferred | 9 — S-01, S-02, S-03, S-04, S-05, S-07, Q-02, Q-11, Q-12 |
| Rejected | 0 — every finding was re-verified against the source and holds |
| Extension suite | `node --test extension/tests/*.test.js` — **103 pass, 0 fail** (was 100; +3 new tests) |
| Native suite | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app` — **107 tests / 8 suites pass** (was 103; −1 redundant case, −2 compile-time-only/duplicate cases, +7 new) |
| Regression check | With the Q-01 `.catch` calls stripped in a scratch copy, the 3 new tests fail (plus 3 knock-on failures from leaked rejections) — the guard is real |

Both reviewers' verdicts stand: the branch implements the spec faithfully and nothing rises to must-fix-before-merge. The applied items are housekeeping and test coverage; the deferred items are defense-in-depth or behaviour-adjacent and need an owner decision.

## Scope reviewed

`git diff main --stat` after the refactors (the `sounds/stop.mp3` line is the pre-existing working-tree change the brief says must NOT be committed):

```
 README.md                                                 | 139 +++++++++++++++++++------------
 extension/background.js                                   |  56 +++++++++++--
 extension/content.js                                      |  81 ++++++++++++-------
 extension/manifest.json                                   |   2 +-
 extension/options.html                                    |  13 ++-
 extension/options.js                                      |  56 ++++++++++++-
 extension/popup.html                                      |   3 +-
 extension/popup.js                                        |  25 +++++-
 extension/sites.js                                        |  16 +++-
 extension/tests/sites.test.js                             |  18 +++++
 mac-app/README.md                                         | 192 ++++++++++++++++++++++++++++++-------------
 mac-app/Sources/SpendingAngel/AppDelegate.swift           |  13 +--
 mac-app/Sources/SpendingAngel/BridgeServer.swift          | 193 +++++++++++++++++++++++++++++++++++---------
 mac-app/Sources/SpendingAngel/DropdownView.swift          |  82 ++++++++++++++++---
 mac-app/Sources/SpendingAngel/Log.swift                   |  17 ++++
 mac-app/Sources/SpendingAngel/OverlayController.swift     |  26 +++++-
 mac-app/Sources/SpendingAngel/SpendingAngelApp.swift      |  10 ++-
 mac-app/Sources/SpendingAngel/Store.swift                 |  80 ++++++++++++++++--
 mac-app/Tests/SpendingAngelTests/BridgeParsingTests.swift |  21 +++--
 sounds/stop.mp3                                           | Bin 798 -> 246841 bytes
 20 files changed, 811 insertions(+), 232 deletions(-)
```

New (untracked) files on the branch, with line counts after the refactors:

```
 477 extension/tests/background.test.js
 389 extension/tests/content.test.js
 395 extension/tests/harness.js
 210 extension/tests/ui.test.js
  33 mac-app/Sources/SpendingAngel/CatchRunner.swift
 296 mac-app/Tests/SpendingAngelTests/BridgeAuthTests.swift
 204 mac-app/Tests/SpendingAngelTests/BridgeHardeningTests.swift
  27 mac-app/Tests/SpendingAngelTests/CatchAdmissionTests.swift
 152 mac-app/Tests/SpendingAngelTests/CatchRunnerTests.swift
 100 mac-app/Tests/SpendingAngelTests/LogClipTests.swift
  82 mac-app/Tests/SpendingAngelTests/StoreRolloverTests.swift
  18 mac-app/Tests/SpendingAngelTests/TestFixtures.swift   (new in this review, Q-09)
```

Also untracked and deliberately excluded from the PR: `extension/preview.html` (pre-existing). `docs/` holds `audit-validation.md`, `design-spec.md`, and this report.

Files edited by this review: `extension/background.js`, `extension/content.js`, `extension/tests/harness.js`, `extension/tests/content.test.js`, `extension/tests/background.test.js`, `mac-app/Sources/SpendingAngel/BridgeServer.swift`, `mac-app/Sources/SpendingAngel/Store.swift`, `mac-app/Sources/SpendingAngel/OverlayController.swift`, `mac-app/Tests/SpendingAngelTests/{BridgeAuthTests,BridgeHardeningTests,BridgeParsingTests,LogClipTests,CatchAdmissionTests,TestFixtures}.swift`.

## Findings table

Line numbers are as reported by the reviewers (pre-refactor); where the applied edit moved code, the subsection says where it lives now.

| id | severity | category | file:line | description | recommendation | status |
| --- | --- | --- | --- | --- | --- | --- |
| S-01 | medium | process | `sounds/stop.mp3:1` | `sounds/stop.mp3` (modified) and `extension/preview.html` (untracked) are in the working tree; a `git add -A` would sweep them into the PR against decision 2 of the brief. | Stage explicitly; verify with `git diff --cached --stat` before committing. | deferred (orchestrator action at commit time) |
| S-02 | minor | robustness | `extension/background.js:128` | `forward()`'s first `await chrome.storage.local.get(...)` is outside any try/catch and the `onMessage` listener calls `forward(msg)` without `.catch`, so a storage rejection is unhandled in the SW. | Wrap the token read (log `bridge.token_read_failed`, return) or `.catch` at the listener; add a listener-level test. | deferred → done in Round 2 (R-02b) |
| S-03 | minor | privacy-defense-in-depth | `extension/background.js:145` | `forward()` serialises the whole received `payload`; the five-key privacy invariant is enforced only by the senders, not at the choke point. | Build the wire body from an explicit allowlist of the five keys; add a test with an extra key. | deferred → done in Round 2 (S-03) |
| S-04 | minor | log-flood | `mac-app/.../BridgeServer.swift:139` | Rejection paths (`bridge.unauthorized`, `bridge.bad_request`) log one line per connection with no rate limit; a local loop grows the day's JSONL unbounded. | Suppression window (≤1 line/s) with a `suppressed` count on the next written line. | deferred → done in Round 2 (S-04 / Q-12) |
| S-05 | minor | state-ordering | `mac-app/.../BridgeServer.swift:164` | `onIntent(intent)` runs synchronously before `respond(200)`; if the overlay work ever exceeds the extension's 4 s abort, a performed-and-counted catch is reported as `bridge.unreachable`. | Respond first, then `DispatchQueue.main.async { onIntent(intent) }`. | deferred |
| S-06 | minor | test-coverage | `mac-app/.../BridgeServer.swift:171` | The response-header contract (no CORS, `Connection: close`, `401 Unauthorized`, `WWW-Authenticate`) was built inline in `respond()` and had no unit test. | Extract `static func responseHead(status:)`; pin it in BridgeAuthTests. | applied |
| S-07 | minor | robustness | `extension/content.js:55` | `chrome.storage.local.set({ lastIntent })` has no `.catch`; `main()`'s storage read has no try/catch. | `.catch(() => {})` on the set; wrap `main()` in the same silent try/catch. | deferred (the `:55` half is applied under Q-01) → `main()` half done in Round 2 (R-02c) |
| Q-01 | medium | robustness | `extension/content.js:55` | Fire-and-forget `chrome.storage.local.set` calls in `sendIntent` (content.js:55) and `forward()` (background.js:134/150/155/159/164) have no `.catch`; a synchronous try/catch does not see a rejected promise. | Append `.catch(() => {})` to each; add a `failNextSet` harness knob and tests. | applied (trivial one-liners, see below) |
| Q-02 | medium | performance | `extension/content.js:39` | `saLog("debug", "sensor.suppressed", …)` is not filtered by log.js, so every suppressed event on a paused/unlisted site does a read-modify-write of the 50-entry `saLogs` ring and evicts the useful events from the popup. | Filter `debug` out of the ring in log.js or hide debug rows in `popup.renderEvents`; adjust content.test.js expectations. | deferred → done in Round 2 (R-01: the log call is removed, `sensor.suppressed` retired) |
| Q-03 | minor | dead-code | `mac-app/.../Store.swift:159` | `var streakDays: Int?` has no caller (DropdownView computes `Store.daysBetween(last, context.date)` directly). | Delete it. | applied |
| Q-04 | minor | stale-comment | `mac-app/.../BridgeServer.swift:35` | `minCatchInterval` comment still says the overlay holds ~4–8 s; clips run up to ~12 s and overlap is handled by CatchRunner. | Reword. | applied |
| Q-05 | minor | stale-comment | `mac-app/.../BridgeServer.swift:6` | Header doc says Native Messaging is the ship path; README and spec say loopback + bearer token is the chosen path. | Align with the README. | applied |
| Q-06 | minor | stale-comment | `mac-app/.../OverlayController.swift:30` | "(also avoids audio/anim races on re-trigger)" sits on the `NSScreen.main` guard but describes the `panel == nil` guard. | Move it up to the panel guard. | applied |
| Q-07 | minor | stale-comment | `extension/background.js:157` | Comment says 429 = "a catch is already on screen"; 429 is the 8 s throttle since the last accepted intent (busy overlay is a 200 + `catch.skipped_busy`). | Reword. | applied |
| Q-08 | minor | duplication | `mac-app/.../BridgeServer.swift:238` | `bearerToken` and `contentLength` hand-roll the same first-match header-line scan. | Extract `static func headerValue(_:named:)`. | applied |
| Q-09 | minor | test-quality | `mac-app/Tests/.../BridgeHardeningTests.swift:13` | `intent(...)` fixture duplicated from BridgeParsingTests; `combiningBomb` duplicates LogClipTests' `bomb`; two hostname cases re-cover `badHostnameRejected`. | Shared `TestFixtures.swift`; drop the redundant cases from one file. | applied |
| Q-10 | minor | test-quality | `mac-app/Tests/.../CatchAdmissionTests.swift:25` | `performCatchSignatureReturnsBoolAndIsDiscardable` never invokes the closure (compile-time check); `idleOverlayWiredThroughCatchRunner…` duplicates `CatchRunnerTests.busyCatchDoesNotRecord`. | Delete both. | applied |
| Q-11 | minor | performance | `extension/background.js:63` | `reconcileContentScripts` awaits `permissions.contains` once per allowlisted host serially (~50 IPC round-trips per reconcile). | `Promise.all` over the hosts, flatten in list order. | deferred |
| Q-12 | minor | performance | `mac-app/.../BridgeServer.swift:139` | Every rejected request writes a structured log line synchronously on the main queue with no coalescing (same root as S-04). | Coalesce repeated `bridge.unauthorized` lines or move serialization onto the utility queue. | deferred → coalescing done in Round 2 (S-04); off-main serialization not done |
| Q-13 | minor | style | `mac-app/.../BridgeServer.swift:273` | `["click", "load", "simulated"].contains(i.trigger)` allocates per validate call. | Hoist to `static let allowedTriggers: Set<String>`. | applied |
| Q-14 | minor | dead-code | `extension/tests/harness.js:383` | `START_CLOCK` is exported but no test imports it (they read `h.clock.now`). | Remove from `module.exports`, keep the internal constant. | applied |

## Findings

### S-01 — pre-existing working-tree changes must not be committed (security R-01, medium, process) — deferred

Verified: `git diff main --stat` still lists `sounds/stop.mp3 | Bin 798 -> 246841 bytes` and `git status` lists `?? extension/preview.html`. Neither was touched by the audit work or by this review. This is not a code change; it is the orchestrator's commit step. Suggested staging (adjust `docs/` to taste):

```
git add README.md extension/*.js extension/*.html extension/manifest.json extension/tests/ \
        mac-app/README.md mac-app/Sources/ mac-app/Tests/ docs/
git diff --cached --stat        # must show neither sounds/ nor extension/preview.html
```

### S-02 — `forward()` token read has no rejection handler (security R-02, minor, robustness) — deferred

Verified in `extension/background.js`: the first statement of `forward()` is `await chrome.storage.local.get({ saBridgeToken: "" })` with no surrounding try/catch, and the `onMessage` listener (line 115) calls `forward(msg)` without `.catch`. The existing test at `background.test.js` ("a storage failure while reading the token…") calls `forward` directly with `.catch(() => {})`, so it would not notice a change in the failure shape. `safe_to_auto_apply=false`; the fix adds a new log event (`bridge.token_read_failed`) and a listener-level test — small, but it is a new code path and a new event name, so it is left for the owner. Auth/privacy contract is unaffected today (nothing is fetched, no timer is armed).

### S-03 — wire payload is not allowlisted at the choke point (security R-03, minor, privacy-defense-in-depth) — deferred

Verified: `body: JSON.stringify(payload)` in `forward()`, and `Intent` on the Swift side is decoded with `JSONDecoder`, which ignores unknown keys. Not a leak today — `content.test.js` pins the five keys and both senders are extension code. The recommended allowlist (`{ id, type, trigger, hostname, ts }`) is a five-line change plus a test, but it changes what a malformed/extra-key message would send, so it is an owner call whether the guard belongs in the SW or stays with the senders.

### S-04 — rejection-path log lines have no rate limit (security R-04, minor, log-flood) — deferred

Verified: `handle()` logs `bridge.unauthorized` per 401 and `read()` logs `bridge.bad_request` per 431/400/413; `lastAccepted` deliberately never moves on those paths. Line *length* is bounded by `Log.clip`; line *count* is not. Attacker model is local-only. The fix (suppression window + `suppressed` count) changes the logging contract the spec mandates (one info event per unauthorized request), so it needs the owner. Same root cause as Q-12.

### S-05 — overlay work runs before the HTTP 200 is queued (security R-05, minor, state-ordering) — deferred

Verified: `onIntent(intent)` on line 164 precedes `respond(conn, status: 200, …)`. The closure does real work (`nextCatchCharacter`, `performCatch` incl. NSPanel/NSHostingView/audio, `recordCatch`, log lines). Normally tens of ms versus the extension's 4 s abort, so a latent mis-report, not a bug. Reordering to respond-then-dispatch changes the observable ordering of side effects (the 200 could arrive before `catch.performed` is logged), so it is deferred even though it is a two-line change.

### S-06 — `responseHead(status:)` extraction + tests (security R-06, minor, test-coverage) — applied

`mac-app/Sources/SpendingAngel/BridgeServer.swift`: the inline `reasons` table was hoisted to `static let reasons: [Int: String]` (so tests can iterate every status), and the header block is now built by `static func responseHead(status: Int) -> String`; `respond()` is reduced to `timeout.cancel()` + `conn.send(content: Data(Self.responseHead(status:).utf8), …)`. Byte-for-byte the same output as before (status line, `Content-Length: 0`, `Connection: close`, the 401-only `WWW-Authenticate: Bearer realm="spending-angel"`, terminating blank line).

`mac-app/Tests/SpendingAngelTests/BridgeAuthTests.swift` gained five tests: `responseHeadStatusLineAndReasons` (every entry in `reasons` produces `HTTP/1.1 <code> <reason>\r\n`), `responseHeadNeverCarriesCORSHeaders` (no `Access-Control` in any status — the regression the reviewer was worried about), `responseHeadClosesEveryConnectionWithEmptyBody` (`Connection: close`, `Content-Length: 0`, ends with `\r\n\r\n`), `responseHeadChallengesOnlyOn401`, and `responseHeadUnknownStatusHasEmptyReason` (an unmapped code degrades to an empty reason rather than crashing).

### S-07 — content.js fire-and-forget `set` and `main()` load path (security R-07, minor, robustness) — deferred (half covered)

The `content.js:55` half is the same one-liner as Q-01 and is applied there (with a test). The other half — wrapping `main()`'s body in a silent try/catch so an invalidated context at load never throws — is `safe_to_auto_apply=false` and is not a one-liner, so it is left for the owner. Impact is console noise in the hostile page's devtools at worst; detection and privacy are unaffected.

### Q-01 — `.catch` on fire-and-forget `chrome.storage.local.set` (quality R-01, medium, robustness) — applied

This is a medium finding applied under the "trivial, clearly correct one-liner" allowance: each fix is `.catch(() => {})` appended to an un-awaited `set(...)`, exactly mirroring the neighbouring `chrome.runtime.sendMessage(payload).catch(() => {})` already on the branch. Six call sites: `extension/content.js` (`lastIntent`) and `extension/background.js` (`bridgeWhy: "unpaired"`, `"unauthorized"`, `"unreachable"`, and the two `bridgeOk: true` writes). `chrome.storage.local.set` returns a Promise in MV3 when called without a callback, and the test harness's `set` already returned `Promise.resolve()`, so no call site can start throwing `TypeError` on `.catch`. A one-line note was added to the `forward()` header comment and to the `sendIntent` block explaining why the `.catch` is there (the surrounding try/catch only sees synchronous throws).

Test support: `extension/tests/harness.js` gained `handle.failNextSet(err, key)` — rejects the next `set()` (or, with `key`, the next one writing that key) without recording it; the `key` form lets a test target the bridge/lastIntent write without tripping log.js's own ring write. Three tests added: `content.test.js` "a rejected lastIntent write is swallowed and does not block delivery"; `background.test.js` "a rejected bridge-status write is swallowed on the unpaired path" and "… after a delivered intent". Both suites already fail the run on any unhandled rejection via `process.on("unhandledRejection")`. Regression check: with the `.catch` calls stripped in a scratch copy, the three new tests fail (`unhandled.length` is non-zero) plus three knock-on failures — confirming they guard the fix.

Not done (still open under S-02 / S-07): the `await chrome.storage.local.get` in `forward()` and in `main()` — those are *awaited* reads, a different shape, and were not marked safe.

### Q-02 — `sensor.suppressed` debug lines fill the popup ring (quality R-02, medium, performance) — deferred

Verified: `extension/log.js` writes every level into the 50-entry `saLogs` ring (no `#if !DEBUG`-style filter like `Log.swift`), and `content.js` logs `sensor.suppressed` at `debug` on every suppressed event (bounded by the 1.5 s cooldown). On a paused site this evicts `sensor.intent` / `bridge.*` from the popup's "Recent events". Both proposed fixes change what the popup shows (ring filter or render filter) and would alter `content.test.js` assertions on `h.lastLog()`, so it is a product decision — the spec asked for the log call, not for its ring behaviour. Recommend the log.js ring filter (console-only for `debug`, matching the native rule) in a follow-up.

### Q-03 — dead `Store.streakDays` (quality R-03, minor, dead-code) — applied

`grep -rn streakDays mac-app/` returned only the definition; `DropdownView.swift:134` computes `Store.daysBetween(last, context.date)` directly so the streak follows the TimelineView date. The property (four lines) was deleted from `mac-app/Sources/SpendingAngel/Store.swift`. `Store.daysBetween` remains the single source.

### Q-04 — stale `minCatchInterval` comment (quality R-04, minor, stale-comment) — applied

`BridgeServer.swift`: now reads "Minimum gap between accepted intents. Clips run up to ~12 s so a catch can outlive this gap — that overlap is handled by the overlay's admission gate (CatchRunner), not here. Anything faster than this is a repeat click or a spammy page, not a new decision." Matches `mac-app/README.md` ("Clips run up to ~12 s") and the NATIVE-03 rationale.

### Q-05 — header doc contradicts README on Native Messaging (quality R-05, minor, stale-comment) — applied

`BridgeServer.swift` header: "(Native Messaging is the ship path; see PRM Q1.)" replaced with "Loopback + bearer token is the chosen path (no Native Messaging host manifest to install)." — the README's wording. The rest of the header (including the NATIVE-01 paragraph) is unchanged.

### Q-06 — misplaced "avoids audio/anim races" comment (quality R-06, minor, stale-comment) — applied

`OverlayController.swift`: the parenthetical was moved off the `NSScreen.main` guard into a two-line comment above `guard panel == nil` ("Already on screen — the caller logs skipped_busy; also avoids audio/anim races on re-trigger."); the `NSScreen` guard keeps only its `Log.error`. Nuance for the record: on `main` the parenthetical was *already* on the `NSScreen` line (`// re-triggers (avoids audio/anim races)`), so this was a pre-existing misplacement rather than one introduced by the branch edit — the fix is still the right one.

### Q-07 — wrong 429 gloss in `forward()` (quality R-07, minor, stale-comment) — applied

`extension/background.js`: "429 = a catch is already on screen" → "429 = within 8 s of the last accepted intent". Verified against `BridgeServer.handle()`: 429 fires when `now - lastAccepted < minCatchInterval`; an intent that lands while a catch is on screen is answered 200 and becomes `catch.skipped_busy` on the app side.

### Q-08 — duplicated header-line scan (quality R-08, minor, duplication) — applied

`BridgeServer.swift`: added `static func headerValue(_ header: String, named name: String) -> String?` — first line whose lower-cased, trimmed name matches, value trimmed of `.whitespaces`, `nil` when absent. `contentLength` and `bearerToken` now call it; both keep first-match-wins. One semantic worth spelling out and now documented on the helper: a line with nothing after the colon (`Authorization:`) splits to one component and is *skipped*, so a later line of the same name can still match — identical to the previous loops (`kv.count == 2`). `method`/`path` were left alone (they read the request line, not a named header). Two tests added to BridgeAuthTests: `headerValueFirstMatchWinsAndIsTrimmed` and `headerValueSkipsEmptyValueLines`. All 31 pre-existing `bearerToken`/`contentLength` assertions still pass unchanged.

### Q-09 — duplicated test fixtures (quality R-09, minor, test-quality) — applied

New `mac-app/Tests/SpendingAngelTests/TestFixtures.swift` with two internal free functions: `makeIntent(type:trigger:hostname:id:)` and `combiningBomb(_:)`. `BridgeHardeningTests`, `BridgeParsingTests` and `LogClipTests` use them; the three private copies are gone (25 + 8 call sites renamed `intent(` → `makeIntent(`, 3 renamed `bomb(` → `combiningBomb(`). Redundancy: `hostnameEmptyAfterTrimIsRejected` was dropped from BridgeHardeningTests because `BridgeParsingTests.badHostnameRejected` covers `""` and `"   "`. `hostnameOverBoundRejected` was **kept** — it pins the exact 253/254-byte boundary, which the parsing test's 300-byte case does not, so it is not actually redundant. Net native count: −1.

### Q-10 — compile-time-only and duplicate admission tests (quality R-10, minor, test-quality) — applied

`CatchAdmissionTests.swift`: deleted `performCatchSignatureReturnsBoolAndIsDiscardable` (assigned a closure and never invoked it; the shape is pinned at compile time by the call sites in `AppDelegate`/`SpendingAngelApp`) and `idleOverlayWiredThroughCatchRunnerNeverRecordsWhenPerformSaysBusy` (same assertions as `CatchRunnerTests.busyCatchDoesNotRecord`). The suite header comment now points to CatchRunnerTests for sequencing and to the production call sites for the signature. Two tests remain (`freshOverlayIsNotPerforming`, `dismissOnIdleOverlayIsNoOp`). Net native count: −2.

### Q-11 — serial `permissions.contains` loop in reconcile (quality R-11, minor, performance) — deferred

Verified: `reconcileContentScripts` awaits `chrome.permissions.contains` per allowlisted host in a `for…of`. The `Promise.all` rewrite keeps `matches` order but changes the IPC concurrency profile and is `safe_to_auto_apply=false`. Pre-existing on `main`; the EXT-03 queue only makes it more visible. Cheap follow-up; the existing "a second reconcile replaces the registration wholesale" test would cover it.

### Q-12 — synchronous per-rejection log serialization (quality R-12, minor, performance) — deferred

Same root as S-04, quality angle: `Log.write` does `JSONSerialization` + `os.log` on the caller's (main) queue for every rejected request. Either coalescing or moving serialization onto `Log`'s existing utility queue changes logging behaviour; owner call. Note the two reviewers proposed compatible fixes — a suppression window in `BridgeServer` (S-04) plus off-main serialization in `Log` (Q-12) would address both.

### Q-13 — per-call array allocation in `validate` (quality R-13, minor, style) — applied

`BridgeServer.swift`: `static let allowedTriggers: Set<String> = ["click", "load", "simulated"]` hoisted next to `maxIDLength`; `validate` uses `allowedTriggers.contains(i.trigger)`. Same three values; `validationOrderTypeBeforeTriggerBeforeIDBeforeHost` and the trigger tests still pass.

### Q-14 — unused `START_CLOCK` export (quality R-14, minor, dead-code) — applied

`extension/tests/harness.js`: `START_CLOCK` removed from `module.exports` (no test imported it — verified by grep); the internal constant stays and now carries a comment saying tests read `h.clock.now` so there is one source of truth.

## Applied refactors

All behaviour-preserving; both suites green after each group.

1. **`BridgeServer.swift`** — header doc aligned with README (Q-05); `minCatchInterval` comment (Q-04); `allowedTriggers` set (Q-13); `reasons` table hoisted + `responseHead(status:)` extracted, `respond()` delegates to it (S-06); `headerValue(_:named:)` extracted, `contentLength`/`bearerToken` call it (Q-08).
2. **`Store.swift`** — `streakDays` deleted (Q-03).
3. **`OverlayController.swift`** — re-trigger comment moved to the `panel == nil` guard (Q-06).
4. **`extension/background.js`** — 429 comment (Q-07); `.catch(() => {})` on five fire-and-forget `set` calls + a header-comment note (Q-01).
5. **`extension/content.js`** — `.catch(() => {})` on the `lastIntent` set + a two-line comment (Q-01 / S-07 half).
6. **`extension/tests/harness.js`** — `START_CLOCK` un-exported (Q-14); `failNextSet(err, key)` knob (`pendingSetError`) for Q-01.
7. **Tests added** — BridgeAuthTests: 5 × `responseHead`, 2 × `headerValue`; content.test.js: 1; background.test.js: 2.
8. **Tests consolidated** — `TestFixtures.swift` (`makeIntent`, `combiningBomb`) replaces three private copies (Q-09); 1 redundant hostname case and 2 admission tests removed (Q-09, Q-10).

Suite results: extension `node --test extension/tests/*.test.js` → 103 pass / 0 fail (baseline 100); native `swift test` → 107 tests in 8 suites pass (baseline 103). No Swift warnings introduced.

## Deferred items

For the owner / a follow-up PR, roughly in priority order:

1. **S-01** — commit hygiene: exclude `sounds/stop.mp3` and `extension/preview.html` (orchestrator, at commit time).
2. **Q-02** — keep `sensor.suppressed` (debug) out of the `saLogs` ring so paused sites don't evict useful popup events. Product decision on where to filter (log.js vs popup). *(Done in Round 2 — the log call itself was removed; see below.)*
3. **S-03** — allowlist the five wire keys in `forward()` (defense in depth on the privacy invariant). *(Done in Round 2.)*
4. **S-02 + S-07 (main() half)** — try/catch around the *awaited* storage reads in `forward()` and `main()`, with a listener-level test for the SW. *(Done in Round 2.)*
5. **S-05** — respond 200 before dispatching the overlay work.
6. **S-04 / Q-12** — bound rejection-path log *count* (suppression window) and/or move JSON serialization onto `Log`'s utility queue. *(Suppression window done in Round 2; off-main serialization still open.)*
7. **Q-11** — `Promise.all` over the allowlist in `reconcileContentScripts`.

## Reviewers' overall assessments

### security

The branch implements every item in docs/design-spec.md faithfully, and the security-critical pieces hold up under scrutiny. Auth: `bearerToken` matches the header name and scheme case-insensitively, keeps only the ASCII-space/tab-separated remainder, trims with `.whitespaces` (which excludes CR/LF, so a bare-LF split header cannot smuggle a second line into the credential), first Authorization line wins even when it is non-Bearer, and `tokenMatches` is a genuine constant-time XOR fold over UTF-8 bytes with the only early exits on nil/empty-expected/length (public). `gate()` pins 204 -> 405 -> 404 -> 401 -> decode and `handle()` calls it before touching the body, so nothing request-derived is logged on the 401 path; `respond()` drops both CORS headers on every status and adds `Connection: close`. EXT-03: `syncContentScripts` is a proper promise tail (`then(reconcile).catch(log)`), each reconcile re-reads storage at its own start, and the gated-permissions test proves an older everywhere run cannot win. EXT-01/02: `isTrusted` is the first statement of the capture listener (no log, no write), the cooldown stamp happens before the first `await`, and `saShouldWatch` is consulted per event including the deferred 800 ms load. NATIVE-02: `catchCount(monthlyCount:countMonth:at:calendar:)` is pure and the dropdown reads it on a minute timeline with the same `.current` calendar `recordCatch` uses. NATIVE-03: `CatchRunner.run` orders perform -> record -> log with the overlay as the single admission point, and both call sites go through it. Hardening: `headerExceedsCap` is checked on both framing branches with slice-relative offsets, `id`/`hostname` bounds and `Log.clip` are all UTF-8-byte based (the combining-mark tests would catch any regression to `String.count`), and every request-derived log field on the accepted/throttled/invalid paths is clipped. The intent payload is unchanged (`content.test.js` pins the five keys) and the token appears in logs only as a 4-char tail. Both suites run green with the brief's exact commands (extension 100 pass, native 103 tests / 8 suites) and the READMEs match the code (status table, caps, events, pairing flow). No high findings. The one medium is procedural: `sounds/stop.mp3` and `extension/preview.html` are in the working tree and must be excluded from the commit per the owner's decision. The minors are defense-in-depth (allowlist the wire payload in `forward()`, rate-limit rejection log lines, respond before dispatching the overlay work), a couple of missing `.catch`es on fire-and-forget storage calls, and one behaviour-preserving extraction (`responseHead(status:)`) that would let a unit test pin the no-CORS/401 header contract instead of relying solely on the manual curl checklist.

### quality

The branch implements docs/design-spec.md faithfully and both suites are green with the exact brief commands (extension: 100 tests in ~0.18 s, no leaked 4 s timers; native: 103 tests / 8 suites). Performance is acceptable everywhere the lens asked: the per-event `chrome.storage.local.get` in content.js is gated behind the synchronous 1.5 s cooldown so it costs at most one small IPC read per tab per 1.5 s; BridgeServer's new work (header-cap check, bearer parse, constant-time compare, `Log.clip`) is bounded by the 8 KB header / 1 MB body caps and stays on the pre-existing main-queue model; `TimelineView(.everyMinute)` re-evaluates one `Calendar.dateComponents` and one `daysBetween` per minute with the fixed-height frame kept on the outer view, so the window never resizes. Naming follows the house rules (dotted.snake events, `sa*` helpers, `reconcile`/`sync` split as specified), `saNormalizeBridgeToken` lives in sites.js as the single normaliser and is used by both options.js and background.js, and the harness evaluates the real scripts rather than copies. The test suites are deterministic (pinned calendar, fake clock, gate promises instead of timers, unhandled-rejection guards) and cover the failure states that matter (storage rejection, register failure, 401/429/400, abort, malformed token, busy overlay, byte-vs-grapheme bounds). CI needs no change: the JS uses only Node 17+/20-safe APIs (`structuredClone`, `.at`, `||=`, node:test `describe/after`) and the Swift Testing dependency on macos-14/Xcode 16 predates this branch. Nothing rises to must-fix-before-merge. The two medium items are worth doing in this PR: add `.catch` to the fire-and-forget `storage.set` calls so the new try/catch in `sendIntent` actually delivers the silence its comment promises, and keep `sensor.suppressed` debug lines out of the 50-entry `saLogs` ring so paused sites don't evict the useful events from the popup. The rest is housekeeping — one dead property (`Store.streakDays`), four stale/misplaced comments left behind by the edits, duplicated header-scan and test fixtures, and a couple of trivial hoists — all safe to apply without behavioural change. Note for the orchestrator: `sounds/stop.mp3` (modified) and `extension/preview.html` (untracked) are still in the working tree and must be excluded from the commit per the brief.

## Post-review addendum (2026-09-15)

CI's `macOS app (build + test)` job had been failing on `main` since June 2026 with `no such module 'Testing'`: the `macos-14` runner's default Xcode ships Swift 5.10, which has no Swift Testing. The quality reviewer's "CI needs no change" statement above was wrong on that point. Fixed on this branch by moving the job to `macos-15` (Xcode 16 by default). Extension job was unaffected.

## Round 2 (2026-09-15) — independent PR #1 review

Inputs: the external review bundle (`Spending_Angel_PR1_Review_Bundle.zip`, reviewed head `fff0f1a`), its validation (`docs/review-validation-r2.md`, binding scope), the Round 2 design spec (`docs/design-spec-r2.md`), and the two lens reviews (security, quality) run against the Round 2 working tree. Both lenses numbered their findings `R2-01…`; below they are prefixed **S2-** (security) and **Q2-** (quality) and the original id is kept in the table.

Rules applied: as in Round 1 — only findings marked `safe_to_auto_apply=true` with severity *minor* were applied, plus one *medium* whose fix is a verbatim, spec-supplied text replacement (S2-01 / Q2-01, the README pairing step — called out explicitly). No commits were made (orchestrator commits). `sounds/`, `extension/preview.html`, `*.ai`, and the root PRM/mission markdown were not touched.

### What the external review found, and how each item was addressed

| Item | Finding (validated in `review-validation-r2.md`) | Addressed by |
| --- | --- | --- |
| **R-01 / Q-02** | A paused/unlisted site was still recorded: `sensor.suppressed` went to console and the `saLogs` ring. | `extension/content.js:41` — the denied-policy branch is a bare `return` (no log, no write, no message); `sensor.suppressed` is retired. Tests: `content.test.js:329` "paused host leaves no trace anywhere" (`zq-private-shop-7731.test` absent from ring, `lastIntent`, writes, messages, console) and `:359` end-to-end through a paired service worker (no fetch). |
| **R-02 / S-02 / S-07** | Rejected storage promises could leak unhandled: `log.js` ring write, `forward()`'s token read, the `onMessage` listener, `content.js` boot. | `extension/log.js:27` one awaited async IIFE with a terminal `.catch(() => {})`; `extension/background.js:139-147` token read in try/catch (logs nothing, sets nothing, returns) and `:125` listener `.catch`; `extension/content.js:127` `void main().catch(() => {})`. Tests: `background.test.js:489` (real listener, failing token read, zero fetch/timer/log/write), `:525` (listener contains a rejecting `forward`), `content.test.js:383` (boot read failure), new `tests/log.test.js` (9 tests: failing get/set on `saLogs`, corrupted ring, missing `chrome` global, documented same-tick race). |
| **R-03** | `validate()` bounded the *trimmed* hostname, so padding reached every log sink unclipped. | `BridgeServer.swift:48` `maxHostnameLength = 253`, `:346-349` raw bound before trimming; `CatchRunner.swift` clips in `run` and the new `skipOffDuty` (`:39`), called from `AppDelegate.swift:23`. Tests: `BridgeHardeningTests.swift:67` `paddedHostnameIsRejectedRaw` (20 009-byte, 254-, 257-byte and tab-padded inputs), `:80`, `:88`; `CatchRunnerTests.swift:155`, `:181` (259-byte clipped `msg`). The `hostnameAtBoundPasses` expectation flip (`"  " + 253×a + "  "` now rejected) is an intentional contract change — Round 1 §3a is annotated as superseded. |
| **S-03** | `forward()` serialized the whole runtime message. | `extension/background.js:160` five-key `wire` literal, `body: JSON.stringify(wire)`. Tests: `background.test.js:543` extra/nested keys never reach the wire; missing `id` → four keys; key order pinned. |
| **S-04 / Q-12** | Rejection log lines unbounded in *count*. | `BridgeServer.swift:366` nested `LogThrottle` (1 line/s per key, `suppressed` + `suppressed_since` on the first line after a busy window, injectable clock), `:95` `logRejected` as the single door, five call sites converted; `bridge.unauthorized` keyed per reason so a `mismatch` probe is never hidden behind a `missing` flood. Tests: new `LogThrottleTests.swift` (15 tests, fake clock: boundary at exactly 1.0 s, independent keys, clock regression, burst-then-silence, per-reason keys). Off-main JSON serialization (the Q-12 half) is still open. |
| **Wording (1)(2)(5)** | Header comment said auth precedes body *buffering*; overstated "a page can neither call the bridge"; constant-time claimed as a machine-code guarantee. | `BridgeServer.swift:16-35` header paragraph and `:313-318` `tokenMatches` doc rewritten per design-spec-r2 §6. Options: "Paired" now only after `bridgeOk === true` (`extension/options.js:32` `tokenStateText`, live re-render at `:240`); `ui.test.js` covers the five states. |
| **CI pin** | `macos-15` image default was trusted for the toolchain. | `.github/workflows/ci.yml:24` `DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer` on the job, `:33` `grep -q 'Swift version 6\.1\.2'` assertion; `runs-on: macos-15` kept, no third-party actions. |
| **S-05, Q-11** | Respond-before-overlay; parallel permission lookups. | Deferred by the brief (protocol decision / optional perf). |

### Findings table (this round's reviewer output)

Line numbers as reported by the reviewers (pre-refactor); where an applied edit moved code, the subsection below says where it lives now.

| id | severity | category | file:line | description | recommendation | status |
| --- | --- | --- | --- | --- | --- | --- |
| S2-01 / Q2-01 | medium | docs-drift | `README.md:26` | Install step 3 still promised `"Paired — token ends in …XXXX"` on save; after Round 2 item 4 a save reads "Token saved — waiting…" and "Paired" appears only after the app answered 200. | Apply the design-spec-r2 §6 text to steps 3 and 4; optionally note the rejection-line rate limit in the security paragraph. | **applied** (medium exception: verbatim spec text, no code) |
| S2-02 / Q2-12 / Q2-13 | minor | docs-drift | `docs/design-spec.md:74,118,405,180,183`; `mac-app/README.md:105` | The three `(superseded by design-spec-r2 item 5…)` notes, the `options.renderToken` read-by entries and the mac-app README throttle sentence required by design-spec-r2 §4/§6 were missing; `docs/review-report.md` had no Round 2 section. | Add the notes, the read-by entries, the README sentence; append this section. | **applied** |
| S2-03 | minor | error-containment | `extension/background.js:106` | `onInstalled` (`async () => { await seedIfNeeded(); await syncContentScripts(); }`) was the one real listener still not contained: a rejecting storage at install/update time became an unhandled rejection in the worker. | `seedIfNeeded().then(() => syncContentScripts()).catch(() => {})`, logging nothing; add a `background.test.js` case with `failNextGet(err, "saInitialized")`. | **applied** |
| S2-04 / Q2-04 | minor | comment-accuracy | `BridgeServer.swift:374` | `LogThrottle.iso` doc claimed `suppressed_since` has "the same shape as the line's own `ts`"; `Log.iso` uses `.withFractionalSeconds`, so `ts` is `…20.123Z` and `suppressed_since` is `…20Z` — lexical comparison is exact only to the second. | Fix the comment (safe) or align the formatter options (behaviour change, not auto-applied). | **applied** (comment only) |
| S2-05 | minor | observability | `BridgeServer.swift:151` | `bridge.bad_request` is one throttle key for three causes (431/400/413), so a 431 flood can hide the first 400/413 line within a second; same for `bridge.invalid_intent` across problem strings. Explicitly accepted by design-spec-r2 edge case 15. | Optional: key per status (`"bridge.bad_request/" + status`) and add a `status` field. | **deferred** (accepted behaviour, owner call) |
| S2-06 | minor | error-containment | `extension/options.js:242` | The live re-render listener called `renderToken()` with no `.catch`; a storage that rejects while the Options page tears down produced an unhandled rejection in the page. | `renderToken().catch(() => {})`. | **applied** |
| Q2-02 | medium | docs-consistency | `docs/review-report.md:220` | No Round 2 section; the Round 1 deferred list and status column still described S-03, S-04/Q-12, Q-02, S-02/S-07 as deferred although this diff implements them. | Append the Round 2 section; mark those rows/bullets as done in Round 2. | **applied** (this section; Round 1 rows annotated "→ done in Round 2", history kept) |
| Q2-03 | medium | docs-consistency | PR #1 description | PR body still says the wire allowlist and rate limiter are "not included", cites 103/107 tests, and lacks the Round 2 manual-checklist lines. | Add a "Round 2 (review follow-ups)" table, refresh counts (extension 128, native 128 / 9 suites), add the §5c manual lines, shrink "Not included" to S-05 and Q-11. | **deferred** to the orchestrator (public content; draft text below) |
| Q2-05 | minor | naming | `BridgeServer.swift:74` | Two unrelated "throttles" in one file: the 429 catch throttle (`minCatchInterval`) and the log-line throttle (`LogThrottle`, property `throttle`); `logRejected("bridge.intent_throttled", …)` → `throttle.admit(…)` read ambiguously. | Rename the property (and the unused init label) to `logThrottle`. | **applied** |
| Q2-06 | minor | style | `BridgeServer.swift:93` | `logRejected(_ event, key: = nil, _ msg, _ fields = [:], via:)` interleaved a labeled default between positionals; the 401 call site was easy to misread. | `logRejected(_ event, _ msg, _ fields = [:], key: = nil, via:)`; reorder the one call site that passes `key:`. | **applied** |
| Q2-07 | minor | simplification | `BridgeServer.swift:370` | `Slot.dropped` / `firstDroppedAt` are a coupled pair (`dropped > 0` iff `firstDroppedAt != nil`), hence the double guard in `admit`. Correct as is. | Optional: one optional tuple `drops: (count: Int, since: Date)?`. | **deferred** (optional; current code correct) |
| Q2-08 | minor | test-harness | `extension/tests/harness.js:185` | `failFirstGet instanceof Error \|\| !("err" in failFirstGet)` wrapped a keyless object as the error and threw `TypeError` for a string; only a bare Error or `{ err, key }` is documented. | `const spec = failFirstGet instanceof Error ? { err: failFirstGet } : failFirstGet;` | **applied** |
| Q2-09 | minor | test-quality | `extension/tests/content.test.js:601` | `paused.fireTimers()` right after asserting `timers.length === 0` is a guaranteed no-op; the end-to-end R-01 test pipes an asserted-empty `messages` array into a background handle, so its bridge half is vacuous. | Delete the no-op line (safe); keep the e2e test as a labelled tripwire or fold it into the first test. | **partially applied** — the no-op `fireTimers()` line is removed (one-liner, cannot change any outcome); the tripwire-vs-fold decision is deferred |
| Q2-10 | minor | style | `extension/options.js:5` | Header comment left a 30-column ragged line after the Round 2 insertion. | Reflow lines 3–10. | **applied** |
| Q2-11 | minor | stale-comment | `BridgeHardeningTests.swift:5` | Suite header did not mention the raw-hostname rule the file now pins. | Add the clause. | **applied** |

### Applied refactors

All behaviour-preserving except S2-03 (a containment `.catch` on a path that previously leaked); both suites green after each group.

1. **`extension/background.js`** — `onInstalled` listener contained: `seedIfNeeded().then(() => syncContentScripts()).catch(() => {})` with a three-line intent comment (S2-03). Now at `:106-111`.
2. **`extension/options.js`** — `renderToken().catch(() => {})` in the `storage.onChanged` listener (S2-06, `:244`); header comment reflowed to the file's width (Q2-10).
3. **`extension/tests/harness.js`** — `failFirstGet` shape check reduced to the two documented forms (Q2-08, `:185`).
4. **`extension/tests/background.test.js`** — the two existing `onInstalled` drives no longer `await` the listener's (now `undefined`) return value: `h.listeners.onInstalled[0](); await flush(h, 6);`. New test `onInstalled is contained when storage rejects at install time (R2-03)` (`:259`): arms `failNextGet(err, "saInitialized")`, drives the real listener, asserts zero unhandled rejections, zero writes, zero registrations, zero log lines, zero console output, then a recovered second install seeds and syncs. Regression check: with the `.catch` stripped in a scratch copy the test fails with `unhandled rejections leaked: Error: storage gone` (plus 5 knock-on failures) — the guard is real.
5. **`extension/tests/content.test.js`** — no-op `paused.fireTimers()` removed (Q2-09 half).
6. **`mac-app/Sources/SpendingAngel/BridgeServer.swift`** — `throttle` → `logThrottle` (property, init label, doc comment now names the 429 catch throttle as the thing it is *not*) (Q2-05); `logRejected(_ event, _ msg, _ fields = [:], key: String? = nil, via:)` with the 401 call site reordered (Q2-06); `iso` doc comment states second resolution and that `ts` carries fractional seconds (S2-04 / Q2-04). Verified against the reviewer-style stub gate: `BridgeServer.swift` + `CatchRunner.swift` still compile standalone with a stub `Log` (`info`/`error`/`clip` only), `BridgeServer(expectedToken:) { intent in … }` still resolves, and the 20 009-byte hostname repro yields `"bad hostname"` from `validate()` and a 259-byte `msg` from `CatchRunner.run`.
7. **`mac-app/Tests/SpendingAngelTests/BridgeHardeningTests.swift`** — header names the raw-before-trimming rule (Q2-11).
8. **Docs** — `README.md` steps 3–4 follow the new Options wording; security note mentions the per-event rate limit (S2-01 / Q2-01). `mac-app/README.md` Logs paragraph describes `suppressed` / `suppressed_since` and the per-reason key (Q2-13). `docs/design-spec.md` carries the three `(superseded by design-spec-r2 item 5 …)` notes (schema row, size-caps row, edge case 26) and `options.renderToken` in the read-by column of `bridgeOk` / `bridgeWhy` (S2-02 / Q2-12). `docs/design-spec-r2.md` item 6 gained a one-paragraph note that the shipped names are `logThrottle` and the reordered `logRejected` signature, so the Round 2 spec matches the code. Round 1 rows/bullets in this report that Round 2 closed are annotated "→ done in Round 2" (Q2-02).

Suite results after the refactors: extension `node --test extension/tests/*.test.js` → **128 pass / 0 fail, 10 suites** (Round 2 entry 127; +1 for S2-03); native `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app` → **128 tests / 9 suites pass**, no Swift warnings. Baselines before Round 2 were 103 / 107.

### Still deferred

1. **S-05** — respond `200` before dispatching the overlay work (protocol-semantics decision; reviewer's own recommendation to defer).
2. **Q-11** — `Promise.all` over the allowlist in `reconcileContentScripts` (optional perf; no correctness bug).
3. **Q-12 (off-main half)** — moving JSON serialization onto `Log`'s utility queue; the count bound (S-04) is done.
4. **S2-05** — per-status keys / `status` field on `bridge.bad_request` and per-problem keys on `bridge.invalid_intent`; accepted behaviour per design-spec-r2 edge case 15, owner call.
5. **Q2-07** — collapse `Slot.dropped` / `firstDroppedAt` into one optional; current code is correct.
6. **Q2-09 (second half)** — decide whether `paused host never reaches the bridge end to end (R-01)` stays as a labelled tripwire or folds into the first R-01 test.
7. **Q2-03** — PR #1 description refresh (orchestrator; public content). Suggested body delta: add a "Round 2 (review follow-ups)" table with the eight items above and their file references; replace the test-plan counts with extension 128 / native 128 in 9 suites; add the two manual lines from design-spec-r2 §5c — (a) `for i in $(seq 20); do curl -s -o /dev/null -X POST http://127.0.0.1:17865/intent; done; sleep 1.2; curl -s -o /dev/null -X POST http://127.0.0.1:17865/intent` → the day's JSONL shows one `bridge.unauthorized` (`reason:"missing"`) then one more with `"suppressed":"19"` and a `"suppressed_since"` inside the first second, every request still `401`; then within one second of a fresh no-token burst, one request with `-H 'Authorization: Bearer 0000…0000'` (64 zeros) → a `reason:"mismatch"` line appears immediately; (b) after Save, Options reads "Token saved — waiting…", and "Paired — token ends in …XXXX" only after "Simulate intent"; and shrink "Not included" to S-05 and Q-11 (plus the Q-12 off-main half).
8. **S-01 (commit hygiene, unchanged)** — `sounds/stop.mp3` (modified) and `extension/preview.html` (untracked) must stay out of the commit; `docs/design-spec-r2.md`, `docs/review-validation-r2.md`, `extension/tests/log.test.js` and `mac-app/Tests/SpendingAngelTests/LogThrottleTests.swift` are untracked and must be added.

### Reviewers' overall assessments

#### security

The Round 2 working tree (vs fff0f1a) implements docs/design-spec-r2.md faithfully and both suites are green with the brief's exact commands: extension 127 pass / 10 suites (baseline 103), native 128 tests / 9 suites (baseline 107). On the reviewer's lens: (1) a paused/unlisted hostname reaches nothing — content.js's denied branch is a bare return, main() only reads saMode and logs nothing, the click path drops before any log, background's sites.registered logs counts only, popup/options never log the current host, and the 'zq-private-shop-7731.test' test pins absence from ring, lastIntent, writes, messages, console and (piped through a paired SW) fetches; the manifest has no externally_connectable, so onMessage is reachable only from this extension's own contexts. (2) The wire object is airtight: forward() serializes a fresh five-key literal after the constant-type check, extra/nested keys cannot travel, undefined keys are dropped (never more than five), and the app's validate() remains the single validator. (3) The suppression window never hides the first occurrence per key and receives only constant keys plus a clock reading; the 401 line still carries only `reason`; the one accepted blind spot is the shared bridge.bad_request / bridge.invalid_intent keys across causes (R2-05, spec edge 15). (4) The raw hostname is bounded (≤253 UTF-8 bytes before trimming) ahead of every consumer, and all four hostname log sites (intent_received, intent_throttled, CatchRunner.run, skipOffDuty) clip; onIntent still receives the raw ≤253-byte value as specified. (5) Rejections are contained through the real listeners: onMessage → forward() (token read caught, no log/set/fetch/timer), log.js's single awaited chain with terminal catch (proven with failing get/set on saLogs and a missing chrome global), and `void main().catch` for the boot read — each with an unhandledRejection guard in the test file; the one uncontained real listener is onInstalled → seedIfNeeded (R2-03, minor). (6) No Round 1 guarantee regressed: gate order, responseHead bytes, tokenMatches/bearerToken bodies, lastAccepted semantics, the unpaired no-timer path, the one-write reset in saveToken, CatchRunner.run's signature/ordering, storage keys and popup strings are unchanged; the hostnameAtBoundPasses expectation flip is intentional and documented. The CI pin is sound (job env DEVELOPER_DIR + `grep -q 'Swift version 6\.1\.2'` under GitHub's `bash -eo pipefail`). The only gap that matters for the PR is documentation drift: README step 3 still promises 'Paired' on save (R2-01), and the design-spec supersession notes, mac-app README throttle sentence and review-report Round 2 section required by the spec are absent (R2-02). Housekeeping for the orchestrator: sounds/stop.mp3 (modified) and extension/preview.html (untracked) are still in the tree and must stay out of the commit per the Round 1 decision; docs/design-spec-r2.md, docs/review-validation-r2.md, extension/tests/log.test.js and mac-app/Tests/SpendingAngelTests/LogThrottleTests.swift are untracked and must be added. No high-severity findings; nothing blocks merge once the docs are aligned.

#### quality

The Round 2 code is in good shape and matches docs/design-spec-r2.md closely; nothing rises to high, and I found no ordering, thread-safety, or determinism defects. The async logger change is safe for every shipped caller: the only ordering that mattered was get-then-set for the ring itself, which the single awaited IIFE preserves, and no shipped path calls saLog twice in one synchronous turn (content.js emits one sensor.intent; every consecutive pair in background.js is separated by an await on storage, scripting or fetch), so the documented edge-28 race cannot bite in production, and popup.renderEvents has no ordering assumption. The containment paths (forward()'s token read, the onMessage .catch, void main().catch) log nothing and set nothing, exactly as the brief requires, and the S-03 wire object is built from the five named keys in validate() order. LogThrottle is simple and genuinely main-queue confined (the NWListener and every connection run on .main, so the lockless dictionary is correct), the window arithmetic is right at both boundaries and on clock regression, and the six keys keep the dictionary bounded; the only inaccuracy is its comment claiming suppressed_since has the same shape as Log's ts (Log uses fractional seconds). validate() bounds the raw hostname first and both hostname log sites clip, with a test that would fail if either regressed. The tests are deterministic: a fake clock for the throttle, scoped failNextGet/failFirstGet knobs so the ring read cannot steal a failure meant for the read under test, unhandledRejection guards, and no real waits — the extension suite runs 127 tests in 0.18 s (so no leaked abort timers) and the native suite runs 128 tests in 9 suites. The new JS uses only Node 20-safe APIs (structuredClone, .at, node:test describe/after). The CI change is correct: env is on the job, DEVELOPER_DIR points at /Applications/Xcode_16.4.app/Contents/Developer, the assertion step really fails on a version drift (the grep matches 'Apple Swift version 6.1.2' and run steps use bash -e), and macos-15 is kept with no third-party actions. The findings that need a human are all wording: the root README's pairing step still promises 'Paired — token ends in …XXXX' immediately after Save, which the new Options strings no longer say; docs/review-report.md has no Round 2 section and still lists S-03, S-04/Q-12 and Q-02 as deferred; and the PR body says the wire allowlist and rate limiter are not included. The rest is housekeeping — a misleading 'throttle' property name beside the unrelated 429 throttle, an awkward parameter order in logRejected, a redundant Slot field pair, a too-clever failFirstGet shape check, one no-op fireTimers() and one vacuous end-to-end test, a ragged options.js header, and the promised 'superseded' notes never applied to docs/design-spec.md — all safe to apply without behavioural change except where marked.

## Round 3 (2026-09-15) — usability: install flow and honest app status

A decision round, not a review round (spec: `docs/design-spec-r3.md`; branch `feat/usability-r3`). Two entries from the deferred lists move:

- **S-05 — resolved by decision.** The bridge no longer answers `200` with an empty body before the app has decided anything. `200` now means *accepted and handled*, and its JSON body says what happened: `{"result":"shown","character":"mom"}` or `{"result":"skipped","reason":"off"|"snoozed"|"busy"}` (plus `snooze_until`), always with `app_version`; `429` carries `{"result":"skipped","reason":"throttled","retry_in_s":N}`. The overlay call is synchronous panel creation (milliseconds) against the sensor's 4 s timeout, so no dispatch reordering was needed — the reviewer's respond-before-overlay proposal is answered by making the response *mean* what it says instead. Code: `BridgeServer.responseBody` / `throttledBody` / `responseHead(status:bodyLength:)` (pure; `BridgeResponseTests` pins the bytes), `CatchRunner.decide` (`CatchDecideTests`), `IntentOutcome` returned by `onIntent`. Every status, evaluation order and log event from Rounds 1–2 is unchanged; the empty-body head is byte-identical to before. The body carries nothing request-derived.
- **Q-11 — still deferred.** No delay was measured in `reconcileContentScripts` during the acceptance runs, so the serial `permissions.contains` loop stays until one is.

Also landed on the native side: `AppInfo.version` = 0.6.0 as the single version source (bridge body, dropdown footer, `scripts/bundle.sh`; `AppInfoTests` reads `extension/manifest.json` relative to `#filePath` and fails on drift); `scripts/bundle.sh` / `install.sh` / `update.sh` / `uninstall.sh` and a root `Makefile` for a real `~/Applications/Spending Angel.app` (ad-hoc signed, `LSUIElement`, LaunchAgent `net.modafoca.spendingangel`); `Store.migrateLegacyDefaults` so the bundle-id change does not lose the bare binary's goal, character, counter, token and `installID` (`StoreMigrationTests`, isolated suite; called first thing in `SpendingAngelApp.init()` before any `Log` call); a `Bundle` step on the macOS CI job and `bash -n scripts/*.sh` on the extension job. Native suite after Round 3: **160 tests / 14 suites** (Round 2 entry: 131 incl. `StoreRestoreTests`). The extension half of Round 3 (`status.js`, Options App card, `lastResult` / `appVersion` storage) is reported with its own suite counts by the extension agent.

Still deferred, unchanged from Round 2: Q-11 (above), Q-12 off-main half, S2-05, Q2-07, Q2-09 second half, Q2-03 (PR body), S-01 commit hygiene (`sounds/stop.mp3` modified and `extension/preview.html` untracked must stay out of the commit).
