# Spending Angel

The angel on your shoulder when you're about to spend.

You tell it once what you're saving for. Then, when you're about to check out on a shopping site, a character takes over your screen, says its line out loud, and reminds you: *"Hey. Stop. You're saving for Tokyo trip."*

That's it. No tracking, no math, no dashboards. The joke does the work.

## How it's built (v0.6)

Two halves, one job each:

- **`mac-app/` — the brain and the performer.** A macOS menu-bar app (Swift Package, no Dock icon). It owns the goal, the cast, on/off and snooze, the monthly stat, and every pixel of the catch: a full-screen overlay with the character's animation, a speech bubble, and a voice line at full volume. Details in [`mac-app/README.md`](mac-app/README.md).
- **`extension/` — the Sensor.** A Chrome extension (MV3) that *only detects*. On the sites you choose it watches for a checkout page load or a real click on a buy button, and POSTs a tiny intent to the app over `http://127.0.0.1:17865`. It renders nothing and plays nothing.

The two are paired with a token the app generates and shows you; the Sensor cannot talk to the app until you paste it in. Nothing leaves your Mac.

## Install

Two halves: the app goes into `~/Applications` and starts at login; the Sensor is loaded unpacked into Chrome straight from this checkout.

1. **Install the app.**
   ```bash
   make install
   ```
   Builds a release binary, wraps it into **`~/Applications/Spending Angel.app`** (ad-hoc signed, no Dock icon), registers a login item (`~/Library/LaunchAgents/net.modafoca.spendingangel.plist`, so it is back after a reboot), starts it, and waits for the bridge to come up — it prints the version and the log path when it does. Needs Xcode or the Command Line Tools. `NO_LOGIN_ITEM=1 make install` skips the login item and just opens the app once. If you were running the bare `swift run` binary before, its goal, character, counter and pairing token are carried over on the first launch — no re-pairing.
2. **Load the Sensor.** Open `chrome://extensions`, toggle **Developer mode** on, click **Load unpacked** and pick the **`extension/` folder** (not the repo root — that's where `manifest.json` lives).
3. **Pair them.** Click the menu-bar icon → under **PAIR SENSOR** hit **COPY**. In Chrome, open the extension's **Options → Pair with the app**, paste the token, **Save**. The options page now reads "Token saved — waiting for the app to confirm (…XXXX)". Step 4 turns that into "Paired".
4. **Verify.** On the same Options page, the **App** card is the status surface: **Connection** (Connected ✓ and when), **Last request** (what the app did with it — "Character shown — Mom", or why it was skipped: off, snoozed, busy, too soon), and **Versions** (Sensor vX · App vY, with a hint when they disagree). Click **Simulate intent** there: the character should appear on screen and both lines should change. The toolbar popup shows the same lines plus per-site Watch/Stop; pin it (puzzle piece → pin "Spending Angel — Sensor") if you want it handy. "App not reachable" means the app is not running — `make install` again, or check the menu bar.

### Updating

```bash
make update
```

`git pull --ff-only`, then the install above (the running copy is stopped and replaced, settings kept). The Sensor is loaded from the checkout, so its files update with the pull — but **Chrome only picks them up after you reload the extension** at `chrome://extensions` (↻ on "Spending Angel — Sensor"). `make update` prints a reminder when anything under `extension/` changed, and the Options **Versions** row keeps saying "reload the extension" until you do.

### Uninstalling

`make uninstall` stops the app and removes it and the login item; settings and logs stay so a reinstall picks up where you left off. `PURGE=1 make uninstall` removes those too. The extension is removed from `chrome://extensions` like any other.

## Developing

Run the app from source instead of installing it:

```bash
swift run --package-path mac-app        # or: make run
```

or open `mac-app/Package.swift` in Xcode, pick the `SpendingAngel` scheme, Run. Only one copy runs at a time (the bridge port is the lock), so quit the installed one first — and don't `make install` while a `swift run` copy is up: it kills it. The dev binary keeps its settings under the `SpendingAngel` defaults domain, the bundle under `net.modafoca.spendingangel`; the bundle copies the former over once, on its first launch. `make bundle` builds the `.app` without installing it (safe at any time). `make test` runs both suites.

> **Pulling this change onto an existing install?** Reload the extension on `chrome://extensions` and pair once — older builds had no token, and the app now answers `401` without one.

## Using it

- **Goal** — type it in the dropdown under SAVING FOR. Leave it blank and the character falls back to its generic line.
- **Guardian** — pick one of the cast (The Angel, Dominican Papi, The Wizard, Asian Mom), or flip **SHAKE IT UP** to get a random one per catch.
- **Sites** — the toolbar popup handles the page you're on ("Watch this site" / "Stop watching", or "Pause on this site" in everywhere mode). **Manage all sites →** opens the options page with the full list.
- **Off / snooze** — the big button in the dropdown is the master switch; **SNOOZE 1 HR** below it is a nap. Real intents respect both; the tiny **▶ test** link fires a catch regardless so you can hear a character.

## How a catch works

1. The content script decides there's checkout intent (see below) and sends `{id, type, trigger, hostname, ts}` to the service worker. That is the whole payload — no URL, no page contents, no cart.
2. The service worker POSTs it to the app with `Authorization: Bearer <token>`. No token saved yet → it doesn't fetch at all and the popup shows "Not paired ✕".
3. The app checks the token, validates the intent, and throttles to one accepted intent per 8 s. If the app is on duty and no catch is already on screen, the overlay comes up: character animates in, the voice line plays, the first ~0.5 s of clicks are swallowed, then the overlay becomes click-through and fades after the line ends. A catch that arrives while one is playing is skipped and not counted.
4. The dropdown's stat ("I've stopped you 3 times. You're welcome.") counts only catches that were actually performed this calendar month.

Bilingual on launch — the click detector matches English and Spanish buy-button text (`add to cart`, `comprar`, `finalizar compra`, etc.).

## How it decides to trigger

Two modes, set in the options page:

- **Only the sites I list** (default, recommended). The content script is injected only on your list; nothing runs anywhere else. First run seeds the list with ~50 known shopping domains from `domains.js`.
- **Every site.** Watches everywhere except the sites you pause. Chrome asks for the `*://*/*` permission when you pick this.

Two paths, both in `content.js`:

- **Page load.** 800 ms after load, on a listed site (or, in everywhere mode, a host matching `domains.js` — suffix match, `www.` stripped).
- **Buy-button click.** A delegated capture-phase `click` listener looks at the clicked element's text — `add to cart`, `buy now`, `checkout`, `place order`, plus the Spanish equivalents. **Real user clicks only** — a click the page dispatches itself (`isTrusted === false`) is ignored.

Either way there's a 1.5-second cooldown, and the site policy is re-read from storage on every event, so pausing a site in the popup takes effect in the tabs that are already open — no reload needed.

## Storage schema

Lives in `chrome.storage.local`:

| Key | What |
| --- | --- |
| `saMode` | `"listed"` or `"everywhere"` |
| `saAllowlist` | sites watched in listed mode (seeded from `domains.js`) |
| `saBlocklist` | sites paused in everywhere mode |
| `saInitialized` | first-run seed done |
| `saLogs` | ring buffer of the last 50 structured log entries (popup → Recent events) |
| `lastIntent` | the last intent the sensor emitted |
| `bridgeOk` / `bridgeAt` / `bridgeWhy` | last app contact: ok?, when, and why not (`unpaired`, `unauthorized`, `unreachable`) |
| `lastResult` | what the app did with the last request it answered: `result` (`shown` / `skipped` / `unknown`), `reason`, `character`, `snooze_until`, `retry_in_s`, `at`, `intent_id`, `hostname`, `trigger` |
| `appVersion` | the app's version from its last answer (Options → App → Versions) |
| `saBridgeToken` | the pairing token — 64 hex chars |

The token is the only secret in the system, and it never leaves the machine: the service worker sends it to `127.0.0.1` and nowhere else, and the app never logs it.

## Security note

The bridge listens on loopback only. Every request needs the bearer token (constant-time compare); a wrong or missing one gets `401`, and nothing from the body is decoded or logged. There are no CORS headers, so a web page cannot read a response even if it manages to reach the port. Headers, body and intent `id` are capped (8 KB / 1 MB / 128 bytes), logged fields are truncated, and rejection log lines are rate-limited to one per second per event. If you suspect the token leaked, regenerate it from the PAIR SENSOR row in the dropdown and paste the new one into Options; the old one stops working immediately.

## File map

```
spending-angel/
├── extension/                 the Sensor (load this folder unpacked)
│   ├── manifest.json          MV3 config, v0.6
│   ├── background.js          service worker — per-site injection, forwards intents to the app
│   ├── content.js             runs on watched sites; emits checkout intents
│   ├── detect.js              buy-button text matching (EN/ES), visibility
│   ├── sites.js               site-list / mode / token helpers (pure)
│   ├── status.js              connection / last-result / version-hint text (pure, shared by popup + options)
│   ├── domains.js             the seed list of shopping hostnames
│   ├── log.js                 structured logging into saLogs
│   ├── popup.html / .css / .js     toolbar popup (this site, last intent, app connection + last request)
│   ├── options.html / .css / .js   pairing, the App status card, site lists
│   ├── pixel.css / fonts/ / icons/ pixel-game theme, Silkscreen font, $-halo icons
│   └── tests/                 node --test extension/tests/*.test.js
├── mac-app/                   the menu-bar app (Swift Package) — see mac-app/README.md
├── scripts/                   bundle.sh (release build → .app) · install.sh · update.sh · uninstall.sh
├── Makefile                   make install / update / uninstall / bundle / run / test
├── .github/workflows/ci.yml   Swift build+test on macOS, extension tests on Linux
└── sounds/                    legacy assets from the v0.1 extension; not used by the sensor
```

## Tests

`make test` runs both, or by hand:

```bash
# extension (Node 20+)
node --test extension/tests/*.test.js

# app (needs full Xcode — Command Line Tools alone lack the Testing module)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app
```

## Adding your own shopping domains

Two ways. For yourself: options page → **Your sites** → add a host. For the seed everyone gets on first run: edit `extension/domains.js` — append a string to the `SPENDING_ANGEL_DOMAINS` array. Use the bare hostname (`amazon.com`, not `https://www.amazon.com/`). Wildcards: prefix with `*.` (e.g. `*.myshopify.com` catches every Shopify-hosted store).

## Historical notes (v0.1)

The first cut was a single Chrome extension that did everything itself: a DOM overlay (`overlay.css`) with a cartoon angel sliding in from the corner, an `.mp3` picked from a sound dropdown in the popup, an `onboarding.html` first-run flow, and `mutedDomains` / `triggerMode` / `selectedSound` keys in storage. All of that moved into the macOS app so the character could take the whole screen and talk. The `sounds/` folder (`stop.mp3`, `bonk.mp3`, `mom-sigh.mp3`, `wah-wah.mp3`) is left over from that era; the app's voice lines live in `mac-app/Sources/SpendingAngel/Resources/voice/`.

## What's intentionally not here

- Spend tracking, target amounts, currencies — none of it. The financial logic is deliberately dumb so the comedy can carry the weight.
- Multiple goals, custom voice upload, Firefox port.
- Chrome Web Store submission and a notarized `.app`. The bundle `make install` builds is ad-hoc signed — fine on your own Mac, not something to hand to someone else yet.

## License

MIT. See `LICENSE`.
