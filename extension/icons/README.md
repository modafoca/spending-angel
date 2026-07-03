# icons/

Toolbar + store icons: the **$-halo mark** (same asset as the macOS app's
`menubar.svg`), cyan on a navy rounded badge so it reads on light and dark
Chrome toolbars.

## Sources (edit these, then regenerate)

- `icon.svg` — badge **with** border; used for 48 + 128 (larger sizes).
- `icon-16.svg` — borderless, bigger mark; used for 16 + 32 (so it stays
  legible at toolbar size).

## Regenerate the PNGs

```sh
INK=/Applications/Inkscape.app/Contents/MacOS/inkscape
"$INK" icon-16.svg --export-type=png --export-filename=icon16.png  -w 16  -h 16
"$INK" icon-16.svg --export-type=png --export-filename=icon32.png  -w 32  -h 32
"$INK" icon.svg    --export-type=png --export-filename=icon48.png  -w 48  -h 48
"$INK" icon.svg    --export-type=png --export-filename=icon128.png -w 128 -h 128
```

Wired in `manifest.json` under both `"icons"` and `"action".default_icon`.
