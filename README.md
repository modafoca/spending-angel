# Spending Angel

A tiny Chrome extension that's the angel on your shoulder when you're about to spend.

You tell it once what you're saving for. Then, when you wander onto a shopping site or click "Buy now," it slides in from the corner with a cartoon angel and a sound, and reminds you: *"Hey. Stop. You're saving for Tokyo trip."*

That's it. No tracking, no math, no dashboards. The joke does the work.

## What it does

- Asks once: **what are you saving for?** (free text — "Tokyo trip", "rent", "new camera")
- When you visit one of ~50 known shopping sites, OR click an "Add to Cart" / "Buy now" / "Checkout" button anywhere, an angel slides in from the corner with your goal text and plays a sound.
- Click the toolbar icon to edit the goal, change the sound, mute a site, or send the angel to bed (`Angel is sleeping 😴`).
- If you leave the goal blank, it falls back to the generic *"Hey. Stop. Don't do that."*

Bilingual on launch — the click detector matches English and Spanish buy-button text (`add to cart`, `comprar`, `finalizar compra`, etc.).

## Install (dev mode)

1. Clone this repo.
2. Open `chrome://extensions`.
3. Toggle **Developer mode** on (top-right).
4. Click **Load unpacked** → pick this folder.
5. The extension installs and immediately opens onboarding. Set your goal, you're done.

> **Heads up — the bundled sounds are silent.** This repo ships with 0.5s silent `.mp3` placeholders so the extension loads without 404s. Drop real audio at `sounds/stop.mp3`, `sounds/bonk.mp3`, `sounds/mom-sigh.mp3`, `sounds/wah-wah.mp3` to hear anything. See `sounds/README.md`.

> **Heads up — no toolbar icon yet.** Chrome shows the default puzzle-piece in v0.1. To swap in real ones, see `icons/README.md`.

## Adding your own sounds

1. Drop `sounds/your-sound.mp3` into the folder.
2. Add `<option value="your-sound.mp3">Your Label</option>` to the `<select id="sound">` in `popup.html`.
3. Reload the extension on `chrome://extensions`.

Sound names in the dropdown should be playful, not technical — "The Classic", "Cartoon Bonk", "Disappointed Sigh", "Sad Trombone".

## Adding your own shopping domains

Edit `domains.js` — append a string to the `SPENDING_ANGEL_DOMAINS` array. Use the bare hostname (`amazon.com`, not `https://www.amazon.com/`). Wildcards: prefix with `*.` (e.g. `*.myshopify.com` catches every Shopify-hosted store).

## How it decides to trigger

Two paths, both in `content.js`:

- **Domain match on page load.** The hostname is checked against `domains.js` (suffix match, `www.` stripped).
- **Buy-button click.** A single delegated `click` listener on `document` looks at the target's text — `add to cart`, `buy now`, `checkout`, `place order`, plus the Spanish equivalents — and triggers regardless of domain.

You can switch between page-load only / button-click only / both in the popup. There's a 1.5-second cooldown so the sound doesn't stack on rapid clicks.

## File map

```
spending-angel/
├── manifest.json     MV3 config
├── background.js     service worker — sets defaults, opens onboarding
├── content.js        injected into every page; runs the show
├── overlay.css       angel sticker styles
├── popup.html / .css / .js   toolbar UI
├── onboarding.html   first-install flow
├── domains.js        list of e-commerce hostnames
├── sounds/           drop your .mp3 files here
└── icons/            drop your .pngs here (see folder README)
```

## Storage schema

Lives in `chrome.storage.local`:

```json
{
  "enabled": true,
  "goal": "Tokyo trip",
  "selectedSound": "stop.mp3",
  "volume": 0.7,
  "triggerMode": "both",
  "mutedDomains": [],
  "onboarded": true
}
```

The popup writes here. The content script reads on load and listens for `chrome.storage.onChanged`, so edits in the popup take effect on every open tab without a reload.

## What's intentionally not in v0.1

- Spend tracking, target amounts, currencies — none of it. The financial logic is deliberately dumb so the comedy can carry the weight.
- Multiple goals, custom sound upload, Firefox port.
- Chrome Web Store submission. Personal install for now.

## Design handoff

Popup wireframes in Figma are placeholders — see `spending-angel-design-spec.md` for design intent. Replace shapes with final art, keep layer names consistent with the data model in `characters.js`.

## License

MIT. See `LICENSE`.
