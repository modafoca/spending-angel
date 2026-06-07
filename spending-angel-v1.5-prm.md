# MISSION BRIEF — SPENDING ANGEL v1.5

**Repo:** `modafoca/spending-angel` (single repo, monorepo style)
**Builds on:** v1.0 (shipped) — see `PRM.md` for original spec
**Type:** Chrome Extension + marketing site + distribution package
**Agents:** Claude Code (build), Ian (design + listings), Jorge (optional brand pass on copy)
**Estimated effort:** 3–5 days from kickoff to public launch

---

## CONTEXT — WHAT SHIPPED IN v1.0

- Working extension installed locally
- Onboarding asks "What are you saving for?" and stores a single goal string
- Domain list of ~50 stores triggers angel overlay + sound on cart click
- Popup with toggle, sound dropdown, goal editor, mute-this-site, trigger mode
- Generic fallback when no goal is set
- Repo at `modafoca/spending-angel`, README, MIT license

**One known glitch:** after the angel dismisses, it re-appears for ~0.5s before disappearing for good.

---

## v1.5 GOALS

1. Fix the dismiss-flicker.
2. Replace the placeholder visual with a real designer-made cast that's actually funny.
3. **Introduce the Character System — four playable guardians at launch, with shuffle mode.**
4. Expand store detection to cover the long tail.
5. Build the marketing site inside the same repo.
6. Set up Gumroad as primary distribution (mirroring the GhostSweep playbook).
7. Submit to Chrome Web Store as the secondary channel.
8. Run the Instagram launch with the option to debut ModafocaLab alongside.

The studio bet: a charming, personal, Dominican-flavored cast of guardians that gets shared on IG because the visual + sound is funnier than anything else in the "stop spending" category — and because **"which one are you?"** is the kind of question that travels in group chats. Distribution mirrors what already worked for GhostSweep.

---

## TRACK 1 — v1.0.1 HOTFIX (glitch patch)

**Issue:** angel overlay dismisses, then briefly re-renders before disappearing.

**Likely root cause:** one of two things, possibly both.

1. **CSS transition race:** `display: none` is applied while a `transform` or `opacity` transition is still resolving. The element re-shows for the tail of the transition, then truly hides.
2. **Event bubble re-trigger:** the dismiss click bubbles up to the underlying "Add to Cart" button on the host page, which re-fires the cart-click listener and re-renders the overlay.

**Fix:**
- On dismiss, fully **remove the overlay element from the DOM** (`element.remove()`) instead of hiding via CSS.
- On the dismiss click handler, call `event.stopPropagation()` and `event.preventDefault()` to halt any further event bubbling.
- Add a 500ms internal cooldown after dismiss so even if a re-trigger sneaks through, no second overlay can render.
- After the auto-dismiss timer fires, also remove from DOM (don't just animate-out).

**Acceptance:** Trigger overlay on amazon.com → dismiss it (click or wait for timer) → the overlay does not re-appear. Repeat 5 times, observe zero flickers.

**Ship as:** `v1.0.1` patch, single PR, no other changes bundled in.

---

## TRACK 2 — THE CAST (Ian-led design)

**This is the biggest single shift from v1.0.** Spending Angel is no longer a single character — it's a roster of four guardians, with the option to add more in v1.6+. The Angel becomes the default and brand anchor; the others give the product personality, range, and IG-shareable identity moments.

### 2a. Launch cast (locked)

| Slot | Character | Voice / Gag | Audience hook |
|------|-----------|-------------|---------------|
| 1 | **The Angel** (Classic) | Gentle, exasperated. "Hey. Stop. Don't do that." | Universal default, the brand anchor |
| 2 | **Dominican Papi** | Warm, scolding. "Ay, no, mi amor." Bilingual. | DR / LATAM signature, IG fuel |
| 3 | **The Wizard** | Gravitas-vs-cart absurdism. "You shall not pass... checkout." | Wildcard, pizzazz, fantasy nerds |
| 4 | **Asian Mom** | Tiger-mom guilt + the **slipper**. "You need this? You have one already." | Diaspora audience, the slipper is THE visual gag |

**Non-negotiable design notes:**
- **Asian Mom MUST have a slipper.** It's the visual joke. Static frame, slipper raised mid-threat OR caught mid-throw — Ian's call, but no animation. The pose carries the gag.
- **Dominican Papi is bilingual** — sounds and overlay copy mix Spanish + English naturally.
- **The Wizard's comedy is the contrast** between fantasy-epic gravitas and the mundane act of clicking "Add to Cart." Lean into it visually (robes, staff, dramatic pose) and aurally (theatrical baritone).
- **The Angel stays soft-edged and warm** — it's the gentlest of the four, the "default mode."
- **No animation in v1.5.** All characters are static. Sound plays alone, no visual sync to worry about. Animation is v2.0 territory if it earns its way in.

### 2b. v1.6 backlog (announced as "coming soon" in v1.5 popup)

- **The Bear** — wordless, growling, physical-menace humor
- **The Ex** — pure judgment energy, "really? you're buying *that*?"

The "coming soon" tease in the popup serves a strategic purpose: it gives IG followers a reason to stay subscribed and makes the next release feel like a known event, not a surprise drop.

### 2c. Three design directions, applied to four characters

The three visual directions Ian named (pixel, harp angel on cloud-window edge, full cloud-window container) now need to be evaluated as a system, not just for the Angel. Whatever direction Ian picks must hold up across **all four characters**.

For example:
- **Pixel direction:** every character is a sprite. Frame-animated. Comedy via low-fi consistency. Wizard sprite = epic. Asian Mom sprite throwing slipper = peak.
- **Cloud-window edge:** every character perches on / inhabits a window-shaped container. Angel on cloud, Papi leaning over a porch railing, Wizard standing on a tower stone, Mom in a doorway. Container shape can shift per character.
- **Full cloud-window container:** every character lives inside a custom-shaped window. Angel = cloud, Papi = colmado window, Wizard = ancient scroll, Mom = kitchen doorway.

**Recommendation:** Direction 3 (custom container per character) gives the most personality differentiation and the most IG-shareable visual identity. Direction 1 (pixel) is the cheapest to produce at quality. Direction 2 (edge perch) is a middle ground.

Ian picks one direction during the design morning and produces all four characters in that style.

### 2d. Ian's deliverable from the design morning

For each of the four characters:
- Character artwork (SVG static, OR PNG spritesheet for animation)
- Container/speech bubble/window shape (per character if going Direction 3)
- Optional accessories (slipper, staff, harp, halo)
- One promo banner per character (1280×800), used in marketing site rotation + IG carousel

System-wide:
- Updated extension icon (16/48/128) — angel-led, since Angel is the default and brand anchor
- One "cast group shot" banner showing all four together — the IG launch hero image

### 2e. What Claude Code needs to know to build the v1.5 container

The overlay container must be **character-aware**. Each character has its own:
- Visual asset bundle (artwork + container shape + accessories)
- Sound pack (3–5 sounds in that character's voice/style)
- Optional animation timing (e.g. Mom's slipper-throw frame syncs with her sound)
- Display name + tagline shown in the popup picker

All character data lives in a single config file (`characters.js`) so Ian can add v1.6 characters by extending the config + dropping new assets, no overlay code changes needed.

---

## TRACK 3 — v1.5 EXTENSION BUILD

### 3a. Character-aware overlay container

Refactor `content.js` and `overlay.css` so the overlay rendering is decoupled from a single character or rectangular shape:

- All character data loaded from `characters.js`:
  ```js
  export const CHARACTERS = {
    angel: {
      id: 'angel',
      displayName: 'The Angel',
      tagline: 'Classic. Gentle. Always watching.',
      assets: { base: 'angel/cloud.svg', figure: 'angel/angel.svg' },
      sounds: ['stop.mp3', 'whoa.mp3', 'mmm-no.mp3'],
      defaultSound: 'stop.mp3'
    },
    papi: { ... },
    wizard: { ... },
    mom: { ... }
  }
  ```
- Overlay root: positioned `<div>` with **transparent background, no border, no shadow** at the wrapper level. Visual identity comes entirely from inner character assets.
- Inner structure:
  ```
  .sa-overlay-root[data-character="papi"]
    └── .sa-stage          (positioning, slide-in entry, dismiss exit)
         ├── .sa-base       (character-specific container shape — static SVG)
         ├── .sa-figure     (character artwork — static SVG)
         └── .sa-message    (speech bubble + goal text, character-tinted)
  ```
- Character switching is handled via the `data-character` attribute on the overlay root. CSS targets `[data-character="papi"] .sa-base { background-image: url(...); }` etc. No JS class juggling.
- All assets live under `/assets/overlay/<character-id>/` so adding a v1.6 character is: drop a folder + extend `characters.js`. No overlay code changes.
- **Static characters only.** No spritesheets, no frame animation, no sound-visual sync. Entry and exit animations on the overlay container itself (slide-in, dismiss) are fine — those are CSS transitions on the wrapper, not character animation.

### 3b. Detection expansion

**Expand `domains.js`** from ~50 to ~200 domains. Categories to fill out:

- Global e-commerce giants (Amazon all locales, eBay all locales, AliExpress, Temu, Shein, Wish, Etsy, Walmart, Target, Best Buy, Costco, Ikea, Zappos)
- Fashion (Zara, H&M, Uniqlo, ASOS, Zalando, Nike, Adidas, Forever21, SSENSE, Net-a-Porter, Farfetch, Nordstrom)
- Tech (Apple, B&H, Newegg, Microcenter, Adorama, Crucial)
- Home (Wayfair, West Elm, CB2, Crate & Barrel, RH, Pottery Barn)
- Beauty (Sephora, Ulta, Glossier, Mecca)
- LATAM + DR (MercadoLibre all countries, Falabella, Linio, La Sirena, Jumbo DR, Plaza Lama, Cuesta, Multiplaza, La Curacao)
- Marketplaces (Etsy, Reverb, Discogs, Bandcamp, Depop, Vinted, Poshmark, ThredUp, Grailed, StockX, GOAT)
- High-impulse-risk (Steam, Nintendo, PlayStation Store, Xbox Store, Apple App Store, Spotify gift cards)
- Food impulse (Instacart, DoorDash, Uber Eats, Rappi, PedidosYa)
- Wildcard match: `*.myshopify.com` already in v1.0 — keep it

Total: ~200 domains, alphabetized, with a comment block at the top explaining how to add more.

### 3c. Fallback heuristic for unlisted sites

When the user is on a domain **not** in the list, run a conservative heuristic:

**Trigger conditions (ALL must be true):**
- The user clicked a button (never on page load — load-trigger stays domain-list-only)
- The clicked element's text matches cart/checkout patterns: `add to cart`, `buy now`, `checkout`, `proceed to checkout`, `place order`, `comprar`, `añadir al carrito`, `finalizar compra`, `pagar`, `confirmar pedido`
- AND **at least one** of these supporting signals is present on the page:
  - `<meta name="description">` contains: `shop`, `store`, `buy`, `purchase`, `tienda`
  - Page has structured data with `@type: Product`, `Offer`, or `OfferPrice` (schema.org)
  - URL path includes `/cart`, `/checkout`, `/shop`, `/product`, `/products/`, `/buy`, `/order`, `/comprar`, `/tienda`

**Why this works:** the button-text match catches the moment of intent. The supporting-signal requirement filters out false positives (a news article mentioning "buy" in a headline won't have product schema or a `/cart` URL). Conservative by design.

**Telemetry hook (opt-in only, defaults to off):** if the user opts in via popup, log heuristic hits to local storage so Ian can review which domains the heuristic catches and promote the good ones to the hardcoded list in v1.6. Never sends data anywhere — local only.

### 3d. Sound system — per-character sound packs

- Each character in `characters.js` declares 3–5 sounds in their voice/style.
- File structure: `/assets/sounds/<character-id>/<filename>.mp3`
- Sound dropdown in popup is **scoped to the active character** — switching characters swaps the available sound list automatically.
- Each character has a `defaultSound` that plays unless the user picks otherwise.
- New sounds Ian needs to record (or source) for launch:
  - **Angel:** "Hey. Stop. Don't do that.", "Mmm... no.", soft sigh
  - **Papi:** "Ay, no, mi amor.", "¿Tú estás loco?", knowing chuckle, "Hmmm..."
  - **Wizard:** "You shall not pass... checkout.", incantation hum, dramatic staff thud
  - **Mom:** "Aiyah!", "You have one already!", slipper-whoosh SFX, tongue click
- Sounds play standalone — no visual sync, no frame timing dependencies.

### 3e. Character selection + Shuffle Mode

**Storage schema additions:**
```json
{
  ...v1.0 fields,
  "activeCharacter": "angel",
  "shuffleMode": false,
  "perCharacterSound": {
    "angel": "stop.mp3",
    "papi": "ay-no-mi-amor.mp3",
    "wizard": "shall-not-pass.mp3",
    "mom": "aiyah.mp3"
  }
}
```

**Trigger logic:**
- If `shuffleMode === false`: render `activeCharacter` with their `perCharacterSound[activeCharacter]`.
- If `shuffleMode === true`: pick a random character from the unlocked roster on each trigger. Use that character's default sound (not the user's per-character override — shuffle is meant to feel chaotic).
- Shuffle does NOT repeat the same character twice in a row (anti-streak, keeps variety).

**Popup additions:**
- **Character picker** prominently placed below the goal field. Visual: 4 character avatars in a row, active one highlighted with a glow/border. Tap to switch.
- **Shuffle toggle** below the picker, labeled: "🎲 Feeling chaotic? Shuffle every time." Off by default.
- **"Coming soon" slot** showing silhouettes of the Bear and the Ex with a "v1.6" badge. Non-interactive but visible — strategic teaser for IG followers.

### 3f. Onboarding update for character selection

Single-screen onboarding now runs in **two steps** (still skippable at each):

**Step 1 — Goal:**
- "I'm your Spending Guardian. What are you saving for?" (single text field)
- Continue → Step 2

**Step 2 — Character pick:**
- "Pick your guardian. You can change them anytime."
- Show all 4 characters with name + tagline + a tiny preview of their voice (tap to hear sample sound)
- Below: a small "Or shuffle them all 🎲" toggle for users who can't pick
- "Done — I've got your back." → marks `onboarded: true`, `activeCharacter` saved, `shuffleMode` saved if toggled

If user skips Step 2: default to Angel, shuffle off. Same user can change anytime in popup.

### 3g. Vice List — user-defined watchlist

The hardcoded 200-domain list + heuristic fallback covers the common cases, but everyone has their own niche weakness — a specific Etsy shop, a local boutique, a hobby store the heuristic misses. The Vice List lets users add their own domains explicitly.

**Naming:** the feature is called the **Vice List** in all UI copy. Not "blacklist," not "watchlist." The name is the joke — users are literally naming their vices.

**Behavior:**
- User adds a domain via the popup (simple text input, URL only, no notes)
- Domains on the Vice List trigger the angel exactly like hardcoded domains do — same character logic, same sound logic, same trigger modes
- Vice List is checked AFTER the hardcoded list and BEFORE the heuristic fallback
- **The global ON/OFF toggle wins.** If the extension is off, the Vice List is off too. No override. Off means off — committed to one or the other.
- Domains can be removed from the list anytime
- Stored as a simple array in `chrome.storage.local`

**Storage schema addition:**
```json
{
  ...existing fields,
  "viceList": ["etsy.com", "stationery-shop.jp", "local-bookstore.do"]
}
```

**Popup UI for the Vice List:**
- Lives in a collapsible section labeled "**My Vices**" with a subtitle "Sites I can't be trusted on"
- Simple list view: each entry shows the domain + a small × to remove
- "Add a vice..." text input below the list, single field, accepts pasted URLs (auto-strips `https://`, `www.`, paths)
- Empty state copy: "No vices yet. Bold of you. Add a site you can't trust yourself on."

**Validation:**
- Strip protocol and path on input — store only the hostname
- De-duplicate (case-insensitive) on add
- No length limit on the list (if a user has 50 vices, that's their truth)

**Acceptance:**
- [ ] Adding a domain to the Vice List causes it to trigger the angel on next visit
- [ ] Removing a domain stops triggers immediately
- [ ] Global OFF toggle silences Vice List domains too (no override)
- [ ] Pasting a full URL strips it down to just the hostname
- [ ] Duplicates are not added

### 3h. Acceptance criteria for v1.5 extension

- [ ] Glitch from v1.0 is gone (carry over from Track 1)
- [ ] All four characters render correctly with their unique container, figure, and message styling
- [ ] Switching characters in popup updates the next overlay trigger immediately
- [ ] Shuffle mode rotates randomly without repeating the same character twice in a row
- [ ] Onboarding two-step flow runs on first install and saves both goal AND character choice
- [ ] "Coming soon" slot for v1.6 characters (Bear + Ex) is visible in popup
- [ ] Domain list expanded to ~200, no false positives observed across 30 minutes of normal browsing
- [ ] Heuristic fallback fires correctly on at least 3 unlisted but legitimate shopping sites
- [ ] Heuristic does NOT fire on news sites, Wikipedia, blogs, or any non-shopping context
- [ ] Vice List works end-to-end: add, trigger, remove, respect global toggle
- [ ] All v1.0 features still work (toggle, mute-this-site, goal editor, trigger mode)
- [ ] Adding a hypothetical 5th character requires only a new folder + `characters.js` extension — no overlay code changes

---

## TRACK 4 — MARKETING SITE (same repo, `/docs` folder)

**Decision locked:** site lives inside `modafoca/spending-angel` under `/docs/`. GitHub Pages serves from `main` branch, `/docs` folder. No separate repo.

### 4a. Repo structure for v1.5

```
spending-angel/
├── manifest.json              # extension root (unchanged)
├── content.js
├── popup.html, popup.js, popup.css
├── onboarding.html
├── domains.js
├── assets/
│   ├── overlay/               # NEW — Ian's angel assets
│   ├── sounds/                # existing, expanded
│   └── icons/                 # existing
├── docs/                      # NEW — marketing site, served by GitHub Pages
│   ├── index.html
│   ├── privacy.html
│   ├── banner.png             # Ian's hero banner
│   └── assets/                # site-only images, favicon
├── PRM.md                     # original v1.0 brief
├── PRM-v1.5.md                # this brief
└── README.md
```

GitHub Pages config: Settings → Pages → Source = `main` branch, `/docs` folder. URL becomes `https://modafoca.github.io/spending-angel/`.

Custom domain optional later — for v1.5 launch, the github.io URL is fine.

### 4b. `index.html` spec

Mirror GhostSweep structure with one major addition: **a cast showcase**. The four characters are the product's identity — the site needs to lead with them.

Single page, single `<style>` block, zero JS framework, ships in seconds.

**Sections, in order:**

1. **Hero banner image** (`banner.png` — the cast group shot, all four characters together; max-width 800px, drop shadow in brand color)
2. **Primary CTA button:** "Get Spending Angel" → links to Gumroad URL
3. **Cast showcase** (the new section — most important visually):
   - 4 character cards in a horizontal row (stacked on mobile)
   - Each card: character art + name + one-line tagline + "tap to hear them" mini play button
   - Below the row: small text "Plus the Bear and the Ex coming soon."
4. **"Why Spending Angel?" features box** (white card on gradient bg, brand-colored border, four bullets):
   - **Goal-aware nudges:** It knows what you're saving for and reminds you mid-impulse.
   - **A cast that fits your vibe:** Pick your guardian — or shuffle them and let chaos reign.
   - **Name your vices:** Add your own sites to the watchlist. Bold of you.
   - **No tracking, ever:** Your goals stay on your device. We never see them.
5. **Footer:** support email + privacy policy link

**Brand color:** TBD by Ian during design morning. Site uses single accent color + white-to-color gradient background, mirroring GhostSweep's pattern.

**Typography:** system stack — keep it boring, let the cast carry personality.

**Copy tone:** warm, conspiratorial, slightly funny. Avoid product-page voice. Read the v1.0 PRM's "Tone of every string" section.

### 4c. `privacy.html` spec

Required for Chrome Web Store submission. Single page, plain language, no legalese where avoidable.

**Sections:**
- What Spending Angel does
- What data it collects: **none**
- What data it stores locally: goal string, settings, mute list (chrome.storage.local only, never leaves device)
- No third-party services, no analytics, no telemetry (unless heuristic-debug opt-in is on, and even then it stays local)
- Contact email

Match the visual styling of `index.html` for consistency.

### 4d. Support email

Set up `spendingangel@proton.me` (or `angel@modafoca.com` if Ian wants studio-branded). ProtonMail mirrors the GhostSweep choice and reinforces the privacy story.

### 4e. Acceptance criteria

- [ ] `/docs/index.html` and `/docs/privacy.html` render correctly on github.io
- [ ] CTA button links to live Gumroad listing (added once Track 5 is done)
- [ ] Banner image is Ian's design, not placeholder
- [ ] Mobile-responsive at 375px width
- [ ] Privacy policy is accurate and matches actual extension behavior
- [ ] Support email is monitored

---

## TRACK 5 — GUMROAD DISTRIBUTION (primary channel)

Mirroring the GhostSweep playbook exactly.

### 5a. Gumroad product setup

- Create Gumroad product: "Spending Angel — A Chrome Extension"
- Pricing model: **pay what you want**, $0 minimum, suggested tip $3 (matches the playful charity-of-effort tone). Open question for Ian — could also do flat $0 with optional tip.
- Cover image: Ian's banner from Track 2
- Product description: short, punchy, written like the IG caption, not a sales page
- Email collection: ON (this is half the reason Gumroad exists in this funnel)
- Delivery: ZIP of the unpacked extension folder + a one-page install guide (`INSTALL.md`)
- Once Web Store is approved, the delivery message also includes the Web Store link as the easier install path

### 5b. Install guide (`INSTALL.md` inside the ZIP)

Plain-language steps for non-technical users:
1. Unzip
2. Open Chrome → `chrome://extensions/`
3. Toggle "Developer mode" on (top right)
4. Click "Load unpacked" → select unzipped folder
5. Pin the angel icon
6. Set your goal — you're done

Include screenshots for each step.

### 5c. Acceptance criteria

- [ ] Gumroad listing is live and tested with a self-purchase (free)
- [ ] ZIP delivery works end-to-end
- [ ] INSTALL.md is clear enough that a non-technical friend can install in under 3 minutes
- [ ] Email confirmation copy matches brand voice
- [ ] Marketing site CTA button updated with the live Gumroad URL

---

## TRACK 6 — CHROME WEB STORE (secondary channel, parallel)

Submit while Gumroad goes live. Web Store review is 1–3 days; runs in parallel so it doesn't block launch.

### 6a. Pre-submission checklist

- Chrome Web Store developer account ($5 one-time fee — Ian needs to pay this if not already done)
- Listing assets:
  - 128×128 icon (final v1.5 icon from Ian)
  - At least 1, ideally 3–5 screenshots: 1280×800 or 640×400, showing the angel in action
  - Promo tile: 440×280 (uses the banner crop)
  - Optional: marquee 1400×560
- Listing copy: short title (≤45 chars), summary (≤132 chars), full description (~1500 chars). Mirror IG caption tone.
- Categories: **Productivity** (primary), Shopping (secondary if allowed)
- Privacy policy URL: `https://modafoca.github.io/spending-angel/privacy.html`
- Permissions justification: explain why `host_permissions: <all_urls>` is needed (to detect shopping sites). Be honest, be brief.

### 6b. Submission steps

1. Zip the extension files (NOT the `/docs` folder, NOT PRM files — only what's needed to run)
2. Upload to Chrome Web Store dashboard
3. Fill in all listing fields
4. Submit for review
5. Wait 1–3 days. If rejected, address feedback and resubmit (common rejection: permissions justification too vague — be very specific)

### 6c. Acceptance criteria

- [ ] Listing is approved and publicly visible in the Web Store
- [ ] Marketing site has both Gumroad CTA and "Or get it on the Web Store" secondary link
- [ ] Gumroad delivery email mentions the Web Store as the recommended install once approved

---

## TRACK 7 — INSTAGRAM LAUNCH

**The campaign hook:** **"Which one are you?"**

The cast IS the launch. Four characters means four shareable identity moments — perfect for IG, where "tag your character" energy is the whole game. Audience split: half DR locals (Spanish-speaking, MODAFOCA followers), half global creative/dev/design audience. Captions in both languages, English first.

### 7a. Five-post launch sequence (expanded from three — the cast earned it)

**Post 1 — The reveal (Day 0)**
- Format: 20-second Reel, screen recording cycling through all four characters triggering on Amazon, sound on
- Caption hook: "I built four guardians that live in my browser and yell at me when I try to buy stuff I don't need."
- CTA: link in bio → marketing site
- Hook for engagement: "Which one are you? 👇"

**Post 2 — The cast (Day 1)**
- Format: carousel, 5 slides
- Slide 1: Cast group shot
- Slides 2–5: One per character — full art + name + their signature line + a short "you're this one if..." description
   - Angel: "...you want gentle guidance"
   - Papi: "...you need someone who cares like family"
   - Wizard: "...you respond to dramatic gravitas"
   - Mom: "...you need the slipper energy"
- Caption: "Tag yourself. Tag your friend who needs this."

**Post 3 — The why (Day 3)**
- Format: Reel or carousel, personal story
- "I was saving for Tokyo. Then Amazon's homepage happened. So I built four guardians to stop me."
- Quick demo of the goal-setting + character-pick onboarding
- Slide-out: the Dominican Papi sound clip (text + audio) — the most shareable of the four

**Post 4 — Behind the scenes (Day 5)**
- Format: Reel, sketches → final designs → working extension across all four characters
- Show the "design morning" Figma file evolving
- Caption: "From sketch to ship in under a week. This is how the studio works."
- (Optional ModafocaLab tease here — see Track 8)

**Post 5 — The slipper (Day 7)**
- Format: short Reel, just the Asian Mom slipper-throw animation in slow-mo with the whoosh sound, looping
- One-line caption. Maybe just "👟"
- This is the post that gets sent to group chats. Built for shareability, not info.

### 7b. Stories rotation

- Day 0: launch announcement, swipe-up to bio link
- Day 1: poll — "Which guardian are you?" with all four as options
- Day 2: behind-the-scenes design morning
- Day 3: poll — "Shuffle mode: yes or no?"
- Day 5: user reactions / repost the best ones
- Day 7: the slipper post + "drop a 👟 if you're a Mom person"

### 7c. Distribution beyond IG

- **TikTok:** the slipper Reel (Post 5) is built for TikTok. Same edit, post natively.
- **LinkedIn:** Post 4 (BTS) only — frames the studio's experimentation cadence. Skip the cultural-character angle on LinkedIn.
- **Twitter/X:** Post 1 + Post 5. Single tweets, link in profile.
- **Hacker News:** only after Web Store approval AND first 100 IG installs are positive. "Show HN: I built a Chrome extension that stops impulse spending — pick your guardian, including a Dominican Papi and an Asian Mom with a slipper."

### 7d. Acceptance criteria

- [ ] All five posts published on schedule with working bio link
- [ ] All character art is final, not placeholder
- [ ] Captions are in Ian's voice, not generic launch-post voice — Spanish/English mix where it lands naturally
- [ ] Bio link works on mobile and points to live Gumroad-CTA marketing site
- [ ] Stories use the cast for engagement (polls, reactions) — not just static announcements
- [ ] At least one piece of UGC (someone tagging themselves as a character) is reposted by Day 7

---

## TRACK 8 — MODAFOCALAB DECISION (parking lot, decide before Track 7 Post 3)

**The dependency:** if Spending Angel is the inaugural ModafocaLab public release, the marketing site, Gumroad listing, and IG Post 3 should reflect that. If not, Spending Angel ships as a standalone MODAFOCA project.

**Open questions to resolve before launch day:**
1. Is ModafocaLab a sub-brand of MODAFOCA Studio or a standalone? Visual identity?
2. Does Spending Angel debut the Lab, or does the Lab launch separately first?
3. Does the Lab have its own footer/byline ("A ModafocaLab project") or live on the IG only for now?

**Recommendation:** treat this as a separate 30-minute conversation tomorrow afternoon, after design morning. It's a strategic call, not a v1.5 build dependency. If undecided by Day 3, ship Post 3 without the ModafocaLab framing — easy to add later, hard to walk back.

---

## SEQUENCING (5–7 day arc, expanded from 3–5 to accommodate the cast)

**Day 1**
- Morning: Ian in Figma — design exploration. Pick one of the three directions. Apply it to all four characters. Produce final art for at least 2 characters (Angel + Papi as priority — the brand anchor + the IG signature).
- Afternoon: Claude Code — Track 1 hotfix + Track 3a (character-aware container scaffold) + Track 3b (domain expansion). Commits in chunks.
- Late afternoon: 30-min ModafocaLab conversation (Track 8)

**Day 2**
- Morning: Ian finishes Wizard + Mom character art + the cast group shot banner.
- Afternoon: Ian records voice clips for all four characters (Angel + Papi voiced by Ian, Wizard + Mom voiced by Ian or pulled from CC0 / hired voice talent). Source SFX: slipper-whoosh, staff thud.
- Evening: Claude Code finishes Track 3 (heuristic fallback, character selection logic, shuffle mode, two-step onboarding).

**Day 3**
- Morning: Ian QAs the build with all four characters. Adjusts asset positioning. Refines slipper-throw animation timing.
- Afternoon: Claude Code scaffolds Track 4 (marketing site in `/docs`). Ian writes feature copy. Cast showcase section assembled with character cards.

**Day 4**
- Morning: Ian sets up Gumroad listing (Track 5), tests free purchase flow. Description leans on the cast.
- Afternoon: Ian preps Web Store submission (Track 6) — submits with screenshots showing all four characters. Most permissions justification work happens here.

**Day 5**
- Wait on Web Store review. Ian produces IG content — recordings of all four characters, cast group shot, slipper slow-mo.
- Marketing site goes live with Gumroad CTA. Soft-launch to a few friends.

**Day 6**
- Web Store approval (probably). IG Post 1 + Post 2 go live. Stories run.

**Day 7+**
- Posts 3, 4, 5 follow on Days 8, 10, 12.
- TikTok cross-post on Day 8.
- Monitor reactions, repost UGC.

---

## OUT OF SCOPE FOR v1.5

- **The Bear** and **The Ex** characters — v1.6 (announced as "coming soon" in v1.5)
- Custom user-uploaded characters — never planned
- Firefox port — v2.0
- Spend tracking math — never (the joke is the point)
- Multiple goals / goal switching — v1.6
- Custom user sound upload — v1.6
- Translations beyond ES/EN — v2.0
- Paid tier or premium character packs — only if v1.5 hits 1000+ installs

---

## DELIVERABLE

By end of Day 7:
- Live extension on Chrome Web Store with full four-character cast
- Live marketing site at `modafoca.github.io/spending-angel` featuring the cast showcase
- Live Gumroad listing collecting installs and emails
- IG launch sequence (5 posts) running with "Which one are you?" engagement
- ModafocaLab decision either locked in or cleanly deferred
- v1.6 backlog populated (Bear + Ex characters, plus anything else cut from this scope)

**Ship note:** This is the moment Spending Angel goes from a private weekend build to a public studio release with a real identity. The cast is the product now — keep the personality LOUD and DISTINCT across every character, every touchpoint. If a piece of copy could've been written by any other product, rewrite it. Dominican angel energy throughout. The slipper is mandatory (static is fine — the pose is the gag).
