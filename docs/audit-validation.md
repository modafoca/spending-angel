# Spending Angel — Audit Validation (2026-09-14)

Source audit: `~/Documents/ChatGPT/spending-angel/outputs/Spending_Angel_Audit.md` (audited commit `5d7153b`, which is current `main`).
Validated by Claude Code against the working tree on branch `fix/audit-2026-09`. Every citation below was re-read in the actual source; nothing here is taken on the audit's word.

## Verdict

All six ledger findings are **valid and reproducible from the code**. Severity ratings (Medium / P2, no Critical or High) are fair. No finding was rejected. Two "observations" are promoted into scope as small hardening / docs work.

| ID | Verdict | Evidence checked |
| --- | --- | --- |
| EXT-01 | **Valid.** `content.js` reads mode/blocklist once in `main()` and never again; `sendIntent()` has no policy check. `background.js` only re-registers scripts; Chrome does not remove already-injected scripts on unregister. `popup.js` pause/unwatch only edits storage. | `extension/content.js:19-38, 76-98`, `extension/background.js:49-92`, `extension/popup.js:80-99` |
| EXT-02 | **Valid.** Click listener at `content.js:70-74` never checks `e.isTrusted`. A page-dispatched `MouseEvent("click")` on a visible "Buy now" element produces a real intent. | `extension/content.js:70-74` |
| EXT-03 | **Valid.** `syncContentScripts()` is async, awaits `permissions.contains`, then unregisters + registers a single ID. Five listeners call it with no serialization, so an older "everywhere" run can finish after a newer "listed" run and re-register `*://*/*`. | `extension/background.js:49-92` |
| NATIVE-01 | **Valid.** `BridgeServer.handle()` accepts any `POST /intent` with a decodable body; no token, no Origin/Host check; `respond()` sends `Access-Control-Allow-Origin: *`. Throttle only limits rate, not authenticity. | `mac-app/Sources/SpendingAngel/BridgeServer.swift:108-146` |
| NATIVE-02 | **Valid.** `Store.init` loads `monthlyCount`/`countMonth` unchanged; only `recordCatch()` rolls the month. `DropdownView.stat` reads `store.monthlyCount` directly. | `Store.swift:33-35, 75-82`, `DropdownView.swift:114-135` |
| NATIVE-03 | **Valid.** `AppDelegate` calls `recordCatch()` and logs `catch.performed` BEFORE `overlay.performCatch()`, which silently returns when `panel != nil`. Measured clip durations confirm overlap is routine: wizard clips are 12.07s and 10.58s vs an 8s bridge throttle; hold = duration + 0.6s + 0.4s dismiss. Manual test path in `SpendingAngelApp.swift:16-19` has the same ordering. | `AppDelegate.swift:22-26`, `OverlayController.swift:14-16, 55-59`, `SpendingAngelApp.swift:16-19`, `afinfo` on all 13 MP3s |

Observations promoted into scope (owner decision, 2026-09-14):

- **Bridge hardening**: header cap (`maxHeaderBytes`) is only enforced when no `\r\n\r\n` is present yet; a 12KB header with a delimiter is accepted. Logged fields (`intent.id`, `hostname`) are unbounded on the 429 path, so a rejected request can write ~1MB log lines. Confirmed by reading `BridgeServer.swift:82-101, 122-127` and `validate()` at 174-180 (bounds hostname only).
- **README drift**: root `README.md` says load unpacked at repo root (manifest is in `extension/`), describes a DOM overlay; `mac-app/README.md` says no bridge. Confirmed by reading both files vs `extension/manifest.json` 0.4.0 and `AppDelegate.swift`.

Excluded hypotheses in the audit (XSS, SSRF, path traversal, smuggling, CI supply chain, etc.) were spot-checked and the exclusions are correct. Not in scope.

## Decisions taken with the owner (Ian, 2026-09-14)

1. **NATIVE-01 fix = pairing token with UI**, not env var + DevTools.
   - App generates a random token (32 bytes, hex, 64 chars) on first launch, persists in `UserDefaults` via `Store`, and shows it in the menu-bar dropdown under a "PAIR SENSOR" row with a Copy button (pixel-game theme, same components as the rest of `DropdownView`). A "Regenerate" affordance is acceptable but optional.
   - Extension options page gets a "Bridge token" field stored as `saBridgeToken` in `chrome.storage.local`. `background.js forward()` sends `Authorization: Bearer <token>`. If the token is missing, log `bridge.unpaired` (do not fetch) and set `bridgeOk:false` so the popup shows the unpaired state.
   - `BridgeServer` rejects requests whose bearer token does not match with **401** (constant-time compare), removes the wildcard CORS headers, and keeps `OPTIONS → 204` harmless. Token comparison must be a pure static function so it is unit-testable.
2. **Delivery = feature branch `fix/audit-2026-09` + PR to `main`.** Do NOT commit `sounds/stop.mp3` (pre-existing modification) or `extension/preview.html` (pre-existing untracked). Sub-agents do not commit; the orchestrator commits.
3. **Native tests stay in Swift Testing.** Run with:
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app`
   (Command Line Tools alone lack the `Testing` module. Never run `xcode-select`.)
   Extension tests: `node --test extension/tests/*.test.js` (Node 25 local, Node 20 in CI; use only APIs available in both).
4. **Extras in scope**: bridge hardening (header cap with delimiter, bounded `id` length in `validate()`, truncated log fields) and README drift fix.

## Baselines (before any change)

| Suite | Command | Result |
| --- | --- | --- |
| Extension | `node --test extension/tests/*.test.js` | 28 pass |
| Native | `DEVELOPER_DIR=... swift test --package-path mac-app` | 18 pass, 2 suites |
| Native build | `swift build --package-path mac-app` | OK |

## Constraints for implementers

- Keep the extension's privacy stance: payload stays `{id,type,trigger,hostname,ts}`; nothing else leaves the page.
- Keep the pixel-game UI language in `DropdownView` / options / popup (`Theme`, `.pixel()` font, `pxCorner`, `pixel.css`). Do not invent a new visual style.
- `content.js` runs as a classic script after `domains.js, log.js, detect.js, sites.js`; it may use `saShouldWatch`, `saHostInList`, `saHostnameMatches`, `saLog`. It cannot `require`.
- `sites.js` and `detect.js` export via `module.exports` for tests; `content.js` / `background.js` do not. A Node `vm` harness with a mocked `chrome` + minimal DOM is the accepted way to test them (see the pattern in `~/Documents/ChatGPT/spending-angel/outputs/evidence/extension-security-repro.cjs`; write our own clean version under `extension/tests/`).
- Swift Testing tests live in `mac-app/Tests/SpendingAngelTests/`. `OverlayController` creates `NSPanel`s; keep admission logic testable without a window server where practical (e.g. a pure `shouldAdmit`/state check), but do not over-engineer.
- Log helper: `Log.swift` (native) and `log.js` (extension). Structured event names are `dotted.snake` — keep the convention.
- Do not touch: `sounds/`, `extension/preview.html`, `*.ai`, PRM / mission markdown files at repo root.

## Audit's reference remediation (informational)

The audit's proposed patches are in `~/Documents/ChatGPT/spending-angel/outputs/evidence/extension-patched/` and inline in the audit for Swift. They are a reasonable starting point for EXT-01/02/03, NATIVE-02, NATIVE-03. The NATIVE-01 patch (env var token) is **superseded** by decision 1 above.
