# Spending Angel — macOS app

The brain and the performer. A menu-bar app that owns the goal, the cast, on/off,
snooze and the monthly stat, and fires the **catch**: a full-screen overlay where a
character ambushes you with a voice line. Real catches arrive from the Chrome
Sensor (`../extension/`) over a paired localhost bridge; a **▶ test** link in the
dropdown fires one by hand.

## Install

From the repo root:

```bash
make install                   # build → ~/Applications/Spending Angel.app → login item → start
make update                    # git pull --ff-only, then install (reminds you to reload the extension)
make uninstall                 # stop, remove app + login item (PURGE=1 also removes settings + logs)
make bundle                    # only build mac-app/.build/Spending Angel.app — safe while the app runs
NO_LOGIN_ITEM=1 make install   # no LaunchAgent, just open the app once
```

`scripts/bundle.sh` does `swift build -c release`, then wraps the binary and the SwiftPM
resource bundle (`SpendingAngel_SpendingAngel.bundle`, found via `Bundle.main.resourceURL`)
into a bundle with `CFBundleIdentifier net.modafoca.spendingangel`, `LSUIElement`, the
version from `AppInfo.swift`, and an icon derived from the sensor's `icon128.png`; then
signs it ad-hoc (`codesign --sign -`) and verifies with `--deep --strict`. No Developer ID
and no notarisation yet, so it is for this Mac, not for handing out. `scripts/install.sh`
stops any running copy, replaces the app, writes
`~/Library/LaunchAgents/net.modafoca.spendingangel.plist` (`RunAtLoad`, no `KeepAlive`, so
"quit" sticks until the next login), bootstraps it and waits up to 5 s for
`bridge.listening` in today's log. All scripts are idempotent and print what they did.

A `$`-halo icon appears in the menu bar (no Dock icon). Click it for the dropdown.
Only one copy runs at a time: the bridge port doubles as a single-instance lock, so
a second launch logs `app.duplicate_instance` and quits itself.

### Run from source (development)

```bash
swift run --package-path mac-app       # or: make run
```
**Or Xcode:** open `mac-app/Package.swift`, pick the `SpendingAngel` scheme, Run.
Quit the installed copy first (port lock), and don't `make install` while a dev copy is
up — the install script kills it.

## The dropdown

Top to bottom (pixel-game theme — `Theme`, `.pixel()` font, `PixelFrame` corners):

- **SAVING FOR** — the goal, free text. Blank falls back to the generic line.
- **PICK YOUR GUARDIAN** — The Angel, Dominican Papi, The Wizard, Asian Mom (four "?" slots are reserved for future cast).
- **SHAKE IT UP** — random character per catch, no immediate repeats.
- **Stat box** — the character's brag over this calendar month's catch count ("I've stopped you 3 times. You're welcome.") plus a days-clean streak. Derived from the month containing *now*, so the count reads 0 on the 1st even before the first catch.
- **PAIR SENSOR** — the pairing token with a **COPY** button. Paste it into the extension's Options → Pair with the app. Regenerating (same row) mints a new one and invalidates the old pairing until you paste again.
- **SPENDING ANGEL IS ON / OFF** — master switch. **SNOOZE 1 HR / WAKE UP** — a nap. Real intents respect both.
- **▶ test** / **v0.6.0** / **quit** — the test fires a catch regardless of on-duty state (and counts toward the stat if it actually plays); the version in the middle is `AppInfo.version`, the same value the bridge reports.

## The bridge

`BridgeServer.swift` listens on `http://127.0.0.1:17865` (loopback only).

```
POST /intent HTTP/1.1
Authorization: Bearer <64-hex token>
Content-Type: application/json

{"id":"<uuid>","type":"checkout_intent","trigger":"click"|"load"|"simulated","hostname":"amazon.com","ts":1700000000000}
```

Every response has `Connection: close` and no CORS headers (the Sensor's service worker
has `host_permissions` for `127.0.0.1`, so it needs none; a web page therefore can't
read anything back). `200` and `429` carry a small JSON body — the app says what it did,
so the Sensor can show "Character shown — Mom" instead of only "Connected"; every other
status has an empty body (`Content-Length: 0`, no `Content-Type`).

**Response contract** (`BridgeServer.responseBody` / `throttledBody`; keys sorted, no
whitespace, `Content-Type: application/json; charset=utf-8`):

```
200  {"app_version":"0.6.0","character":"mom","result":"shown"}
200  {"app_version":"0.6.0","reason":"off","result":"skipped"}
200  {"app_version":"0.6.0","reason":"snoozed","result":"skipped","snooze_until":"2026-09-15T22:43:54Z"}
200  {"app_version":"0.6.0","reason":"busy","result":"skipped"}
429  {"app_version":"0.6.0","reason":"throttled","result":"skipped","retry_in_s":5}
```

`200` means *accepted and handled* — the decision is made before the response is written
(overlay creation is synchronous and takes milliseconds, well under the Sensor's 4 s
timeout). `character` is the id (`angel` / `papi` / `wizard` / `mom`); `snooze_until` is
UTC at second resolution and only present when a deadline is known; `retry_in_s` is the
remaining throttle window rounded up, never below 1. The body is built from the app's
own state only — nothing from the request is echoed back. The mapping lives in
`CatchRunner.decide` (`!enabled` → off, snooze ahead of now → snoozed, overlay refused →
busy, else shown); the `IntentOutcome` enum is the value `onIntent` returns.

| Status | When |
| --- | --- |
| `200` | accepted and handled — the JSON body says whether a character was shown, or why not |
| `204` | `OPTIONS` (any path) — answered so a stray preflight doesn't hang; no auth |
| `400` | bad `Content-Length`, body isn't an intent, or it fails validation |
| `401` | missing or wrong bearer token (`WWW-Authenticate: Bearer realm="spending-angel"`); body never decoded or logged |
| `404` | path isn't exactly `/intent` |
| `405` | method isn't `POST` |
| `413` | `Content-Length` over 1 MB |
| `429` | fewer than 8 s since the last *accepted* intent — body carries `retry_in_s` |
| `431` | request headers over 8 KB |

Caps: headers 8 192 bytes, body 1 000 000 bytes, `id` 128 bytes, `hostname` 1–253 bytes
(UTF-8), 10 s per connection. Logged request fields are clipped to 256 bytes.

**Pairing.** On first launch `Store` generates a token (32 random bytes → 64 lowercase
hex chars), keeps it in `UserDefaults` (`bridgeToken`), and shows it under PAIR SENSOR.
The server reads it per request and compares in constant time, so regenerating takes
effect immediately, no restart. The token is never written to the logs (at most its
last 4 characters, as `token_tail`).

## Versioning

`AppInfo.version` (`Sources/SpendingAngel/AppInfo.swift`) is the one version string: the
bridge sends it as `app_version`, the dropdown shows it, and `scripts/bundle.sh` greps it
into `CFBundleShortVersionString` / `CFBundleVersion`. **Bump rule:** change it and
`extension/manifest.json` `version` together, in the same commit — `AppInfoTests` reads
the manifest relative to `#filePath` and fails when they drift, and the Sensor's
Versions row compares major.minor across the bridge, so a lone bump would tell the user
to "update the app" right after they did.

## Settings and their migration

State is `UserDefaults` (`goal`, `activeCharacter`, `enabled`, `snoozeUntil`,
`shuffleMode`, `monthlyCount`, `countMonth`, `lastCatchDate`, `bridgeToken`, plus
`installID` from `Log`). The bare `swift run` binary keeps them under the process-name
domain `SpendingAngel`; the bundle uses `net.modafoca.spendingangel`. On launch,
before anything touches `Log`, `Store.migrateLegacyDefaults` copies the old domain into
the new one exactly once (marker `migratedFromLegacyDefaults`) — skipped when there is
nothing to copy or when the new domain already has an `installID` / `bridgeToken` of its
own, so a fresh install is never overwritten by a stale one. Logged as
`store.defaults_migrated` with the key count. The old domain is left in place for the
dev binary.

## The catch sequence

```
t+0.0    overlay panel appears above everything (any Space, fullscreen apps too);
         character animates in; clicks are intercepted; the voice line starts
t+0.5    intercept releases → overlay becomes click-through
t+hold   exit animation (0.4 s), panel closes
```

`hold = max(4 s, clip length + 0.6 s)`. Clips run up to ~12 s, so a catch can be on
screen well past the bridge's 8 s throttle. The overlay is the single admission point:
if a catch is already playing, the next one is dropped and logged as
`catch.skipped_busy` — it is **not** counted in the stat. Only an admitted catch
records and logs `catch.performed`. The bridge path additionally checks on-duty first
(`catch.skipped_off_duty`); the manual test doesn't.

The 0.5 s intercept is the **"get through me first"** gag — during it, a click anywhere
is swallowed. After it you can proceed with your purchase; the character fades on its own.

## Voice lines

Per character under `Sources/SpendingAngel/Resources/voice/<character>/`
(`angel`, `papi`, `wizard`, `mom`): a few `*.mp3` clips plus a `captions.json` so the
speech bubble types the exact line being spoken. The player picks one at random.
Without a caption the bubble falls back to "You're saving for <goal>."

## Logs

One JSON line per event in `~/Library/Logs/SpendingAngel/spending-angel-YYYY-MM-DD.jsonl`
(14-day retention), mirrored to os.log under subsystem `net.modafoca.spendingangel`
so Console.app / `log stream` see it live. Nothing leaves the machine.

Events worth grepping for: `bridge.listening`, `bridge.unauthorized`,
`bridge.intent_received`, `bridge.intent_throttled`, `catch.performed`,
`catch.skipped_busy`, `catch.skipped_off_duty`, `store.token_generated`,
`store.token_regenerated`, `store.defaults_migrated`, `pair.token_copied`. `intent_id` traces one catch from the
extension to the overlay. Rejection events (`bridge.unauthorized`, `bridge.bad_request`,
`bridge.bad_payload`, `bridge.invalid_intent`, `bridge.intent_throttled`) are written at
most once per second per event (per reason for `bridge.unauthorized`); the next line
after a burst carries `suppressed: "<n>"` with the number dropped and `suppressed_since`
with the time of the first drop.

## Tests

Swift Testing, in `Tests/SpendingAngelTests/`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app
```

Full Xcode is required — the Command Line Tools alone don't ship the `Testing`
module. `swift build --package-path mac-app` works with either.

Poking the bridge by hand:

```bash
TOKEN=<paste from PAIR SENSOR>
curl -i -X POST http://127.0.0.1:17865/intent \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"checkout_intent","trigger":"simulated","hostname":"example.com","ts":0}'
# expect 200; drop the Authorization header and expect 401
```

## Notes / deliberate choices

- **Swift Package, not `.xcodeproj`** — reliable to build from terminal and in
  Xcode, and verifiable in CI. `scripts/bundle.sh` wraps the release build into an
  ad-hoc-signed `.app` (CI runs it too); notarisation is still to come (needs the
  Apple Developer account; not required on your own Mac).
- **Loopback + bearer token, not Native Messaging** — keeps the extension a plain
  MV3 package with no host manifest to install. The token is the only secret.
- **Menu-bar trigger, not a global hotkey** — a global hotkey needs Input-Monitoring
  permission; we avoid invasive permissions on purpose. No Accessibility prompt either.
- **`NSApp.setActivationPolicy(.accessory)`** is the SPM stand-in for `LSUIElement`; the bundle sets `LSUIElement` as well, so both paths are Dock-free.
- **`UserDefaults`, not Keychain** for the token — it only ever grants "make my own
  character yell at me" on this machine.

## File map

```
mac-app/
├── Package.swift
├── Sources/SpendingAngel/
│   ├── SpendingAngelApp.swift     @main · defaults migration, MenuBarExtra + the manual test
│   ├── AppInfo.swift              the version string (bridge body, dropdown, bundle.sh)
│   ├── AppDelegate.swift          accessory policy; owns the overlay; starts the bridge
│   ├── BridgeServer.swift         127.0.0.1:17865 · auth, framing, validation, throttle, response bodies
│   ├── CatchRunner.swift          decide (off/snoozed/busy/shown) · admit → record → log
│   ├── OverlayController.swift    the NSPanel + catch-sequence timing
│   ├── CatchView.swift            the SwiftUI performance (character + bubble + animation)
│   ├── DropdownView.swift         the menu-bar "brain" (goal, cast, stat, PAIR SENSOR, controls)
│   ├── Store.swift                persisted state: goal, cast, on/off, snooze, stat, token
│   ├── Characters.swift           the cast: names, brags, streak lines
│   ├── AudioPlayer.swift          full-volume clip playback + captions
│   ├── Log.swift                  JSONL + os.log, field clipping
│   ├── Theme.swift / PixelFrame.swift / PixelToggleStyle.swift / Fonts.swift   pixel UI kit
│   ├── AppIcons.swift / CastAssets.swift / FrameAnimationView.swift / SpeechBubble.swift
│   └── Resources/
│       ├── voice/<character>/     *.mp3 + captions.json
│       ├── cast/<character>_sequence/   frame art + portraits
│       ├── icon/ · fonts/ · ui/   $-halo mark, Silkscreen, speech bubble
└── Tests/SpendingAngelTests/      Swift Testing suites (bridge parsing/auth/response, store dates/migration, catch runner/decide, AppInfo)
```

## Historical notes

The first milestone (M-02) was menu-item-only — "no browser, no bridge yet" — with a
`😇` emoji stand-in and a single placeholder clip copied from the old extension. The
bridge landed in M-05, the real cast art and voices in M-06, and the pairing token in
the September 2026 audit fixes.
