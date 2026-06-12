# Spending Angel — Mission Briefs

Paste-ready tasks for Claude Code. Canonical context: `spending-angel-PRM.md` (v2.1) +
`spending-angel-behavior-and-voice.md`. Build order is fun-first: reshape the sensor (M-01),
then make the magic moment land (M-02). **M-01 and M-02 are independent and can run in parallel.**

---

## MISSION 01: Sensor slim-down + repo reshape

**Objective:**
Turn the shipped v0.1 extension into a thin, render-nothing **sensor** that detects checkout
intent and emits a structured event — and move it under `extension/` — without building the bridge.

**Specification:**
- **Repo move:** relocate the current root extension files into `extension/`:
  `manifest.json`, `background.js`, `content.js`, `domains.js`, `popup.html/js/css`,
  `onboarding.html/js`, `icons/`. **Delete** `overlay.css` and the `sounds/` folder from the
  extension (the app owns audio + visuals now). Leave the `.md` docs, `LICENSE`, `README.md`, and
  `Spending-Angel-Logo.ai` at repo root.
- **Strip `content.js` to detection-only.** Remove `renderOverlay`, `playSound`, the inline angel
  SVG, the speech bubble, the autoplay/`NotAllowedError` retry hack, and `escapeHtml`. **Keep**
  `hostnameMatches`, `isBuyButton`, `findBuyButtonAncestor`, `attachClickWatcher`, and the cooldown.
- **The sensor is dumb.** Remove the `enabled` / `onboarded` / `goal` / `selectedSound` / `volume` /
  `mutedDomains` gating from the trigger path — the macOS app owns all of that. The sensor just
  detects and sends. Keep the load-trigger (matched domain) + click-trigger (buy button) split.
- **Define the intent event + `sendIntent(payload)` stub.** Payload shape (no price, no scraping —
  explicitly out of scope):
  ```js
  {
    type: "checkout_intent",
    trigger: "click" | "load",
    hostname: "amazon.com",   // location.hostname, www-stripped
    ts: 1717603200000          // Date.now()
  }
  ```
  For this mission `sendIntent` does two things only: `console.log("[SA sensor]", payload)` and
  `chrome.storage.local.set({ lastIntent: payload })`. **No WebSocket yet** (that's M-05) — leave a
  `// TODO M-05: send over 127.0.0.1 WebSocket bridge` marker.
- **Debug popup.** Repurpose `popup.html/js` into a tiny status/test panel (the user-facing controls
  move to the app later): show the last detected intent (`hostname`, `trigger`, time) from
  `lastIntent`, and a **"Simulate intent"** button that calls `sendIntent` with a fake payload so the
  pipeline is testable before the app exists. Drop the goal/sound/volume/trigger/mute UI.
- **Manifest cleanup:** remove `overlay.css` from `content_scripts`; remove `sounds/*` and
  `onboarding.html` from `web_accessible_resources` (keep icons); keep `storage`; drop any permission
  the slimmed sensor + debug popup no longer use (`tabs`/`activeTab` only if the popup still reads the
  current host). Keep `host_permissions: <all_urls>` and the `domains.js + content.js` content script.

**Prerequisites:** none (independent of M-02).

**Success Criteria:**
1. Extension loads unpacked from `extension/` with zero errors.
2. `grep -ri "renderOverlay\|playSound\|new Audio\|overlay.css" extension/` returns nothing.
3. Clicking a buy button on amazon.com logs the structured `checkout_intent` payload and saves it to `lastIntent`.
4. Loading a matched domain (e.g. amazon.com) does the same with `trigger: "load"`.
5. The debug popup shows the last intent and the "Simulate intent" button works.
6. `manifest.json` no longer references `overlay.css`, `sounds/`, or unused permissions.

**Effort Estimate:** 1.5–2 hours
**Model:** Sonnet

**Agent Brief:**
```
Working directory: /Users/ianvictor/AiProjects/spending-angel
Repo: modafoca/spending-angel
Stack: Chrome extension, Manifest V3, vanilla JS (no framework).

Read first: spending-angel-PRM.md (§4 "The sensor", §5 repo structure) and
spending-angel-behavior-and-voice.md (the "Catch" moment). This repo currently holds a working
v0.1 single-character extension at the root; we are demoting it to a render-nothing SENSOR for a
macOS companion app (built separately). It must detect checkout intent and emit an event — nothing
visual, no audio.

Task:
1. Move the extension files (manifest.json, background.js, content.js, domains.js, popup.*,
   onboarding.*, icons/) into a new extension/ subfolder. Delete overlay.css and sounds/ from the
   extension. Leave root .md docs, LICENSE, README.md, and Spending-Angel-Logo.ai where they are.
2. Rewrite content.js to detection-only: keep hostnameMatches, isBuyButton, findBuyButtonAncestor,
   attachClickWatcher, and the cooldown; delete renderOverlay, playSound, the inline SVG, the
   autoplay retry hack, escapeHtml. Remove the enabled/onboarded/goal/sound/volume/mutedDomains
   gating — the sensor is dumb and always sends.
3. On a detected intent, call sendIntent(payload) where payload = { type:"checkout_intent",
   trigger:"click"|"load", hostname:<www-stripped location.hostname>, ts:Date.now() }. For now
   sendIntent only console.log's it and saves chrome.storage.local.set({ lastIntent: payload }).
   Add a "// TODO M-05: send over 127.0.0.1 WebSocket bridge" marker. Do NOT build the WebSocket.
4. Turn popup.html/js into a debug panel: show lastIntent (hostname, trigger, time) and a
   "Simulate intent" button that calls sendIntent with a fake payload. Remove the old controls.
5. Clean manifest.json: drop overlay.css from content_scripts; drop sounds/* and onboarding.html
   from web_accessible_resources; keep storage + host_permissions <all_urls> + the content script;
   remove permissions the slimmed sensor/popup don't use.

Constraints:
- Vanilla JS only, no new dependencies. Keep the existing code style (IIFE in content.js).
- Do NOT scrape prices or read page content beyond button text — privacy is a core principle.
- Do NOT build the bridge/WebSocket or touch any mac-app/ work — that's other missions.

Definition of done: the 6 Success Criteria above. Verify by loading unpacked from extension/ and
clicking a buy button on amazon.com with the console open.

When complete:
- Commit on a branch (do not push without Ian's go): "refactor: slim extension into render-nothing sensor + reshape repo"
- Report: the final extension/ tree, the exact intent payload, and any permission you removed.
```

---

## MISSION 02: The magic moment — full-screen performance overlay (fake-triggered)

**Objective:**
Stand up the macOS menu-bar app skeleton and the **performance overlay**: a menu trigger makes the
Angel enter full-screen, intercept one click, play a catch-line at full volume, and exit — proving
the core delight before any bridge or real art exists.

**Specification:**
- **New Xcode project** under `mac-app/` — SwiftUI macOS app, deployment target macOS 14+, app name
  "Spending Angel". `LSUIElement = true` (menu-bar only, no Dock icon).
- **`MenuBarExtra`** with a placeholder angel icon (SF Symbol is fine for now, e.g. a halo/`sparkles`)
  and a menu containing: **"▶︎ Test the catch (Angel)"** and **"Quit"**. The full dropdown UI is M-03 —
  do not build it here. The menu item is the M-02 trigger (no global hotkey → no Input-Monitoring
  permission).
- **`PerformanceOverlay`** — a borderless full-screen overlay window. Required AppKit setup:
  - `NSPanel`, styleMask `[.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`.
  - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
  - `level = .screenSaver`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
    so it sits above a fullscreen browser and on every Space.
  - Frame = `NSScreen.main!.frame`. Host SwiftUI content via `NSHostingView`.
  - **Click-through by default:** `ignoresMouseEvents = true`. During the **intercept window**, set it
    to `false` for ~0.5s, then back to `true`.
- **The catch sequence** (timing per the behavior doc):
  - t+0.0s: overlay shows; Angel placeholder animates **in** (slide + scale, ~0.4s); `ignoresMouseEvents = false`.
  - t+0.1s: play a random catch-line via `AVAudioPlayer` at full volume.
  - t+0.5s: `ignoresMouseEvents = true` (intercept releases).
  - t+4.0s (or on click anywhere in the overlay): exit animation (~0.4s), then close the panel.
- **A goal bubble** rendered near the Angel showing a **hardcoded** "You're saving for Tokyo." (the
  real goal comes from app state in M-03; voice stays goal-agnostic per the behavior doc).
- **Audio assets:** play from `mac-app/SpendingAngel/Assets/voice/angel/catch-1.mp3`. Ian records the
  real lines this week; until they land, **bundle a placeholder** (copy the old `sounds/stop.mp3` from
  git history, or generate a 1s silent mp3) at that path and document it. If multiple `catch-N.mp3`
  exist, pick one at random.
- **Angel art:** placeholder only (SF Symbol or a simple drawn halo). Real Figma art is M-06.

**Prerequisites:** none (independent of M-01). Xcode installed.

**Success Criteria:**
1. `mac-app/` builds and runs; the placeholder angel icon appears in the menu bar, no Dock icon.
2. The menu has "▶︎ Test the catch (Angel)" and "Quit".
3. Triggering the catch: the Angel animates in full-screen, the "saving for Tokyo" bubble shows, and a catch-line plays at full volume.
4. During the ~0.5s intercept window a click is swallowed by the overlay (clicking the desktop/browser does nothing); after it, clicks pass through to whatever is underneath.
5. The overlay auto-dismisses after ~4s, or immediately on click, with an exit animation.
6. The overlay renders above a fullscreen Chrome/Safari window and on any Space.
7. No Accessibility or Input-Monitoring permission prompt appears.

**Effort Estimate:** 4–6 hours (the NSPanel click-through-then-intercept is the genuinely tricky bit)
**Model:** Opus

**Agent Brief:**
```
Working directory: /Users/ianvictor/AiProjects/spending-angel
Repo: modafoca/spending-angel
Stack: macOS app, SwiftUI + AppKit interop, Xcode, macOS 14+ target. No third-party deps.

Read first: spending-angel-PRM.md (§4 "The performer + brain", §7 design) and
spending-angel-behavior-and-voice.md (the "Catch" moment + timing). You are building the macOS
menu-bar app's FIRST and most important piece — the full-screen "performance" where a character
ambushes the user. Build the magic moment before any networking. The companion Chrome sensor is a
separate mission; ignore it here.

Task:
Create an Xcode project under mac-app/ (app name "Spending Angel", LSUIElement = true, menu-bar only).
1. MenuBarExtra with a placeholder angel icon (SF Symbol ok) and a menu: "▶︎ Test the catch (Angel)"
   and "Quit". This menu item is the trigger — do NOT add a global hotkey (avoids Input-Monitoring
   permission). Do NOT build the full dropdown UI (that's a later mission).
2. A PerformanceOverlay built on an NSPanel:
   - styleMask [.borderless, .nonactivatingPanel], isFloatingPanel = true
   - isOpaque = false, backgroundColor = .clear, hasShadow = false
   - level = .screenSaver, collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
   - frame = NSScreen.main!.frame, SwiftUI content via NSHostingView
   - ignoresMouseEvents = true normally; flip to false during the intercept window only.
3. The catch sequence on trigger:
   t+0.0  show panel; Angel animates in (slide+scale ~0.4s); ignoresMouseEvents = false
   t+0.1  play a random catch-line via AVAudioPlayer at full volume
   t+0.5  ignoresMouseEvents = true  (intercept releases)
   t+4.0  (or on click in the overlay) exit animation ~0.4s, then close the panel
4. Render a goal bubble near the Angel: hardcode "You're saving for Tokyo." (real goal comes later;
   the audio stays goal-agnostic — never says the goal).
5. Audio: play mac-app/SpendingAngel/Assets/voice/angel/catch-1.mp3. Ian is recording real lines this
   week; bundle a placeholder at that path now (recover old sounds/stop.mp3 from git history, or a 1s
   silent mp3) and note it in a README inside mac-app/. If several catch-N.mp3 exist, pick at random.
6. Angel art is a placeholder (SF Symbol or simple drawn halo). Real art is a later mission.

Constraints:
- No third-party Swift packages. AppKit + SwiftUI + AVFoundation only.
- The app must NOT request Accessibility or Input-Monitoring permission — verify nothing prompts.
- Keep it one clean Xcode project; structure files so PerformanceOverlay, the menu, and (future)
  Store/Bridge are separable.

Definition of done: the 7 Success Criteria above. Test it over a fullscreen browser window: trigger
the catch, confirm the 0.5s click-swallow then click-through, confirm auto-dismiss, confirm no
permission prompt.

When complete:
- Commit on a branch (do not push without Ian's go): "feat: macOS menu-bar app + full-screen performance overlay (fake-triggered)"
- Report: how the NSPanel intercept-then-passthrough was implemented, the file layout, and exactly
  where Ian drops his real catch-1/2/3.mp3 when the recording session is done.
```

---

## Progress
- ✅ **M-01** — sensor slim-down + repo reshape (`feat/m01-sensor-slim`).
- ✅ **M-02** — macOS app + full-screen performance overlay (runtime-confirmed).
- ✅ **$-halo menu-bar icon** — custom template NSImage placeholder.
- ✅ **M-03** — dropdown brain (portrait, editable goal, character picker, snooze, on/off).
- ✅ **M-04** — brag stat + streak in the dropdown.
  *(M-02 onward live on `feat/m02-magic-moment`; nothing pushed.)*

## Status — 🎉 CAST COMPLETE + ALIVE (2026-06-08)
- ✅ **M-01–M-05** — sensor, macOS app + full-screen overlay, the bridge, dropdown brain, brag stat. **Loop works end to end** (real "Add to Cart" → character ambush).
- ✅ **M-06** — real Figma cast art + portraits + vector $-halo icon + restyle.
- ✅ **M-07** — pixel-game UI redesign, DONE + merged to `main` (details below).
- ✅ **Voices + animated entrances + captioned bubble — ALL DONE & pushed.** All 4 guardians animate + speak (Ian's voice via ElevenLabs) with their own entrance (Papi/Mom slide in; Angel/Wizard in place), and the speech bubble **types out the exact spoken line** matched to the audio (`voice/<id>/captions.json`).
- ⏳ **Only M-FINAL remains**: productize & launch — now broken into M-F1…M-F5 (below). Go/no-go per mission is Ian's.

---

## M-FINAL — Productize & launch (5 missions, ship-ordered)

> **Audit verdict (2026-06-12):** well built ~3.5/5, production-ready ~2/5. Architecture is sound
> (same app+extension pattern as 1Password/Grammarly); the gap is hardening, packaging, and
> store compliance — a finite checklist, not a rewrite. Full findings in the audit session.

### M-F1 — Harden the core + structured logging — ✅ DONE (2026-06-12, MOD-270)

> **As built:** all of the below, plus one bonus correctness fix found by the new tests — JS `\b`
> isn't Unicode-aware, so "pagar" matched inside "pagaré"; the button regex now uses
> Unicode-aware lookarounds. Tests = Swift Testing (18) + node:test (9), all green; CI at
> `.github/workflows/ci.yml`. Verified live: 405/404/400/413/204 rejection codes, 10s stall
> timeout, single-instance guard, and an end-to-end intent trace (`intent_id` from sensor →
> `bridge.intent_received` → `catch.performed`) with the second intent throttled at 429.

- **Objective:** make the existing app trustworthy before wrapping it. No visible changes.
- **Bridge:** validate Intent fields (`type`/`trigger` whitelisted), cap request body (1 MB),
  connection timeouts, real HTTP error codes (400/405) instead of always-200, fix the
  `NWEndpoint.Port` force-unwrap, **rate-limit intents** (throttle to ~1 catch per N seconds so
  a buggy/hostile page can't spam the overlay; log dropped intents).
- **Correctness:** fix month-key/streak date math (explicit calendar/timezone), handle missing or
  malformed resources (font, mp3, captions.json, PNGs) loudly instead of silently.
- **Structured logging (the new house standard, local-first):**
  - JSONL at `~/Library/Logs/SpendingAngel/`, daily files, rotated. Fields: `ts` (ISO-8601),
    `level`, `event`, `msg`, `intent_id`, `install_id`, plus event context (`character`,
    `hostname`, …). Queryable with `jq`/DuckDB.
  - Mirrored to `os.log` (subsystem `net.modafoca.spendingangel`) so Console.app works in dev.
  - Levels: `debug` (dev only, compiled-out/gated), `info` (normal ops: bridge up, intent
    received, catch shown), `error` (anything that breaks).
  - **`intent_id`:** UUID minted in the extension at detection time, travels in the POST payload,
    logged on both sides → end-to-end trace of every catch.
  - **`install_id`:** UUID minted on first launch (stands in for user id — single-user app).
  - Extension side: same structured shape to console + a small ring buffer in
    `chrome.storage` (last ~50 events) surfaced in the popup debug panel.
  - **Privacy rule:** logs NEVER leave the machine by default — "nothing leaves your Mac" is the
    product's selling point. Centralized aggregation is opt-in-only, later, if ever.
- **Tests + CI:** unit tests for Store date logic + bridge parsing + the button regex; GitHub
  Action that builds the package and runs them on push.
- **Deps:** none. **Cost:** $0. **Deliverable:** production-grade core, fully traceable catches.

### M-F2 — Site list control (allowlist / blacklist)
- **Objective:** replace "watch everything" with a specific, user-customizable site list. This
  also solves the Chrome Web Store `<all_urls>` review problem.
- **Scope:**
  - Curated default shopping-domain list (grow `domains.js`) + user-added sites.
  - Two modes: **Listed sites only** (default; Web-Store-friendly via
    `optional_host_permissions` granted per site) and **Everywhere** (explicit broad grant)
    with a per-site **blacklist** ("never bother me here").
  - Popup quick actions: "Watch this site" / "Pause on this site" for the current tab.
  - Full list management in the extension options page; stored in `chrome.storage.sync`.
  - Tighten detection: regex narrowed (drop bare `pagar`, marketing-copy false positives),
    button visibility check, fetch timeout (AbortController) when the app isn't running.
- **Why the extension owns it:** Chrome host-permission grants must be a user gesture *inside
  Chrome* — the Mac app can't do it. The dropdown can get read-only visibility later.
- **Deps:** M-F1 (logging makes detection tunable from real data). **Cost:** $0.

### M-F3 — Make it a real app
- **Objective:** `.app` bundle, signed + notarized, double-clickable.
- **Scope:** bundle structure + Info.plist + app icon; Developer ID signing + hardened runtime +
  notarization; launch-at-login; "Check for updates" (Sparkle or manual v1).
- **Deps:** M-F1; **Apple Developer account ($99/yr) — Ian's purchase decision gates this.**

### M-F4 — Web-Store-ready extension
- **Objective:** pass Chrome review clean.
- **Scope:** manifest narrowed per M-F2; store listing copy + screenshots; privacy disclosure
  ("processes page text locally, transmits nothing off-device"); $5 one-time dev fee.
- **Open question (decide here):** migrate localhost bridge → Chrome Native Messaging
  (reviewer-friendliest, no open port). Recommendation: ship v1 on localhost, native messaging
  as v1.1. **Deps:** M-F2, M-F3.

### M-F5 — Pairing & first-run UX
- **Objective:** the two-install onboarding moment. App-first: install app → it offers the
  extension → live green-light when paired (bridge heartbeat both sides already exists).
- **Scope:** first-run window, pairing status in dropdown + popup, landing page + launch reel.
- **Deps:** M-F3, M-F4.

---

## M-07 — Pixel-game UI redesign (4 phases) — ✅ DONE (merged to main, tip a6da6fd)

> **As built (deviations from the plan below):** font = **Silkscreen** (not Pixel Operator); shuffle
> copy = **"Shake It Up"** (not "Feeling chaotic"); grid = **4 + 4** dashed "?" slots; **ON/OFF** is the
> hero button (Test demoted to a small dev link); custom `PixelFrame` shape gives pixel-stepped corners
> on frame + inputs + buttons (avatars kept smooth); custom `PixelToggleStyle` for visible switches;
> header = $-halo icon + guardian name (two lines: name over status). **M-07d skipped** — Ian preferred
> the code frame, so no asset hand-off.

Restyle the dropdown into the pixel-game look from Ian's mockup (dark navy + cyan glow, ornate pixel
frame, pixel font). **Scope = #3:** reskin our current structure + add shuffle + coming-soon slots;
**brag stat stays inline; no Settings subpage yet.** Guardian grid = **4 characters + 4 generic "?"
coming-soon slots** (8 total, same size as the others, no names, image-swappable when added). Phased so the
first three need ZERO new assets; only phase 4 needs Ian's exported frame art.

### M-07a — Pixel foundation (font + dark/cyan theme)
- **Objective:** establish the retro look — bundle a pixel font + a dark-navy/cyan theme — on the
  existing dropdown, layout unchanged.
- **Scope:** fetch + bundle a free pixel TTF (default *Pixel Operator*, OFL — swappable), register it
  in Info; add `PixelTheme` (deep navy bg, cyan accent + glow tokens); apply font + colors to current
  dropdown text/labels/field/toggle. No external art.
- **Deps:** none. **Deliverable:** dropdown reads as a dark pixel UI immediately.

### M-07b — Shuffle + 7-slot guardian grid
- **Objective:** add shuffle mode + the coming-soon slots.
- **Scope:** `Store.shuffleMode` (persisted); "Feeling chaotic? 🎲" toggle; catch picks a random
  unlocked character when shuffle is on (no immediate repeat). Picker → 8 same-size slots: 4 chars +
  4 disabled "?" slots (generic question-mark icon, swappable PNG later), laid out 4 + 4. Brag stat stays inline.
- **Deps:** M-07a. **Deliverable:** functional shuffle + the new grid.

### M-07c — Pixel chrome in code (approximate)
- **Objective:** build the mockup's frames/borders/buttons/glow, approximated in SwiftUI.
- **Scope:** beveled goal field; the big "Spending Angel is ON" toggle button; guardian-slot rings +
  cyan glow on the active one; panel styling; header (avatar + title); a "Settings →" link stub. All
  via SwiftUI shapes/strokes/shadows + `.interpolation(.none)`. ~80% of the mockup, no external art.
- **Deps:** M-07a, M-07b. **Deliverable:** looks like the mockup, code-only.

### M-07d — Authentic frame art (9-slice swap)
- **Objective:** swap code-approximated borders for Ian's real pixel frame art.
- **Scope:** Ian exports the ornate frame pieces as **9-slice PNGs** (outer frame, field border,
  button frame, slot ring); wire via `resizable(capInsets:resizingMode:) + .interpolation(.none)`.
- **Deps:** M-07c **+ Ian's exported assets** ← the only phase that needs his art.
  **Deliverable:** pixel-perfect match to the mockup.

### M-07e *(optional, deferred per #3)* — Settings subpage
If wanted later: move sound/trigger/snooze (and a future Vice List) behind the "Settings →" link.
