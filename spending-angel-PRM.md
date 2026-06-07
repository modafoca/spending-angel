# PRM — SPENDING ANGEL

**Version:** v2.2
**Date:** 2026-06-05
**Owner:** Ian Víctor (MODAFOCA Studio)
**Repo:** `modafoca/spending-angel`
**Status:** Active — building. Single native product (sensor extension + macOS menu-bar app).

> **Single source of truth.** Supersedes `spending-angel-v1.5-prm.md` (a *mission brief*, not a
> PRM). Behavior + voice detail lives in `spending-angel-behavior-and-voice.md`. Design frames
> live in `spending-angel-design-spec.md`. This doc governs.

---

## Changelog

- **v2.2 (2026-06-05)** — Formalized the **UI design pass** as an explicit milestone (M-06 →
  "Design pass + real assets") instead of leaving the app's visual language implicit. Decoupled
  design *work* (Ian, in Figma, **anytime**) from design *implementation* (scheduled at M-06, after
  M-04/M-05 so every surface + state exists first — design against reality, not hypotheticals).
  Build history this session: M-01 (sensor) → M-02 (overlay, runtime-confirmed) → $-halo icon →
  M-03 (dropdown) → M-04 (brag stat + streak). UI is functional-placeholder (default SwiftUI +
  emoji) **on purpose** until M-06.
- **v2.1 (2026-06-05)** — Ian's reframe: **this is a personal "build it because it's fun" project,
  not a startup.** Consequences:
  - **Killed the loop-proof gate** (no user testing — Ian is the user, he's sold).
  - **Collapsed to a single native build.** Skip the browser-overlay cast entirely; the extension
    is born as a thin sensor, the macOS menu-bar app is the whole show. No building it twice.
  - **Parked the launch machinery** as the final, *optional* mission with a go/no-go after the app
    works.
  - **Locked the interactions:** one-click intercept at checkout; full-screen performance overlay;
    menu-bar dropdown brain with a character **brag stat + streak** (no dollars, no scraping).
  - **Locked voices:** Ian records, ElevenLabs transforms, lean scope (catch-line only, ~12 lines),
    goal-agnostic.
  - Cut the animated menu-bar icon and the "mood ring" icon (too much / no menu-bar room).
  - Cast art, logo, and brand are **done in Figma**.
- **v2.0 (2026-06-05)** — Pivot chapter; reconciled handoff doc vs. repo; two-milestone roadmap with
  a loop-proof gate (now removed in v2.1).

---

## 0. Vision

Spending Angel is a **character that lives in your Mac's menu bar and ambushes you at the moment of
an impulse buy** — not with a generic alarm, but by reminding you, in a voice with real personality,
of the specific thing you're saving for. The financial logic is deliberately dumb (one goal string,
no tracking) so the **comedy and the character carry it.** The cast — Angel, Dominican Papi, Wizard,
Asian Mom — is the moat: nothing in the "stop spending" category has personality or cultural
specificity. Built first and foremost **because it's fun to make and fun to use** — and because it'll
make a funny reel. A real product launch is a switch we can flip later, not the reason it exists.

---

## 1. Problem & opportunity

- **Problem:** impulse spending happens in a half-second of intent. Budget apps intervene after the
  money's gone. Nothing funny, personal, and *present at the moment of intent* exists.
- **Wedge / the fun:** make the intervention a *character you chose*, who knows your goal, who is
  funnier than the urge, and who has a real **body** — full-screen, full-volume, unrestricted by the
  browser. The browser only ever *sees*; the Mac app *performs*.
- **Why native:** the browser can't do this well. Autoplay policy blocks cold sound
  ([content.js:46-61](content.js:46) is a live hack around it), and a DOM popup caps the
  performance. The Mac app removes both ceilings.

---

## 2. Audience & users

- **User #1: Ian.** This is built for himself, by himself. If it makes him laugh and stops him
  buying junk, it's a success.
- **Reel audience:** MODAFOCA's IG — DR-local (Spanish-first) + global creative/dev. The Dominican
  Papi and the Asian Mom are the shareable, "which one are you?" moments.
- **macOS-only.** Accepted — quality over reach. A product launch (if it happens) inherits this.

---

## 3. Scope

### In scope (the build)
- **Sensor extension** (Chrome, MV3): detect checkout/cart intent, ping the app. Renders nothing.
- **macOS menu-bar app** (SwiftUI `MenuBarExtra`): the performer + brain. Two surfaces —
  (a) the dropdown (controls + brag stat), (b) the full-screen performance overlay.
- **The bridge:** localhost WebSocket for v0 (Native Messaging is the ship-path — §11 Q1).
- **The cast:** four characters, art done in Figma, voiced by Ian via ElevenLabs (lean).

### Out of scope
- Spend-tracking math, real dollar amounts, price-scraping — **never / explicitly rejected.**
- Browser-overlay cast (the old v1.5 "cast in the browser") — skipped; we go native.
- Windows/Linux performers, Firefox/Safari sensors — post-v0, only if it ever ships as a product.
- Accessibility-based browser reading by the Mac app — the app stays **blind on purpose**.
- Animated menu-bar icon, "mood ring" icon — cut.

### What this isn't
- **Not a budgeting app.** Tracks nothing, sums nothing, charts nothing. It interrupts.
- **Not a browser product.** The browser is demoted to a sensor; the body is on the desktop.
- **Not a Mac app that spies on your browser.** It never reads the browser via Accessibility —
  the extension feeds it. That blindness is the privacy + permissions win.
- **Not a SaaS.** No accounts, no server, no analytics. Everything is on-device.
- **Not (yet) a launch.** Distribution is a parked final mission, flipped on only if Ian decides.

---

## 4. Architecture & stack

### The sensor (Chrome extension, MV3)
- Slimmed from the shipped v0.1: keep the detection (`domains.js` page-load match + buy-button
  regex on click, with cooldown), **drop the overlay + audio.** On intent, emit a structured event
  over the bridge. `curl`/console-testable payload.
- **Click-trigger is the reliable path** (user gesture); the old page-load autoplay problem is now
  the *app's* job, where there's no gating.

### The performer + brain (macOS menu-bar app, SwiftUI)
- `MenuBarExtra` for the static menu-bar mark + the dropdown.
- **Performance overlay:** borderless, always-on-top, normally **click-through** `NSPanel` —
  except it **intercepts one click for ~0.5s** at the catch moment ("get through me first"), then
  releases. Full-screen, unrestricted audio (plays a random catch-line via `AVAudioPlayer`).
- **State** (local, e.g. `UserDefaults`/JSON): goal string, active character, intercept count,
  streak (days since last "slip"), snooze-until, enabled.
- **No Accessibility permission.** App is blind; sensor feeds it.

### The bridge
- **v0:** app runs a `127.0.0.1` WebSocket server; extension connects on checkout, sends the event.
- **Ship:** likely Chrome Native Messaging (§11 Q1). Verify Chrome local-network policy before any
  distributed build.

---

## 5. Repo structure (target monorepo)

```
spending-angel/
├── extension/                 ← the sensor (slimmed from v0.1; detection only, no overlay/audio)
│   ├── manifest.json, background.js, content.js, domains.js
│   └── bridge-client.js       ← NEW — opens WS to the app, sends intent events
├── mac-app/                   ← NEW — SwiftUI MenuBarExtra (own Xcode project)
│   ├── SpendingAngel/
│   │   ├── MenuBarView.swift          (the dropdown: portrait, goal, brag+streak, snooze, off)
│   │   ├── PerformanceOverlay.swift   (borderless NSPanel, intercept, entrance/exit, audio)
│   │   ├── BridgeServer.swift         (127.0.0.1 WebSocket)
│   │   ├── Store.swift                (goal, character, count, streak, snooze)
│   │   └── Characters.swift           (roster config — mirrors the cast)
│   └── Assets/                ← cast art (from Figma) + assets/voice/<character>/catch-{1,2,3}.mp3
├── docs/                      ← (parked) marketing site, only if launch mission fires
├── spending-angel-PRM.md                  ← THIS doc (canonical)
├── spending-angel-behavior-and-voice.md   ← behavior spec + voice script
├── spending-angel-design-spec.md          ← Figma frame/dimension spec
└── spending-angel-v1.5-prm.md             ← old browser-cast mission brief (historical input)
```
**One repo** through v0. The current flat extension files get moved under `extension/` in M-01.

---

## 6. Domain content — the Cast

Locked roster. Art **done in Figma**. Voices = Ian + ElevenLabs (lean: catch-line only, 3 variations
each, goal-agnostic). Full lines + written UI copy in `spending-angel-behavior-and-voice.md`.

| Character | Voice / gag | Non-negotiable |
|-----------|-------------|----------------|
| **The Angel** (default, brand anchor) | Gentle, exasperated. "Hey. Stop. Don't do that." | Soft-edged; silhouette = the menu-bar mark |
| **Dominican Papi** | Warm, scolding, bilingual. "Ay, no, mi amor." | Specific Dominican uncle, not generic |
| **The Wizard** | Theatrical baritone. "You shall not pass... checkout." | Gravitas vs. cart; don't make him cute |
| **Asian Mom** | Tiger-mom guilt. "Aiyah!" | **The slipper is mandatory** (flies in first) |

- **Data model (locked, dumb):** single `goal` **string**. No amount, no currency, no progress.
- **The stat (locked):** the character **brags** the one honest number the app knows — how many
  times it caught you — anchored to the goal, plus a **streak** ("days since you almost slipped").
  No dollars, no scraping, no estimating. Written copy, per character. Not voiced.
- **Goal is text, not voice:** pre-recorded lines are goal-agnostic; the goal shows as overlay text.

---

## 7. Design system

> **The dedicated UI design pass is M-06** (§9). Until then the app's own interface is
> functional placeholder — default SwiftUI chrome + emoji stand-ins — **by design**, so we don't
> polish surfaces that are still moving. Design *work* (Ian, in Figma) can happen anytime; M-06 is
> where it gets implemented alongside the real cast art + voices.

- **North star:** "sticker pack, not productivity app." Brand + logo + cast **done in Figma**;
  brand color locked there.
- **Menu-bar dropdown (the brain):** static mark → portrait · `Saving for: {goal}` · brag + streak ·
  `Snooze 1hr` · `Off`. No animation, no mood ring.
  ```
  ┌──────────────────────────────┐
  │  [portrait]   Papi  ▾         │
  │  Saving for:  ✎ Tokyo         │
  │  ──────────────────────────  │
  │   "Te he cuidado 12 veces     │   ← brag (per character)
  │        pa' Tokyo" ✨          │
  │   4 días sin resbalar         │   ← streak
  │  ──────────────────────────  │
  │   😴 Snooze 1 hr      ⏻ Off   │
  └──────────────────────────────┘
  ```
- **Performance overlay (the reel):** full-screen, entrance gag → one-click intercept (~0.5s) →
  catch-line audio → goal-text bubble → exit gag. Sequence + timing in the behavior doc.
- **Animation earns its way in here** (unlike the dead browser overlay). The "plane across the
  screen" reference = character entrances that traverse.

---

## 8. Team & roles

| Who | Owns |
|-----|------|
| **Ian Víctor** | Cast art (done), logo/brand (done), voices (record + ElevenLabs), goal/feel, final call |
| **Claude Code** | Sensor slim-down, bridge, SwiftUI app, overlay, dropdown, stat logic |
| **claude.ai** | Architecture/decisions thinking partner |

Voices: **resolved** — Ian records, ElevenLabs transforms, he acts them.

---

## 9. Missions (build sequence)

Full briefs written at kickoff (house format). **Build the magic moment first** — the delight runs
on a fake trigger before any plumbing, so the build itself is fun. Sequence:

- **M-01 — Repo reshape + sensor slim-down.** Move extension files under `extension/`. Strip overlay
  + audio from `content.js`; keep detection; add a stub that logs the intent event.
- **M-02 — The magic moment (fake-triggered).** SwiftUI app skeleton + the full-screen
  `PerformanceOverlay`: on a global hotkey, Angel enters full-screen, intercepts one click for
  ~0.5s, plays a catch-line, shows a goal bubble, exits. **No bridge yet.** This is the day-one "the
  joke landed" milestone.
- **M-03 — The dropdown (brain).** `MenuBarExtra`: portrait, editable goal, character picker,
  snooze, off. Wire `Store.swift`.
- **M-04 — The brag stat + streak.** Track intercept count + streak; render the per-character brag +
  streak copy in the dropdown.
- **M-05 — The bridge.** `127.0.0.1` WebSocket server in the app + `bridge-client.js` in the
  extension. Real checkout intent → real catch. The loop is closed end-to-end on Ian's Mac.
- **M-06 — Design pass + real assets.** The "make it look like the brand, not default SwiftUI"
  milestone. Two halves, done together because they share design tokens:
  - **(a) Visual language:** lock brand color tokens + typography (the sticker/rounded face vs.
    system); restyle the **dropdown chrome** (cream/navy sticker aesthetic, not stock macOS) and the
    **overlay composition** (character placement, speech-bubble style, entrance/exit choreography);
    final **$-halo icon** from Figma; light + dark.
  - **(b) Real assets:** swap the emoji placeholders for the four **Figma characters**; drop Ian's
    **ElevenLabs catch-lines** into each `voice/<character>/` folder; wire per-character entrance/exit
    gags (the slipper flies in first, etc.).
  - **Design work is Ian's clock** (Figma, anytime); this milestone is the *implementation* of it.
- **M-FINAL (parked, optional) — Productize & launch.** Only if Ian flips the switch. See §10.

### What "M-FINAL" entails (so it's ready on the shelf)
Sign + notarize the Mac app (Apple Developer, **$99/yr**); ship the sensor extension to the Chrome
Web Store (**$5**); a one-page `docs/` site; decide pricing/distribution; build the two-install
**pairing/onboarding** UX; migrate the bridge to Native Messaging; cut the launch reel + IG push.
None of it blocks the build — it's a checklist pulled off the shelf on a go/no-go.

---

## 10. Success criteria

No gate, no KPIs to clear — it's a personal build. "Done and good" =

- The full loop runs on Ian's Mac: real checkout click → character ambush + voice, **reliably, zero
  autoplay failures.**
- The one-click intercept feels like a tiny boss fight, not a notification.
- It **makes Ian laugh** the first several times — and yields at least one **funny reel.**
- The dropdown's brag + streak is the kind of thing he opens just to see.

**Go/no-go for M-FINAL:** after v0 works, does Ian want this to be a product? If yes → M-FINAL. If
no → it stays his personal toy (and the reel). Either is a win.

---

## 11. Open questions

> **Q1 — Bridge: localhost WebSocket vs. Native Messaging?**
> - **v0 = localhost HTTP POST** (decided, M-05): the sensor's service worker POSTs intents to
>   `http://127.0.0.1:17865/intent`; the app runs a tiny dep-free `NWListener` HTTP server bound to
>   loopback (no firewall prompt). A WebSocket was the original plan but is overkill for a one-way,
>   fire-and-forget signal and costs a lot of hand-rolled framing. App owns its lifecycle; `curl`-testable.
> - Native Messaging: official, cleaner for distribution, but fights the always-running app (needs a
>   relay). **Gate:** only at M-FINAL, and **verify current Chrome local-network policy** before
>   shipping localhost to anyone but Ian.

> **Q2 — Intercept default-on, or a setting?**
> - One-click intercept is locked as the behavior. Open: is it always on, or toggleable if it ever
>   annoys Ian in real use? **Gate:** after M-05, from real daily use. Default on for now.

> **Q3 — Onboarding direction for the two-part install — DECIDED: app-first.**
> Neither half can silently install the other (Chrome blocks native-driven extension installs
> short of invasive enterprise policy; a sandboxed extension can't install native software), so
> both directions reduce to a guided one-click handoff. **The macOS app is the front door** — it
> delivers value alone (character + "test the catch" + goal + stat) while the extension is inert
> alone. Flow: download app → instantly usable → app nudges "give me eyes, add the browser sensor"
> → app detects the bridge connection and confirms "paired." If the extension is discovered first
> (Web Store search), its only job is a one-screen "get the Spending Angel app" redirect. Mirrors
> the build order (M-02 app-solo → M-05 add sensor).
> **Gate:** only the *direction* is locked now; the polished pairing/onboarding UX stays in
> M-FINAL. v0 hardcodes local pairing on Ian's machine.

> **Pending from Ian:** the "small plane crossing the screen" reference — informs entrance motion
> design (overlay only). Not blocking.

---

## 12. Cost model

Near-zero to build. Costs only appear if M-FINAL fires:
- **Apple Developer Program: $99/yr** — to sign + notarize for distribution (NOT needed for v0 on
  Ian's own Mac).
- **Chrome Web Store: $5** one-time.
- **Voice talent: $0** — Ian records + ElevenLabs (his existing tooling).
- **Revenue:** none assumed. Reputation / IG / personal-use play.

---

## 13. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| **Over-engineering a toy** — Swift app balloons. | Build magic-moment-first; v0 is one character + fake trigger before any plumbing. Lean voice scope. Launch parked. |
| **Browser autoplay** (the old pain). | Solved by the architecture — audio moves to the Mac app, no gating. Sensor only detects. |
| **Chrome tightens local-network access**, breaking the bridge for distributed users. | Localhost = Ian's machine only. Native Messaging fallback at M-FINAL (Q1). |
| **Intercept annoys Ian in daily use.** | Q2 — make it a toggle if real use demands; cheap to add. |
| **macOS overlay fiddliness** (borderless, click-through, always-on-top, intercept-one-click). | The one genuinely tricky bit — isolate it in M-02 and nail it before building on top. |
| **Version drift** (`manifest.json` 0.1.0 vs docs). | This PRM's mission numbering (M-01…) is canonical; bump manifest at M-FINAL. |

---

## 14. Timeline & gates

Milestone-gated, not calendar. Single build → one optional fork at the end.

- **M-01 → M-06:** build the native product (sensor + app + bridge + cast). Internal checkpoint at
  **M-02** (does the magic moment land on Ian's screen?) — if the overlay+intercept+audio feels
  right, everything else is downhill.
- **Go/no-go → M-FINAL:** after v0 works, Ian decides product-or-toy. Productize only on "yes."

---

## 15. Appendix — inputs & prior art

- **`spending-angel-behavior-and-voice.md`** — the behavior spec + the 12-line voice script + UI copy.
- **`spending-angel-design-spec.md`** — Figma frames/dimensions for cast, UI, assets.
- **`spending-angel-v1.5-prm.md`** — old browser-cast mission brief (historical; the launch-track
  detail it contains feeds M-FINAL if it ever fires).
- **`spending-angel-mission-brief.md`** — original v0.1 brief (what shipped as the current extension).
- **Code ground truth:** [content.js](content.js), [popup.js](popup.js),
  [manifest.json](manifest.json) (`0.1.0`).
- **Pivot trail:** 2026-06-05 claude.ai handoff + this session's reframe (personal/fun build).
