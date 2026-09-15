# Spending Angel — macOS app

The brain and the performer. A menu-bar app that owns the goal, the cast, on/off,
snooze and the monthly stat, and fires the **catch**: a full-screen overlay where a
character ambushes you with a voice line. Real catches arrive from the Chrome
Sensor (`../extension/`) over a paired localhost bridge; a **▶ test** link in the
dropdown fires one by hand.

## Run it

**Terminal:**
```bash
swift run --package-path mac-app
```
**Or Xcode:** open `mac-app/Package.swift`, pick the `SpendingAngel` scheme, Run.

A `$`-halo icon appears in the menu bar (no Dock icon). Click it for the dropdown.
Only one copy runs at a time: the bridge port doubles as a single-instance lock, so
a second launch logs `app.duplicate_instance` and quits itself.

## The dropdown

Top to bottom (pixel-game theme — `Theme`, `.pixel()` font, `PixelFrame` corners):

- **SAVING FOR** — the goal, free text. Blank falls back to the generic line.
- **PICK YOUR GUARDIAN** — The Angel, Dominican Papi, The Wizard, Asian Mom (four "?" slots are reserved for future cast).
- **SHAKE IT UP** — random character per catch, no immediate repeats.
- **Stat box** — the character's brag over this calendar month's catch count ("I've stopped you 3 times. You're welcome.") plus a days-clean streak. Derived from the month containing *now*, so the count reads 0 on the 1st even before the first catch.
- **PAIR SENSOR** — the pairing token with a **COPY** button. Paste it into the extension's Options → Pair with the app. Regenerating (same row) mints a new one and invalidates the old pairing until you paste again.
- **SPENDING ANGEL IS ON / OFF** — master switch. **SNOOZE 1 HR / WAKE UP** — a nap. Real intents respect both.
- **▶ test** / **quit** — the test fires a catch regardless of on-duty state (and counts toward the stat if it actually plays).

## The bridge

`BridgeServer.swift` listens on `http://127.0.0.1:17865` (loopback only).

```
POST /intent HTTP/1.1
Authorization: Bearer <64-hex token>
Content-Type: application/json

{"id":"<uuid>","type":"checkout_intent","trigger":"click"|"load"|"simulated","hostname":"amazon.com","ts":1700000000000}
```

Responses have an empty body, `Connection: close`, and no CORS headers (the Sensor's
service worker has `host_permissions` for `127.0.0.1`, so it needs none; a web page
therefore can't read anything back).

| Status | When |
| --- | --- |
| `200` | accepted — the intent is handed to the app |
| `204` | `OPTIONS` (any path) — answered so a stray preflight doesn't hang; no auth |
| `400` | bad `Content-Length`, body isn't an intent, or it fails validation |
| `401` | missing or wrong bearer token (`WWW-Authenticate: Bearer realm="spending-angel"`); body never decoded or logged |
| `404` | path isn't exactly `/intent` |
| `405` | method isn't `POST` |
| `413` | `Content-Length` over 1 MB |
| `429` | fewer than 8 s since the last *accepted* intent |
| `431` | request headers over 8 KB |

Caps: headers 8 192 bytes, body 1 000 000 bytes, `id` 128 bytes, `hostname` 1–253 bytes
(UTF-8), 10 s per connection. Logged request fields are clipped to 256 bytes.

**Pairing.** On first launch `Store` generates a token (32 random bytes → 64 lowercase
hex chars), keeps it in `UserDefaults` (`bridgeToken`), and shows it under PAIR SENSOR.
The server reads it per request and compares in constant time, so regenerating takes
effect immediately, no restart. The token is never written to the logs (at most its
last 4 characters, as `token_tail`).

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
`store.token_regenerated`, `pair.token_copied`. `intent_id` traces one catch from the
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
  Xcode, and verifiable in CI. Wrapping into a signed, notarized `.app` bundle is
  still to come (needs the Apple Developer account; not required to run locally).
- **Loopback + bearer token, not Native Messaging** — keeps the extension a plain
  MV3 package with no host manifest to install. The token is the only secret.
- **Menu-bar trigger, not a global hotkey** — a global hotkey needs Input-Monitoring
  permission; we avoid invasive permissions on purpose. No Accessibility prompt either.
- **`NSApp.setActivationPolicy(.accessory)`** is the SPM stand-in for `LSUIElement`.
- **`UserDefaults`, not Keychain** for the token — it only ever grants "make my own
  character yell at me" on this machine.

## File map

```
mac-app/
├── Package.swift
├── Sources/SpendingAngel/
│   ├── SpendingAngelApp.swift     @main · MenuBarExtra + the manual test
│   ├── AppDelegate.swift          accessory policy; owns the overlay; starts the bridge
│   ├── BridgeServer.swift         127.0.0.1:17865 · auth, framing, validation, throttle
│   ├── CatchRunner.swift          admit → record → log; shared by bridge + test
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
└── Tests/SpendingAngelTests/      Swift Testing suites (bridge parsing/auth, store dates, catch runner)
```

## Historical notes

The first milestone (M-02) was menu-item-only — "no browser, no bridge yet" — with a
`😇` emoji stand-in and a single placeholder clip copied from the old extension. The
bridge landed in M-05, the real cast art and voices in M-06, and the pairing token in
the September 2026 audit fixes.
