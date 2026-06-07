# Spending Angel — Design Spec v1.5

> Companion to `PRM-v1.5.md`. Every frame, dimension, and design note needed for the v1.5 launch. Set up a Figma file with these pages and frames, or work directly from this doc.

---

## How to use this

1. Create a Figma file. Name it **Spending Angel — Design Workspace**.
2. Set up 7 pages in this order: 📋 Read Me · 🎭 Cast · 🪟 Extension UI · 🎨 Icons · 🛒 Web Store Assets · 🌐 Marketing Site · 📱 Social Launch.
3. On each page, create the frames listed below at the dimensions specified.
4. Pick a visual direction (pixel / edge perch / cloud-window) BEFORE drawing characters. Direction must hold up across all four characters, not just one.

---

## Workflow

1. Pick a visual direction on the Cast page. **Direction C — custom container per character — is recommended** for max personality differentiation and IG-shareability.
2. Sketch all four characters in that direction. Iterate until the cast feels coherent as a system.
3. Move to Extension UI — design the popup states with the active character.
4. Icons, Web Store, Marketing, and Social can run in parallel once the cast is locked.
5. The slipper-throw frames for Mom are the single most fragile thing in v1.5. Design them deliberately — the whoosh sound has to sync to the visual.

---

## Reminders

- The cast is the moat. No competitor has personality. Push character + cultural specificity hard.
- Every visual that ships is also IG content. Design for the screenshot, not just the function.
- Avoid the SaaS aesthetic. This should look like a sticker pack, not a productivity app.
- Brand color TBD — pick during design morning, lock it before touching the marketing site.

---

## 🎭 PAGE 1 — Cast

### Direction picker (decide first)

Three visual directions. Pick one before drawing.

**A · Pixel sprites** — Frame-animated. Comedy via low-fi consistency. Cheapest to produce at quality.

**B · Edge perch** — Each character perches on / inhabits a window-shaped container. Container shape can shift per character (Angel on cloud, Papi on porch railing, Wizard on tower stone, Mom in doorway).

**C · Custom container per character (RECOMMENDED)** — Each character lives inside a custom-shaped window (cloud, colmado window, ancient scroll, kitchen doorway). Maximum personality differentiation. Most IG-shareable.

### Frames on this page

**Angel — Working Canvas** · 1000 × 1000

DEFAULT GUARDIAN. The brand anchor.

- Voice: gentle, exasperated. "Hey. Stop. Don't do that."
- Soft-edged, warm
- Halo (slightly crooked = personality)
- Slightly judgy expression
- Looney Tunes shoulder-angel energy, NOT corporate iOS notification
- Must read at small sizes (popup picker is ~64px)
- The Angel must work as the brand mark — its silhouette becomes the extension icon

**Papi — Working Canvas** · 1000 × 1000

THE IG SIGNATURE. The character that gets sent to group chats.

- Voice: warm, scolding, bilingual. "Ay, no, mi amor." / "¿Tú estás loco?"
- Older Dominican uncle energy — gold chain optional but encouraged
- Slight belly, expressive hands
- Maybe a guayabera or polo, depending on direction
- Container could be a colmado window if going Direction C
- Lean in fully — generic "Latino dad" is a miss. Specific Dominican Papi is the win.

**Wizard — Working Canvas** · 1000 × 1000

THE WILDCARD. Comedy via gravitas-vs-cart absurdism.

- Voice: theatrical baritone. "You shall not pass... checkout." Dramatic incantation hum.
- Full fantasy regalia: robes, staff, pointed hat or hood
- The contrast IS the joke — epic posture, mundane subject
- Container option (Direction C): ancient scroll or rune-carved stone arch
- Optional accessory: a glowing staff that thuds (synced to sound)
- Resist the temptation to make him cute. Wizard works because he's serious about a stupid thing.

**Mom — Working Canvas** · 1000 × 1000

THE VIRAL POST. The slipper IS the gag — non-negotiable.

- Voice: tiger-mom guilt. "Aiyah!" / "You have one already!" Tongue click.
- Static character. Slipper raised mid-threat OR caught mid-throw — your call, but no animation needed. The pose is the joke.
- Slipper must read clearly even at small sizes (popup picker is ~64px)
- Container option (Direction C): kitchen doorway
- Expression: equal parts exasperated and weaponized
- The strongest version is whichever reads instantly as "this person is about to / has thrown a slipper at you" without context.

**Cast Group Shot** · 1280 × 800

ALL FOUR CHARACTERS TOGETHER. Used as:

- Marketing site hero banner
- IG launch Post 1 (carousel slide 1)
- Web Store promo tile crop source
- Gumroad cover image

Composition tips:

- Angel anchors center or left (default character = visual default)
- Papi + Mom flank — these are the IG-shareable ones, give them strong presence
- Wizard adds vertical interest — taller silhouette, staff up
- Leave headroom at top for potential overlay text in social cuts

---

## 🪟 PAGE 2 — Extension UI

Chrome popups have a max width around 800px but conventional design is 320–400. Using **360 × 600** for breathing room without feeling oversized.

### Popup states

**Popup — Default** · 360 × 600

Main view when users tap the toolbar icon. Must contain (top to bottom):

- Active character preview at top (~80px square)
- Goal field — "Saving for: ___" editable inline
- Character picker — 4 avatars in a row, active one highlighted, plus "coming soon" Bear + Ex slots
- Shuffle toggle — "🎲 Feeling chaotic?"
- Big ON/OFF master toggle ("Angel is sleeping 😴" when off)
- "Settings" link → opens secondary view

⚠️ The popup is getting dense. Two-view structure recommended: this "Today" view + a separate "Settings" subpage for sounds/trigger/vices/mute list.

**Popup — Settings** · 360 × 600

Secondary view, accessed from the Settings link. Contains:

- Sound dropdown for active character (4 sound options)
- Volume slider
- Trigger mode radio: page load / button click / both
- "Mute this site" button (visible when on a matched site)
- Vice List section (collapsible) — "My Vices · Sites I can't be trusted on" + add field + list with × removers
- Footer: version number, link to GitHub
- Back arrow to return to default view

**Popup — Goal Edit** · 360 × 600

Micro state when user taps the goal field to edit:

- Text input active, cursor blinking
- Suggestion chips below input (optional): "Trip", "Emergency fund", "New gear", "Wedding", "Down payment"
- Save / cancel buttons

Suggestion chips are bonus — they give first-time users something to grab without thinking.

### Onboarding flow (first install)

Two screens, both inside the popup. Skippable at each step. Defaults to Angel + no shuffle if user skips Step 2.

**Onboarding — Step 1 / Goal** · 360 × 600

- Welcome line: "I'm your Spending Guardian." (or whatever feels less corporate)
- Sub-line: "I keep an eye on your wallet."
- Single text field: "What are you saving for?"
- Continue button → Step 2
- Skip link (small, bottom)

Design cue: warm, conspiratorial. NOT product-onboarding-checklist energy. This is the angel introducing themselves, not a SaaS welcome wizard.

**Onboarding — Step 2 / Character pick** · 360 × 600

The "which one are you?" moment. This is where IG content is born.

- Headline: "Pick your guardian."
- Sub-line: "You can change them anytime."
- 4 character cards (stacked or 2×2 grid):
   - Character art
   - Name
   - One-line tagline
   - Tap-to-hear-them mini play button
- Below: "Or shuffle them all 🎲" toggle
- "Done — I've got your back." button → marks `onboarded:true`

The play-to-preview is critical. People decide on character via voice as much as visual.

### On-page overlay

Transparent background — only the character + container has visual weight.

**Overlay — Default character** · 480 × 360 (transparent canvas)

- Character figure (~200 × 200 nominal)
- Container shape (cloud / scroll / window — depending on direction)
- Speech bubble with goal text: "Hey. Stop. You're saving for [Tokyo trip]."
- Subtle dismiss × in corner (small, doesn't fight the character)
- Position guidance: top-right of viewport, with slight rotation (-3°) so it reads as a sticker
- Auto-dismiss after 4s OR on click. Animation: slide-in with bounce on the wrapper, speech bubble pops 100ms after. (No character animation — the wrapper moves, the character stays still inside it.)
- Design all four characters in this frame — duplicate and swap to see how each reads.

---

## 🎨 PAGE 3 — Icons

Three sizes required by Chrome. The 16px icon is the hardest — it has to read in the toolbar at favicon size.

**Test rule: if you can't tell what it is at 16px, it doesn't ship.**

**Icon — 128px** · 128 × 128

Design here first. Source of truth — others are simplified down from this. Used in Web Store listing, extensions page, popup header.

- Angel-led — the brand anchor
- Halo + simplified body silhouette
- Single accent color background (matching brand color TBD)
- Avoid fine detail — even 128 isn't huge

**Icon — 48px** · 48 × 48

Simplify from 128. Drop fine details — eyes, halo crookedness, etc. Used in chrome://extensions.

If the 128 has 5 visual elements, the 48 should have 3. Test by squinting.

**Icon — 16px** · 16 × 16

Pixel art at this scale. Used in Chrome toolbar (where users see it most).

Reduce to silhouette + ONE accent. A halo over a circle is enough — let the brand color do the recognition work.

⚠️ Don't try to fit the full angel here. It will read as a smudge. Stick to: silhouette + halo + brand color.

**Icon — 128 mono** · 128 × 128 (optional bonus)

Monochrome version for use in:

- README header
- Marketing site favicon
- Any context where the brand color clashes (white-on-black IG story, etc.)

Single color, no background. Design in black on transparent + provide inverse (white on transparent) as separate asset.

---

## 🛒 PAGE 4 — Web Store Assets

Required + recommended assets for the Chrome Web Store listing. Screenshots are the most important — they're what convince people to install.

### Screenshots (1280 × 800 each, 5 total)

Order matters. First impression sells the install.

**Screenshot 01 — The Cast Lineup** · 1280 × 800

First impression. Cast group shot or 4-character grid with names + taglines. This is the hook.

**Screenshot 02 — Angel in Action** · 1280 × 800

Mocked-up browser screenshot of Amazon with the Angel overlay triggered. Real product page, fake overlay (composited).

**Screenshot 03 — Papi in Action** · 1280 × 800

Same mockup, swap to MercadoLibre or Amazon, Papi overlay. "Ay, no, mi amor" speech bubble.

**Screenshot 04 — Mom slipper-throw** · 1280 × 800

MUST INCLUDE THIS ONE. Even as a still — the moment of slipper mid-air. Most shareable visual.

**Screenshot 05 — Onboarding flow** · 1280 × 800

Show the goal-setting + character-pick onboarding. Demonstrates the personalization story.

### Promo assets

**Promo Tile (Small)** · 440 × 280

REQUIRED for Web Store listing. Shows in search results + featured rows.

- Product name
- Cast group shot OR Angel solo
- Single-line tagline: "Pick your guardian."
- Brand color background

Keep simple. This is a tile, not a poster — must read at small sizes in browse views.

**Marquee Tile** · 1400 × 560 (optional but recommended)

What gets you featured. Landscape format. Cast group shot with brand styling. Tagline + CTA.

If you make this asset and the editorial team picks you up, you go from "discoverable" to "featured" — that's a 10× install bump.

Reuse the cast group shot from the Cast page, recompose for landscape.

---

## 🌐 PAGE 5 — Marketing Site

Lives at `modafoca.github.io/spending-angel`. Single-page static site. Mirrors GhostSweep's structure with one addition: the Cast Showcase section.

**Hero Banner** · 1280 × 800

Top of the site. The first thing visitors see. This IS the cast group shot — same asset from the Cast page, recomposed if needed.

Will be displayed at max-width 800px on the site (design with that scaling in mind — fine detail will be lost). Drop shadow in brand color around the banner on the live site, mirroring GhostSweep's pattern.

**Site — Desktop Mockup** · 1440 × 1200

Full desktop mockup. Use this to design the entire one-pager before handing structure to Claude Code.

Sections (top to bottom):

1. Hero banner (cast group shot)
2. CTA button: "Get Spending Angel" → Gumroad
3. Cast Showcase — 4 character cards in a row, each with: art + name + tagline + tap-to-hear button. Below: "Plus the Bear and the Ex coming soon."
4. "Why Spending Angel?" features box (4 bullets):
   - Goal-aware nudges
   - A cast that fits your vibe
   - Name your vices
   - No tracking, ever
5. Footer: support email + privacy policy link

White-to-brand-color gradient background. Single accent color. System font typography — let the cast carry personality.

**Site — Mobile Mockup** · 375 × 1200

Mobile first check. Most IG traffic will land here.

Same sections as desktop, stacked vertically:

- Hero banner full-width
- CTA button full-width
- Cast cards stack vertically (4 in a column instead of row)
- Features box stacks bullets vertically
- Footer

⚠️ Touch targets minimum 44px. CTA button needs to be obviously tappable.

⚠️ The cast cards' tap-to-hear buttons are critical here — many users will discover the product on mobile, audio is half the personality.

---

## 📱 PAGE 6 — Social Launch

The "Which one are you?" campaign. Five posts over seven days, plus stories, plus TikTok. The cast IS the launch.

### Instagram Feed (1080 × 1350 — 4:5 portrait)

**Feed 01 — The Reveal** · 1080 × 1350

DAY 0 LAUNCH POST. 20-sec Reel cycling through all four characters triggering on Amazon. Sound on.

Caption hook: *"I built four guardians that live in my browser and yell at me when I try to buy stuff I don't need."*

CTA: link in bio.

**Feed 02 — Cast Carousel** · 1080 × 1350 each (6 slides)

DAY 1.

- Slide 1: Cast group shot. Caption: "Tag yourself. Tag your friend who needs this."
- Slide 2: Angel solo + name + tagline + "You're this one if... you want gentle guidance."
- Slide 3: Papi solo + name + tagline + "You're this one if... you need someone who cares like family."
- Slide 4: Wizard solo + name + tagline + "You're this one if... you respond to dramatic gravitas."
- Slide 5: Mom solo + name + tagline + "You're this one if... you need the slipper energy." Mom slipper-throw frame as the visual.
- Slide 6: CTA + bio link

**Feed 03 — The Why** · 1080 × 1350

DAY 3. Personal story.

*"I was saving for Tokyo. Then Amazon's homepage happened. So I built four guardians to stop me."*

Show goal + character pick onboarding.

**Feed 04 — Behind the Scenes** · 1080 × 1350

DAY 5. Sketches → final designs → working extension. Show the design morning Figma file evolving.

Caption: *"From sketch to ship in under a week. This is how the studio works."*

(Optional ModafocaLab tease here.)

### Instagram Stories + Reels + TikTok (1080 × 1920 — 9:16 portrait)

**Story — Launch Announce** · 1080 × 1920

Day 0. Animated cast reveal. Swipe-up to bio link. Reuse the Reel from Feed 01 if assets are tight.

**Story — Poll: Which Guardian?** · 1080 × 1920

Day 1. Static image of all 4 with poll sticker. "Which one are you?" Each character is a poll option.

**Story — BTS Design Morning** · 1080 × 1920

Day 2. Behind the scenes from your Figma file. Time-lapse of the design morning.

**Story — Poll: Shuffle?** · 1080 × 1920

Day 3. "Shuffle mode: yes or no?" Single yes/no poll.

**Reel Cover — Slipper** · 1080 × 1920

Day 7. The slipper Reel cover — Mom mid-throw, slipper at apex, motion blur.

ONE-LINE caption: maybe just "👟". This is the post built for group chats.

Same dimensions work for TikTok cross-post.

---

## Asset checklist (final summary)

By end of v1.5 design morning, you should have:

- [ ] 4 character canvases drawn in chosen direction
- [ ] Cast group shot (1280 × 800)
- [ ] 3 popup states designed
- [ ] 2 onboarding screens designed
- [ ] Overlay state designed (default, character-swappable)
- [ ] 3 extension icons (128, 48, 16) + optional mono
- [ ] 5 Web Store screenshots
- [ ] Promo tile (440 × 280) + optional marquee (1400 × 560)
- [ ] Hero banner (1280 × 800) — can be the cast group shot
- [ ] Desktop site mockup (1440 × 1200)
- [ ] Mobile site mockup (375 × 1200)
- [ ] 4 IG feed posts (1 reveal + 6-slide carousel + why + BTS) at 1080 × 1350
- [ ] 5 IG story / Reel / TikTok at 1080 × 1920
- [ ] Brand color locked

That's the v1.5 design package. Once it's all in place, hand to Claude Code with the PRM and ship.
