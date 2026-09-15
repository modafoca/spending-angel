# Spending Angel — Validation of the independent PR #1 review (Round 2)

Source: `~/Documents/ChatGPT/spending-angel/outputs/Spending_Angel_PR1_Review_Bundle.zip` (reviewed head `fff0f1a`, 2026-09-15).
Validated by Claude Code against the same head on branch `fix/audit-2026-09`. Every claim below was re-read in source; the reviewer's own fixtures live at `<scratch>/pr1review/evidence/` with `repository/` symlinked to this checkout.

## Verdict on the review

The review is accurate. It closes five of the six original findings, keeps EXT-01 open on a privacy detail, and adds three new items. All three new items and the confirmed deferred items are valid. Nothing in the review is rejected. Two items are consciously left out of this round (below).

| ID | Verdict | Evidence checked |
| --- | --- | --- |
| **R-01** paused-site activity still recorded | **Valid, P2.** `content.js` suppression branch calls `saLog("debug","sensor.suppressed", "<trigger> on <host> …")`; `log.js` writes every level into `chrome.storage.local.saLogs` (50-entry ring) and console. A paused/unlisted host therefore keeps being recorded locally. | `extension/content.js:37-41`, `extension/log.js:10-28` |
| **R-02** shared logger leaks rejected promises | **Valid, P3.** `log.js:21-23` calls `storage.set` inside a callback with no promise handling; the surrounding try/catch cannot catch it. `forward()` awaits the token read outside its try/catch and `onMessage` calls `forward(msg)` with no `.catch`. `content.js` ends with a bare `main();`. | `extension/log.js:18-27`, `extension/background.js:115-130`, `extension/content.js:122` |
| **R-03** raw hostname bypasses log bounds | **Valid, P3.** `validate()` trims into a local `host` and bounds that copy; the untouched `Intent` goes to `onIntent`, and `AppDelegate` (`catch.skipped_off_duty`) and `CatchRunner` (`catch.performed` / `catch.skipped_busy`) log `intent.hostname` unclipped. | `BridgeServer.swift:290-299`, `AppDelegate.swift:20-30`, `CatchRunner.swift:23-29` |
| **S-03** whole payload serialized to the wire | **Valid.** `body: JSON.stringify(payload)` in `forward()`. | `extension/background.js:140-148` |
| **S-04 + Q-12** rejection log lines unbounded in count | **Valid.** `handle()` logs `bridge.unauthorized` / `bridge.bad_request` / `bridge.invalid_intent` once per request; `Log.clip` bounds bytes per line, nothing bounds lines. JSON formatting happens on the caller (main queue) before `queue.async`. | `BridgeServer.swift:143-176`, `Log.swift:77-112` |
| **S-02 / S-07** unhandled boot/token reads | **Valid**, folded into R-02. | as above |
| **S-05** respond before overlay work | **Deferred by the reviewer's own recommendation** (protocol semantics decision). Not in this round. | — |
| **Q-11** serial permission lookups | **Optional per reviewer; not in this round.** No correctness bug. | — |
| Doc/wording corrections 1–5 | **Valid.** (1) auth is before decode, not before body buffering; (2) "a web page can neither call the bridge" overstates: simple POSTs can be *sent*, only unreadable/unauthorized; (3) Options says "Paired" on save before any authenticated request; (5) constant-time claim should say source-level, not machine-code guarantee. (4) is guidance, already reflected in the report. | `BridgeServer.swift:16-22, 271-283`, `extension/options.js:31-34` |
| CI: pin Xcode explicitly | **Valid, cheap.** `macos-15` currently resolves to Xcode 16.4 (Swift 6.1.2 in run 34940554506). | `.github/workflows/ci.yml` |

## Scope for Round 2 (owner: Ian, instruction 2026-09-15: "complete and address remaining suggestions")

**Extension track**
1. R-01 / Q-02: remove the `sensor.suppressed` log from the denied-policy branch entirely (reviewer's smallest correction). No hostname of a paused/unlisted site may reach console or `saLogs`. Update the existing tests that asserted the suppression record; add a negative test using a distinctive hostname that asserts absence from logs, `lastIntent`, messages, and fetches. Keep the popup's `renderEvents` unchanged.
2. S-03: build a fresh five-key `wire` object in `forward()` and serialize that. Test: extra key on the message is absent from the fetch body.
3. R-02 / S-02 / S-07: (a) `log.js` storage path becomes one awaited async IIFE with a terminal `.catch(() => {})`, no recursive logging; (b) `forward()` wraps the token read in try/catch (log nothing that could recurse on a dead storage; set nothing; return) and the `onMessage` listener adds a containment `.catch`; (c) `content.js` entry becomes `void main().catch(() => {})`. Tests must drive the real listeners with failing `get`/`set` on the real keys (including `saLogs`) and assert zero unhandled rejections, zero fetches on a failed token read, zero leaked timers. The harness's existing `failNextGet` / `failNextSet` knobs may need extending; do not mask with test-side catches on production promises.
4. Options wording: on save show "Token saved — waiting for the app to confirm (…tail)" (or similar) rather than "Paired"; show "Paired — …" only when `bridgeOk === true`. Keep pixel-game copy tone. Update `ui.test.js`.

**Native track**
5. R-03: in `validate()`, bound the RAW hostname first (`i.hostname.utf8.count <= 253` → else "bad hostname"), then the trimmed/non-empty check. Adjust the existing test that accepted 253 bytes + padding (that expectation change is intentional). Add padded-input regression cases and assert both `catch.skipped_off_duty` and `CatchRunner` log paths receive a bounded hostname (belt and braces: also `Log.clip` at those two call sites).
6. S-04 / Q-12: bounded rejection logging in `BridgeServer`: a per-event-key suppression window (1 line per second per event key; injectable clock for tests), and when the window closes emit the next line with a `suppressed: "<n>"` field. Pure/injected so it is unit-testable with a fake clock. HTTP status codes unchanged; never include token or body bytes. Apply to `bridge.unauthorized`, `bridge.bad_request`, `bridge.bad_payload`, `bridge.invalid_intent`, `bridge.intent_throttled`.
7. Wording: fix the `BridgeServer` header comment per corrections (1), (2), (5); fix the `tokenMatches` doc comment to say "no data-dependent early exit in source; compiler-level timing not guaranteed".
8. CI: pin Xcode on the macOS job with `DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer` (env on the job) and keep `runs-on: macos-15`; add a `swift --version` assertion comment. Do not use third-party actions.

**Docs**
9. Append "## Round 2 (2026-09-15)" to `docs/review-report.md` from the Round 2 review output; update the PR description checklist and the READMEs only if the pairing status wording changed anything user-facing.

## Constraints (unchanged from Round 1 brief `docs/audit-validation.md`)

- Commands: extension `node --test extension/tests/*.test.js`; native `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app`. Never run `xcode-select`.
- No git commit/checkout/stash/reset/push by sub-agents. Do not touch `sounds/`, `extension/preview.html`, `*.ai`, root PRM/mission markdown.
- Baselines before Round 2: extension 103 pass, native 107 tests / 8 suites pass, CI green on run 34940554506.
- Privacy invariant: only `{id,type,trigger,hostname,ts}` leave the page; nothing about a paused/unlisted site is recorded anywhere.

## Reviewer fixtures available to the final gate

- `<scratch>/pr1review/evidence/deferred-repros.cjs` — asserts the OLD (bad) behaviour for Q-02, S-03, S-02, logger write. After Round 2 it must FAIL at its first assertion; our own suite carries the corrected expectations.
- `<scratch>/pr1review/evidence/browser-bridge-check.cjs` — real Chrome for Testing + real Swift listener (needs `repository/` symlink, `SA_REVIEW_CHROME`, Node ≥22, Xcode). Its step "REPRO: unlisted page still persists hostname/activity in debug log" asserts the OLD behaviour; the gate runs a copy with that assertion inverted (assert no `sensor.suppressed` entry and no `127.0.0.1` in any `saLogs` entry written after unlisting) and expects all nine steps to pass.
- `<scratch>/pr1review/evidence/hostname-log-repro.swift` — standalone repro for R-03; after the fix a 20,009-byte padded hostname must be rejected by `validate()`.
