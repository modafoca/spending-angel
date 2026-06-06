# Spending Angel — macOS app (M-02)

The performer. A menu-bar app whose one job right now is to prove the **magic
moment**: fire a full-screen "catch" where the Angel ambushes you with a voice
line. No browser, no bridge yet — triggered from a menu item.

## Run it

**Terminal:**
```bash
cd mac-app
swift run
```
**Or Xcode:** open `mac-app/Package.swift`, pick the `SpendingAngel` scheme, Run.

A ✦ icon appears in the menu bar (no Dock icon). Click it →
**"▶︎ Test the catch (Angel)"**. The Angel slides in full-screen, says its line
at full volume, and fades after ~4s. **"Quit Spending Angel"** (⌘Q) exits.

## What it does (the catch sequence)

```
t+0.0  overlay appears; Angel animates in; clicks are intercepted
t+0.1  a random Angel catch-line plays at full volume
t+0.5  intercept releases → overlay becomes click-through
t+4.0  auto-dismiss with an exit animation
```

The 0.5s intercept is the **"get through me first"** gag — during it, a click
anywhere is swallowed (the page underneath doesn't get it). After it, the overlay
is click-through, so you proceed with your purchase; it fades on its own at 4s.

> **Dismiss-interaction note:** because the overlay goes click-through after the
> gag, there's no "click the angel to close" yet — it's the 0.5s-swallow →
> click-through → 4s-fade model, which is the real product behavior. If you want
> a manual dismiss (e.g. Esc, or click-the-character), flag it after you've felt
> it in use and we'll add it.

## Drop your real voice in

Placeholder audio lives at:
```
mac-app/Sources/SpendingAngel/Resources/voice/angel/catch-1.mp3
```
…and is just a copy of the old extension `stop.mp3` so the app makes *a* sound.

When your ElevenLabs recordings are ready, drop them in as:
```
Resources/voice/angel/catch-1.mp3
Resources/voice/angel/catch-2.mp3
Resources/voice/angel/catch-3.mp3
```
The player picks one at random. (Other characters get `voice/papi/`, `voice/wizard/`,
`voice/mom/` folders when we wire the full cast in M-06.)

## Verify (M-02 success criteria)

- [ ] ✦ icon in menu bar, no Dock icon
- [ ] Menu has "▶︎ Test the catch (Angel)" + "Quit"
- [ ] Triggering it: Angel animates in, "saving for Tokyo" bubble shows, a line plays at full volume
- [ ] During the first ~0.5s a click is swallowed; after, clicks pass through to whatever's underneath
- [ ] Auto-dismisses after ~4s with an exit animation
- [ ] Renders above a **fullscreen** Chrome/Safari window and on any Space
- [ ] No Accessibility or Input-Monitoring permission prompt

## Notes / deliberate choices

- **Swift Package, not `.xcodeproj`** — reliable to build from terminal and in
  Xcode, and verifiable in CI. Wrapping into a signed, notarized `.app` bundle is
  **M-FINAL** (needs the $99/yr Apple Developer account; not required to run locally).
- **Menu trigger, not a global hotkey** — a global hotkey needs Input-Monitoring
  permission; we avoid invasive permissions on purpose.
- **`😇` placeholder art** — real Figma cast art lands in **M-06**. The emoji is an
  obvious stand-in so it can't ship by accident.
- **`NSApp.setActivationPolicy(.accessory)`** is the SPM stand-in for `LSUIElement`.

## File map

```
mac-app/
├── Package.swift
└── Sources/SpendingAngel/
    ├── SpendingAngelApp.swift     @main · MenuBarExtra + the menu
    ├── AppDelegate.swift          accessory activation policy; owns the overlay
    ├── OverlayController.swift    the NSPanel + the catch-sequence timing
    ├── CatchView.swift            the SwiftUI performance (Angel + bubble + animation)
    ├── AudioPlayer.swift          full-volume catch-line playback
    └── Resources/voice/angel/catch-1.mp3   (placeholder)
```
