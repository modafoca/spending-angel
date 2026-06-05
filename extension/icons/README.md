# icons/

No icons are bundled in v0.1 — Chrome shows the default puzzle-piece in the toolbar. Better than shipping a bad icon.

## To add real icons

1. Drop `icon16.png`, `icon48.png`, `icon128.png` here.
2. Add this block to `manifest.json`:

```json
"icons": {
  "16": "icons/icon16.png",
  "48": "icons/icon48.png",
  "128": "icons/icon128.png"
},
"action": {
  "default_popup": "popup.html",
  "default_title": "Spending Angel",
  "default_icon": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  }
}
```

Direction: hand-drawn cartoon angel — halo, little wings, slightly judgy face. Cream + navy palette to match the overlay. Looney Tunes shoulder-angel energy, not corporate flat design.
