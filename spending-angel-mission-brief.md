# MISSION BRIEF — SPENDING ANGEL v0.1

**Repo:** `modafoca/spending-angel`
**Type:** Chrome Extension (Manifest V3)
**Agent:** Claude Code (autonomous)
**Estimated effort:** Weekend build (~4–6 hours)

---

## THE IDEA

A Chrome extension that acts as the angel on your shoulder when you're about to spend. It plays a sound + shows a playful reminder when you land on a shopping site or click a buy/checkout button — and crucially, it reminds you of **what you're actually saving for**. The goal is to interrupt impulse spending with a personalized nudge, not just a generic alarm.

The shift from "Hey, stop" to "Hey, stop — you're saving for Tokyo" is the whole product.

---

## CORE BEHAVIOR

1. User installs extension → onboarding asks: **"What are you saving for?"** (free text, e.g. "Tokyo trip", "Emergency fund", "New camera"). Optional: target amount + currency.
2. User toggles extension ON via popup.
3. User visits a shopping site on the domain list → sound plays + overlay shows: *"Hey. Stop. You're saving for **{goal}**."*
4. User clicks an "Add to Cart" / "Buy Now" / "Checkout" button → sound plays + overlay shows the same goal-aware message.
5. User can edit the goal anytime from the popup, mute a site, change the sound, or disable entirely.
6. If no goal is set, falls back to a generic message: *"Hey. Stop. Don't do that."*

---

## TECHNICAL ARCHITECTURE

### Files

```
spending-angel/
├── manifest.json           # MV3 config, permissions, content script declaration
├── background.js           # Service worker (minimal — handles storage events)
├── content.js              # Injected into matched pages. Detects buttons, plays sound, renders overlay.
├── overlay.css             # Styles for the in-page overlay (angel card)
├── popup.html              # Toolbar popup UI
├── popup.js                # Toggle, goal management, sound selection, save to chrome.storage
├── popup.css               # Popup styles
├── onboarding.html         # First-install welcome flow (loaded inside popup)
├── domains.js              # Exported array of ~50 e-commerce domains
├── sounds/
│   ├── stop.mp3            # "Hey. Stop. Don't do that."
│   ├── record-scratch.mp3
│   ├── buzzer.mp3
│   └── whoa.mp3
└── icons/
    ├── icon16.png
    ├── icon48.png
    └── icon128.png
```

### Manifest V3 permissions

- `storage` — save user prefs
- `activeTab` — read current URL
- `host_permissions` — `<all_urls>` (needed to inject on any shop; restrict later if desired)

### Detection strategy

**Primary:** Domain match against hardcoded list in `domains.js`. If `window.location.hostname` matches, extension activates.

**Secondary (for buttons):** CSS selector + text match.
- Selectors: `button, a, input[type="submit"]`
- Text match (case-insensitive): `add to cart`, `buy now`, `checkout`, `proceed to checkout`, `place order`, `comprar`, `añadir al carrito`, `finalizar compra`
- Attach `click` listener with event delegation on `document.body` (single listener, checks target on fire — handles dynamically injected buttons).

### Sound playback

- Use `HTMLAudioElement` in content script.
- Sound files bundled in extension → referenced via `chrome.runtime.getURL('sounds/stop.mp3')`.
- Must declare sounds in `web_accessible_resources` in manifest.

### Storage schema (chrome.storage.local)

```json
{
  "enabled": true,
  "goal": "Tokyo trip",
  "selectedSound": "stop.mp3",
  "volume": 0.7,
  "triggerMode": "click",
  "mutedDomains": [],
  "onboarded": true
}
```

`goal` is a single string. If `null` or empty, overlay falls back to generic message. No amounts, no progress tracking — keep it dumb and funny.

### Popup UI (keep minimal + playful)

- **Goal section (top, prominent):**
  - "Saving for: **Tokyo trip**" — editable inline (single text field, no other inputs)
- Big ON/OFF toggle (label changes when off: "Angel is sleeping 😴")
- Sound dropdown (4 options at launch, with playful names — see Comedy Direction)
- Volume slider
- Trigger mode radio: On page load / On button click / Both
- "Mute this site" button (shown when popup opens on a matched site)

### Onboarding (first install)

Single-question flow inside the popup:
1. Welcome — "I'm your Spending Angel. I keep an eye on your wallet."
2. Ask: **"What are you saving for?"** (free text, single field)
3. "Done — I've got your back."

Skip allowed. Goal can be edited anytime from popup. That's it. No amounts, no currency picker, no tracking.

---

## DOMAIN LIST (starter — ~50 domains)

Put in `domains.js` as a single exported array. Starter set:

**Global giants:** amazon.com, amazon.es, amazon.com.mx, ebay.com, aliexpress.com, alibaba.com, temu.com, shein.com, wish.com, etsy.com, walmart.com, target.com, bestbuy.com, costco.com, ikea.com

**Fashion:** zara.com, hm.com, uniqlo.com, asos.com, zalando.com, nike.com, adidas.com, shein.com

**Tech/Electronics:** apple.com, bhphotovideo.com, newegg.com, microcenter.com

**Platforms (Shopify/Woo will hit many stores):** shopify.com, shop.app, *.myshopify.com (wildcard match)

**DR/LATAM:** mercadolibre.com, mercadolibre.com.do, jumbo.com.do, plazalama.com.do, cuestamoda.com

**Grocery/Food:** instacart.com, doordash.com, ubereats.com

**Misc high-risk impulse:** steampowered.com, nintendo.com, playstation.com, microsoft.com/store

Claude Code: extend to 50 using real top-traffic e-commerce rankings. Include a comment at the top of `domains.js` explaining how to add new domains.

---

## SOUND SOURCING

For v0.1, use either:
1. **Record it yourself** — Ian records a 2-second "Hey. Stop. Don't do that." in his own voice. Ship as the default.
2. **Freesound.org** — CC0 sounds for record scratch, buzzer, "whoa."

Claude Code: create the `sounds/` folder with **placeholder silent .mp3 files** at the correct filenames. Ian will drop real audio in before first test. Document this clearly in the README.

---

## COMEDY DIRECTION

**This is the product.** The financial logic is intentionally dumb so the comedy can carry the weight. Both the LOOK and the SOUND need to land.

### Visual personality (the overlay)

The overlay should feel like a tiny cartoon character popping into your browser, not a sterile notification. Direction for Claude Code:

- **Character:** A small angel illustration (SVG, ~80–100px) — halo, little wings, slightly judgy expression. Hand-drawn vibe, NOT corporate flat design. Think "Looney Tunes shoulder angel," not "iOS notification."
- **Speech bubble:** Comic-book style, with a tail pointing at the angel. Hand-drawn border, not a perfect rounded rectangle.
- **Animation:** The angel slides in from the side with a tiny bounce. Speech bubble pops in 100ms after. The whole thing wobbles slightly like it's hovering. Auto-dismiss after 4s with a poof, OR click to dismiss.
- **Position:** Top-right, but offset so it doesn't look like a system notification. Maybe slight rotation (-3°) to feel like a sticker.
- **Color palette:** Warm cream background, navy outlines, a single accent color. Avoid the gradient-y SaaS aesthetic. This should look like a meme, not Stripe.
- **Typography:** Hand-drawn or comic font for the speech bubble (Comic Neue is acceptable as a placeholder; aim for something with more character).

### Audio personality (the sounds)

Default sound pack should feel like a sitcom laugh track for your wallet. Suggested options:

| Filename | Vibe | Description |
|----------|------|-------------|
| `stop.mp3` | The Classic | Ian's voice (or stand-in): "Hey. Stop. Don't do that." Slightly exasperated, like a parent. |
| `bonk.mp3` | Cartoon | Comedic BONK / mallet hit. Pairs with the visual wobble. |
| `mom-sigh.mp3` | Disappointed | A long, theatrical sigh. No words needed. Devastating. |
| `wah-wah.mp3` | Trombone | The classic sad trombone. Plays you off the page. |

Optional bonus sounds Ian might record himself:
- "Mmm... no." (lazy drawl)
- "Ay, no, mi amor." (Dominican mom energy — bilingual angel)
- A throat clear

**Sound naming in the dropdown should be playful, not technical:**
- "The Classic" / "Cartoon Bonk" / "Disappointed Sigh" / "Sad Trombone" — not the filenames.

### Tone of every string in the product

- Onboarding: warm, conspiratorial. ("I've got your back.")
- Overlay generic fallback: short and playful. ("Hey. Stop. Don't do that.")
- Toggle off state: "Angel is sleeping 😴"
- README: written like a friend told you about it, not a product page.

If a copy line feels like a real app wrote it, rewrite it.

---

## MISSION STEPS FOR CLAUDE CODE

1. **Init repo** — create `modafoca/spending-angel` on GitHub (public), init with README, MIT license, `.gitignore` for Node.
2. **Scaffold files** — all files listed above, placeholder icons (simple angel icon — halo + shopping bag, or use emoji as SVG placeholder).
3. **Write manifest.json** — MV3, all declarations, including `web_accessible_resources` for sounds + overlay assets.
4. **Write content.js** — domain check → button detection via event delegation → audio play → overlay render (reads `goal` from storage, falls back to generic message if missing).
5. **Write overlay.css** — styled card that slides in from top-right with the angel message. Auto-dismiss after 4s or on click. **See Comedy Direction for visual personality.**
6. **Write popup.html/js/css** — minimal, clean, playful. Goal section at top, settings below.
7. **Write onboarding.html + flow** — first-install experience that asks for the savings goal.
8. **Write domains.js** — expand starter list to ~50 domains including DR/LATAM.
9. **Write README.md** — install instructions, customization notes, "how to add your own sounds" section, screenshot placeholders.
10. **Commit in logical chunks** — one commit per major piece.
11. **Push to main.** No PR needed for v0.1.

---

## TEST PLAN (for Ian, post-build)

1. Load unpacked in Chrome → verify icon appears.
2. First open of popup → verify onboarding asks for goal (single field).
3. Set goal to "Tokyo trip."
4. Visit amazon.com → verify angel overlay shows "Saving for Tokyo trip" + sound plays.
5. Click "Add to Cart" on any product → verify overlay + sound trigger.
6. **Comedy check:** Does it actually make you laugh the first time? If no → ship anyway and iterate sounds/visuals in v0.2.
7. Open popup → edit goal to "New camera" → revisit → verify overlay updates.
8. Open popup → toggle off → verify "Angel is sleeping" state + revisit amazon.com → verify silence.
9. Change sound in popup → revisit → verify new sound plays.
10. Visit a non-listed site (e.g. google.com) → verify nothing happens.
11. Visit a Shopify-powered store → verify wildcard match catches it.
12. Clear goal entirely → verify fallback to generic "Hey. Stop. Don't do that."

---

## OUT OF SCOPE FOR v0.1

- Any kind of spend tracking or "saved $X this week" math — never. The joke carries it.
- Manual amount entry, target amounts, currencies — none of it.
- Firefox version (Manifest V2 port) — v0.2
- Multiple goals / goal switching — v0.2
- Custom user sounds upload — v0.2
- Cooldown logic (don't re-trigger within 60s) — add in v0.2 if annoying
- Chrome Web Store submission — after Ian tests personally for a week

---

## ACCEPTANCE CRITERIA

- [ ] Extension loads without errors in Chrome dev mode.
- [ ] Onboarding flow runs on first install and saves the goal (single string).
- [ ] Visiting amazon.com triggers the angel overlay with the user's actual goal text + sound.
- [ ] Goal can be edited from the popup and updates take effect immediately.
- [ ] Generic fallback works when goal is cleared.
- [ ] Popup toggles enable/disable and persists across sessions.
- [ ] **Visual landing test:** the overlay looks more like a sticker/cartoon than a notification.
- [ ] **Audio landing test:** the default sound makes Ian laugh the first three times he hears it.
- [ ] Code is clean, commented, and organized for future expansion.
- [ ] README is clear enough that someone else could install and modify.

---

## DELIVERABLE

GitHub repo `modafoca/spending-angel` with working v0.1 extension, README, and placeholder sounds. Ian drops in real audio → manual install → ship to friends for laughs.

**Ship note:** This is a fun project. Keep the code tight, the UI playful, the comments honest. Don't over-engineer. If something's ambiguous, pick the lighter option and ship.
