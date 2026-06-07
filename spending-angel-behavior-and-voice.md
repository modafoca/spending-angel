# Spending Angel — Behavior & Voice Script (v0)

**Companion to** `spending-angel-PRM.md` (v2.1). Defines exactly **what happens** in the app
and **what Ian records** for the voices. Read this before the ElevenLabs session.

---

## The golden rule for the voice session

**Record goal-agnostic lines.** The savings goal ("Tokyo") is user-typed text that changes, so
it can NOT be baked into pre-recorded audio. The **voice** is the generic scold; the **goal**
appears as **text** in the overlay bubble. So when you record: never name the goal out loud.

- Voice (recorded): *"Ay, no, mi amor. ¿Tú 'tá loco?"*
- Bubble (dynamic text, on screen): *"You're saving for Tokyo."*

---

## The two surfaces

**① Menu-bar dropdown — the brain.** Static angel mark in the bar. Tap → small window:
portrait · `Saving for: [goal]` (editable) · the brag stat + streak · `Snooze 1hr` · `Off`.
No animation, no mood ring.

**② Full-screen overlay — the performance.** Borderless, always-on-top. Where the character
actually appears, intercepts, and yells. Unrestricted audio.

---

## The moments (what actually happens)

| # | Moment | What happens | Voiced? |
|---|--------|--------------|---------|
| 1 | **Idle** | Static angel mark in menu bar. | — |
| 2 | **Catch** | Browser sensor detects checkout/cart intent → pings app → character **enters** full-screen (entrance gag) → overlay **intercepts one click for ~0.5s** ("get through me first") → **catch-line plays** (random of 3) → overlay shows goal text in a bubble → auto-exit after ~4s or on click (exit gag). | ✅ catch-line |
| 3 | **Dropdown open** | The brain: portrait, goal, brag stat + streak, snooze, off. | — (written copy) |
| 4 | **Snooze / Off** | Character goes off duty. Dropdown shows a sleeping/off state with a written sass line. | — (written copy) |

### Catch sequence timing (for the build)
```
t+0.0s   intent detected → overlay mounts, character entrance (~0.4s)
t+0.0s   page click intercepted (overlay NOT click-through)
t+0.1s   catch-line audio plays (random of the 3 variations)
t+0.5s   intercept releases (page clickable again)
t+4.0s   auto-exit (or earlier on click) → exit gag (~0.4s) → overlay unmounts
```

---

## VOICE LINES TO RECORD (lean v0 — 12 total)

Only the **catch-line** is voiced. 3 variations per character so it doesn't get stale.
~2–4 seconds each, fully in character. Record in your voice, transform in ElevenLabs.
**Goal-agnostic — never name the goal.**

### The Angel — gentle, exasperated, soft
1. "Hey. Stop. Don't do that."
2. "Mmm... no. We don't need it."
3. "Put it down. Walk away."

### Dominican Papi — warm, scolding, bilingual, Dominican uncle
1. "Ay, no, mi amor. ¿Tú 'tá loco?"
2. "Diablo, otra vez con lo mismo. Suéltalo."
3. "No, no, no. Eso no se hace, mijo."

### The Wizard — theatrical baritone, gravitas vs. cart
1. "You shall not pass... checkout."
2. "Stay your hand, mortal. The coin purse must endure."
3. "I sense a great disturbance. You are about to do something foolish."

### Asian Mom — tiger-mom guilt, the slipper
1. "Aiyah! You have one already!"
2. "You don't need this. Put it back. Now."
3. "I didn't raise you to click 'Buy Now.'" *(+ slipper whoosh SFX)*

**Deliverable filenames:** `assets/voice/<character>/catch-1.mp3` … `catch-3.mp3`
**SFX to source separately (not voice):** slipper-whoosh, optional staff-thud (Wizard).

---

## WRITTEN COPY (not voiced — lives in the UI)

The dropdown and bubble carry personality in **text**, so they cost no recording time. `{goal}`
and `{n}`/`{days}` are filled in at runtime. Write one of each per character.

### Overlay goal bubble (shown during the catch, under/near the character)
- All characters: **"You're saving for {goal}."** *(optional per-character tint later)*

### Dropdown brag stat — count + goal, in character
- **Angel:** "I've stopped you {n} times. You're welcome."
- **Papi:** "Te he cuidado {n} veces pa' {goal}, mi amor."
- **Wizard:** "{n} times I have stayed your hand. {goal} thanks you."
- **Mom:** "{n} times. *Twelve.* And not one thank you." *(use literal {n})*

### Dropdown streak line — "days since you almost slipped"
- **Angel:** "{days} days clean. Proud of you."
- **Papi:** "{days} días sin resbalar. Así me gusta."
- **Wizard:** "{days} days the realm has held. Do not falter now."
- **Mom:** "{days} days good. Don't ruin it."

### Snooze / Off sass (shown when you mute or snooze them)
- **Angel:** "Fine. I'll look away. 😇"
- **Papi:** "Ta bien. Después no vengas llorando."
- **Wizard:** "I shall avert my gaze. Your treasury be upon you."
- **Mom:** "Okay. Do what you want. I'm not even mad." *(she is mad)*

---

## VISUAL GAGS (Ian's Figma / animation — not voice)

Characters already drawn in Figma. These are entrance/exit notes for the overlay:

| Character | Entrance | Exit |
|-----------|----------|------|
| Angel | floats in on cloud, halo bobbing | poofs out |
| Papi | leans in from the side of frame | shrugs, walks off |
| Wizard | sweeps in, staff first, robes billowing | vanishes in smoke |
| Mom | **slipper flies in first**, then she appears | throws the slipper, storms out |

(The "plane crossing the screen" reference Ian reacted to lives here — entrances can traverse.)

---

## What this gives you for the ElevenLabs session

Record **12 short lines** (3 × 4 characters), goal-agnostic, in character. That's the whole
voice scope for v0. Everything else (goal, brag, streak, sass) is text. Add an exit-line and
snooze-voice pass later only if the loop earns it.
