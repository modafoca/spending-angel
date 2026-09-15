# Spending Angel — Round 3 spec: install/update flow + honest app status

Owner decisions (Ian, 2026-09-15): real `.app` in `~/Applications` with launch-at-login; the extension's **Options page becomes the main status surface**; "Connected" is kept separate from "Character shown"; parallel permission checks (Q-11) stay out unless a delay is measured. Usability work, not security.

Findings that motivated this (manual acceptance 2026-09-15): Ian never found the toolbar popup, so the "This site" controls and "App connection" line were invisible to him; the Options page said nothing about the app; the app *did* receive and perform his Amazon intent (log: `bridge.intent_received` → `catch.performed` mom) while the UI showed nothing; and an install from before 2026-09 had a monthly counter on disk with no month key (fixed on this branch: `Store.restoredCountMonth`).

Branch: `feat/usability-r3` (from `main` @ 08851af). Version bump: **app 0.6.0, sensor 0.6.0** (both halves, so the version handshake below is meaningful).

---

## A. Bridge response contract — the app says what it did

Today `BridgeServer` answers `200` with an empty body *before* the app decides anything, so the sensor can only ever say "Connected". Change: `200` and `429` carry a small JSON body describing the outcome. This settles the deferred S-05 question by decision: **200 = accepted and handled; the body says whether a character was shown.** The overlay call is synchronous panel creation (milliseconds), far under the sensor's 4 s timeout; no dispatch reordering.

### Native

```swift
/// What the app did with an accepted intent. Serialised into the 200 body.
enum IntentOutcome: Equatable {
    case shown(character: CharacterID)
    case skipped(SkipReason)
    enum SkipReason: String { case off, snoozed, busy }
}
```

- `BridgeServer.init(expectedToken:logThrottle:onIntent:)` — `onIntent: (Intent) -> IntentOutcome` (was `-> Void`).
- New `enum AppInfo { static let version = "0.6.0" }` in `AppInfo.swift`: single source of truth. Used by the response body, shown in the dropdown (small `v0.6.0` in the footer area, `.pixel(8)`, `Theme.pxDim`), and read by `scripts/bundle.sh` for `CFBundleShortVersionString`.
- Pure, unit-tested: `static func responseBody(_ outcome: IntentOutcome, snoozeUntil: Date?, appVersion: String, iso: ISO8601DateFormatter) -> Data` producing exactly (sorted keys):
  - shown: `{"app_version":"0.6.0","character":"mom","result":"shown"}`
  - off: `{"app_version":"0.6.0","reason":"off","result":"skipped"}`
  - snoozed: `{"app_version":"0.6.0","reason":"snoozed","result":"skipped","snooze_until":"2026-09-15T22:43:54Z"}` (second resolution, UTC)
  - busy: `{"app_version":"0.6.0","reason":"busy","result":"skipped"}`
  - throttled (429, built by the bridge itself): `{"app_version":"0.6.0","reason":"throttled","result":"skipped","retry_in_s":5}` where `retry_in_s = Int(ceil(minCatchInterval - elapsed))`, min 1.
- `responseHead(status:bodyLength:)`: when `bodyLength > 0` add `Content-Type: application/json; charset=utf-8` and `Content-Length: <bodyLength>`; otherwise unchanged (`Content-Length: 0`). No CORS headers, `Connection: close`, `WWW-Authenticate` on 401 — all unchanged. Existing `responseHead(status:)` tests stay valid (call the new one with `bodyLength: 0`).
- `respond(conn, status:, body: Data = Data(), timeout:)` writes head + body in one `send`.
- Evaluation order and every other status/log line unchanged. `handle()` calls `onIntent` for accepted intents and passes the returned outcome to `responseBody`. Snooze time for the body comes from a new `snoozeUntil: () -> Date?` init parameter (default `{ nil }`) so BridgeServer stays Store-free and testable.
- `CatchRunner`: add a pure `static func outcome(enabled: Bool, snoozeUntil: Date?, now: Date, admit: () -> Bool) -> IntentOutcome`-style helper (name it `decide`) so the off / snoozed / busy / shown mapping is unit-tested without AppKit: `!enabled → .skipped(.off)`; `snoozeUntil > now → .skipped(.snoozed)`; `admit() == false → .skipped(.busy)`; else `.shown`. `AppDelegate` uses it: off/snoozed paths still call `CatchRunner.skipOffDuty` (log unchanged), shown/busy paths still go through `CatchRunner.run` (logs unchanged). `SpendingAngelApp` manual test path unchanged.
- Log events unchanged. Add nothing to logs for the body.

### Extension (`background.js forward()`)

- On `res.ok` and on `429`: `const body = await res.json().catch(() => null)`; write `lastResult` (below) alongside the existing `bridgeOk/bridgeAt/bridgeWhy` write, in the **same** `storage.set` call. Also write `appVersion: body.app_version` when it is a string. Missing/invalid body → `lastResult.result = "unknown"` (older app). On 401 / unreachable / unpaired: do **not** touch `lastResult` or `appVersion`.
- `lastResult` shape: `{ result: "shown"|"skipped"|"unknown", reason?: "off"|"snoozed"|"busy"|"throttled", character?: string, snooze_until?: string, retry_in_s?: number, at: <ms>, intent_id: string, hostname: string, trigger: string }`. Only these keys; unknown keys from the body are dropped.
- The five-key wire object, token handling, containment, and all log events from Rounds 1–2 unchanged. The existing `bridge.rejected` log for 429 stays.

## B. Status model — one pure module, two surfaces

New file `extension/status.js` (no `chrome.*`, no DOM, `module.exports` for tests; loaded by both `popup.html` and `options.html` after `sites.js`). Functions:

```js
// Connection line. Same semantics as popup.renderBridge today, moved here.
saConnectionText({ bridgeOk, bridgeAt, bridgeWhy }, fmtTime)
// → { text, tone: "ok"|"bad"|"neutral", needsPairing: boolean }
//   null/undefined ok → "Not tried yet" / neutral
//   ok true          → `Connected ✓  ${fmtTime(bridgeAt)}` / ok
//   why unpaired     → "Not paired ✕ — paste the app's token" / bad / needsPairing
//   why unauthorized → "Token rejected ✕ — re-pair" / bad / needsPairing
//   else             → `App not reachable ✕  ${fmtTime(bridgeAt)}` / bad

// Last-request line. EXACT strings (tests pin them):
saLastResultText(lastResult, fmtTime)
// → { text, tone }
//   no lastResult              → "No request sent yet" / neutral
//   shown                      → `Character shown — ${Name} · ${fmtTime(at)}` / ok     (angel→Angel, papi→Papi, wizard→Wizard, mom→Mom; unknown id → as-is capitalised)
//   skipped off                → "Not shown — the app is switched off (turn it on in the menu bar)" / bad
//   skipped snoozed            → `Not shown — snoozed until ${fmtTime(Date.parse(snooze_until))} (Wake up in the menu bar)` / bad   (no snooze_until → "Not shown — snoozed (Wake up in the menu bar)")
//   skipped busy               → "Not shown — a character was already on screen" / neutral
//   skipped throttled          → `Not shown — too soon after the last catch (wait ${retry_in_s} s)` / neutral   (no retry_in_s → "…last catch")
//   unknown                    → "App answered, but didn't say what it did — update the app" / neutral

// Version handshake. null when equal on major.minor, or appVersion missing.
saVersionHint(sensorVersion, appVersion)
// → `Sensor v${s} · App v${a} — update the app`                          when app older
// → `Sensor v${s} · App v${a} — reload the extension at chrome://extensions`  when sensor older

// Shared payload builder for "Simulate intent" (popup + options), pure except crypto.randomUUID:
saSimulatedIntent(now) → { id, type: "checkout_intent", trigger: "simulated", hostname: "example-shop.test", ts: now }
```

`fmtTime` is injected (default in the pages: `(ms) => new Date(ms).toLocaleTimeString()`) so tests are deterministic.

### Options page (main surface)

New card **"App"** directly after the Pair card:

```
App
  Connection    Connected ✓  5:23 PM                      (tone class on the value)
  Last request  Character shown — Mom · 5:23 PM
  Versions      Sensor v0.6.0 · App v0.6.0                (+ hint line when saVersionHint returns non-null, tone bad)
  [Simulate intent]   Sends a fake checkout through the app so you can see both lines change.
  Tip: pin the toolbar icon (puzzle piece → pin “Spending Angel — Sensor”) for per-site Watch/Stop and the same status.
```

- Markup: a `<dl class="kv">` (dt/dd) inside the existing `.card.pixel`; add minimal `.kv` styles to `options.css` in the existing pixel style (no new colours; reuse `--ink`, `--dim`, and the popup's `.ok/.bad` tones — copy those two rules from `popup.css` if not already in `pixel.css`).
- `options.js`: `renderApp()` reads `{bridgeOk, bridgeAt, bridgeWhy, lastResult, appVersion}`; `chrome.runtime.getManifest().version` for the sensor version; live re-render on `storage.onChanged` for any of those keys (extend the existing listener). The Simulate button uses `saSimulatedIntent`, writes `lastIntent`, and `chrome.runtime.sendMessage(payload).catch(() => {})` exactly like the popup. Keep every existing Options behaviour and string (pairing lines unchanged).

### Popup

"App connection" section shows two lines: `#bridge-status` (connection, via `saConnectionText`) and new `#last-result` (via `saLastResultText`), plus `#version-hint` (hidden when null). `renderBridge` is replaced by the shared helpers; the pair hint link logic uses `needsPairing`. Simulate uses `saSimulatedIntent`. Everything else unchanged.

## C. Install / update flow (Mac app)

Scripts in `scripts/` (bash, `set -euo pipefail`, no third-party tools beyond Xcode/CLT; every script prints what it did and the next step):

- `scripts/bundle.sh` — `swift build -c release --package-path mac-app`, then assemble `mac-app/.build/Spending Angel.app`:
  - `Contents/Info.plist`: `CFBundleIdentifier net.modafoca.spendingangel`, `CFBundleName Spending Angel`, `CFBundleDisplayName Spending Angel`, `CFBundleExecutable SpendingAngel`, `CFBundlePackageType APPL`, `CFBundleShortVersionString` + `CFBundleVersion` = `AppInfo.version` (grep it from `mac-app/Sources/SpendingAngel/AppInfo.swift`), `LSUIElement true`, `LSMinimumSystemVersion 13.0`, `NSHighResolutionCapable true`, `CFBundleIconFile AppIcon` (only if the icon was produced).
  - `Contents/MacOS/SpendingAngel` (the release binary), `Contents/Resources/SpendingAngel_SpendingAngel.bundle` (SwiftPM resource bundle from `.build/release`; `Bundle.module` finds it via `Bundle.main.resourceURL`), `Contents/PkgInfo` = `APPL????`.
  - `Contents/Resources/AppIcon.icns` from `extension/icons/icon128.png` via `sips` + `iconutil` when both exist; skip silently otherwise.
  - `codesign --force --deep --sign - "<app>"` (ad-hoc; no Developer ID yet). Verify with `codesign --verify --deep --strict`.
- `scripts/install.sh` — runs `bundle.sh`; `pkill -x SpendingAngel || true`; replaces `~/Applications/Spending Angel.app`; writes `~/Library/LaunchAgents/net.modafoca.spendingangel.plist` (`Label`, `ProgramArguments` = the bundled executable path, `RunAtLoad true`, `KeepAlive false`, `ProcessType Interactive`); `launchctl bootout gui/$UID/net.modafoca.spendingangel 2>/dev/null || true`; `launchctl bootstrap gui/$UID "<plist>"`; waits up to 5 s for `bridge.listening` in today's log and prints the outcome + app version. Flag `--no-login-item` skips the LaunchAgent and just `open`s the app. Idempotent.
- `scripts/update.sh` — `git pull --ff-only`; runs `install.sh`; if `git diff --name-only ORIG_HEAD HEAD -- extension/` is non-empty print a loud reminder: **reload the extension at chrome://extensions**. Passes through `--no-login-item`.
- `scripts/uninstall.sh` — bootout, remove plist, remove the app; `--purge` also `defaults delete net.modafoca.spendingangel` and removes `~/Library/Logs/SpendingAngel`.
- Root `Makefile` (phony): `install`, `update`, `uninstall`, `bundle`, `run` (`swift run --package-path mac-app`, dev), `test` (both suites; uses `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when that directory exists), `help` (default).
- **Do not run `install.sh`/`update.sh` during development** — the owner's app is running from the debug binary (pid may vary) and the orchestrator installs at the end. `bundle.sh` is safe to run.
- CI: add a step `Bundle` to the macOS job after `Test`: `scripts/bundle.sh` then `codesign --verify --deep --strict "mac-app/.build/Spending Angel.app"` and `test -d ".../Contents/Resources/SpendingAngel_SpendingAngel.bundle"`.

### Settings migration (bundle id changes the UserDefaults domain)

The bare binary persisted under domain `SpendingAngel`; the bundle uses `net.modafoca.spendingangel`. Without migration Ian loses goal, character, counter, token (= must re-pair) and `installID`.

- `Store.migrateLegacyDefaults(legacy: [String: Any]?, into d: UserDefaults, marker: String = "migratedFromLegacyDefaults") -> Bool` — pure decision + copy: returns false (no-op) if `d.bool(forKey: marker)` or `legacy` is nil/empty or `d` already has `installID` or `bridgeToken`; otherwise copies every key/value, sets the marker, returns true. Unit-test the decision with an isolated `UserDefaults(suiteName:)`.
- Call it **before any `Log` call** (Log.installID reads `UserDefaults.standard` lazily): first statement of `SpendingAngelApp.init()`, reading `UserDefaults.standard.persistentDomain(forName: "SpendingAngel")`. Log `store.defaults_migrated` (info, `["keys": "<n>"]`) right after, only when it returned true.

### Docs

- Root `README.md`: "Run it" becomes `make install` (what it does, where the app lands, launch at login, how to update with `make update`, that the extension still needs a manual reload after an update, `make uninstall`). Keep the `swift run` path under "Developing". Pairing steps unchanged except the sensor now shows an **App** card on the Options page with Connection / Last request / Versions.
- `mac-app/README.md`: same install section; document the JSON response contract (A) and the `AppInfo.version` bump rule; note the defaults migration.
- `docs/review-report.md`: short "Round 3" note that S-05 is resolved by decision (200 = accepted; body carries outcome) and Q-11 remains deferred (no delay measured).

## D. Tests

Native (Swift Testing): `responseBody` exact bytes for all five shapes; `responseHead(status:bodyLength:)` with and without body (existing head tests unchanged); `CatchRunner.decide` off/snoozed/busy/shown; `Store.migrateLegacyDefaults` decision matrix with an isolated suite; `AppInfo.version` matches `extension/manifest.json` version (read the file relative to `#filePath`). Existing 131 tests stay green.

Extension (node:test): `status.test.js` pins every string in B with a fixed `fmtTime`; `background.test.js` — 200 with JSON body writes `lastResult` + `appVersion` in the same set as `bridgeOk`; 200 with empty/invalid body → `result: "unknown"`; 429 with throttled body → `lastResult.reason === "throttled"` and `retry_in_s`; 401/unreachable leave `lastResult` untouched; only the listed keys are stored. `ui.test.js` — Options App card renders the three rows and the hint; popup renders both lines; Simulate from Options sends the same payload shape as the popup. The harness `fetchImpl` may return `{ ok, status, json: async () => ({...}) }`; extend the default to `json: async () => ({})` so existing tests keep passing. Existing 128 tests stay green (strings for the connection line are unchanged).

Scripts: `bash -n` on every script in CI (extension job, cheap) and the real `bundle.sh` run on the macOS job (C).

## E. Constraints

- Commands: `node --test extension/tests/*.test.js`; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app`. Never `xcode-select`. Never `install.sh`/`update.sh`/`uninstall.sh`/`pkill` during development.
- No git commit/push by sub-agents. Do not touch `sounds/`, `extension/preview.html`, `*.ai`, root PRM/mission markdown.
- Style: 2-space JS, 4-space Swift, header comments that explain intent, `dotted.snake` log events, pixel-game UI (`Theme`, `.pixel()`, `pxCorner`, `pixel.css`). Copy tone: short, friendly, no exclamation marks.
- Privacy invariant unchanged: only `{id,type,trigger,hostname,ts}` leave the page; the response body carries no request-derived data.
