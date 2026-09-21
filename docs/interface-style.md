# Interface style

The cleaner-controls layout retains Spending Angel’s established pixel-game identity. Use the existing demo-era Theme.swift and pixel.css palette as the reference when changing layouts.

- Colors: near-black navy #0a0e1c, panel #131c38, light ink #ccdeff, muted blue #6b87cc, cyan #66d1ff, border #334f94. Gold #f4b740 is reserved for pending/attention states.
- Typography: bundled Silkscreen Regular/Bold for headings, labels, and primary controls. Browser body copy, domains, and inputs use system sans; connection codes and diagnostics use monospace. Keep Mac goal text in Silkscreen, as in the original dropdown.
- Scale: Mac and browser popups are 320 wide with 16-point/pixel side padding. Mac labels are 9, goal text 14, control text 11. Browser Settings headings are 20, section headings 13, buttons 11; body copy is 12–14.
- Roster: two rows of four 66-point slots with 8-point horizontal gaps. The first row holds existing guardians; the second reserves four dim question-mark slots for future guardians. Placeholders are informational, not selectable. Portraits retain smooth 4-point corners; other Mac frames and browser buttons use pixel staircase corners.
- Selection: cyan border and restrained glow on the selected guardian; dim unselected portraits. Keep original character art.
- Structure: pairing remains in Settings; daily on/off and snooze controls stay side by side. Chrome keeps plain-language site controls, with technical details under Troubleshooting.

Use real rendered SwiftUI and browser views to check font loading, clipping, and spacing; screenshots with synthetic data are previews, not evidence of live clipboard/audio behavior.
