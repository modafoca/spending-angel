# Spending Angel — Design Spec: audit fixes (branch `fix/audit-2026-09`)

Source brief: `docs/audit-validation.md` (binding). Audited commit `5d7153b` = current `main`.
Scope: EXT-01, EXT-02, EXT-03, NATIVE-01, NATIVE-02, NATIVE-03, plus bridge hardening and README drift.
This document is the contract for three parallel tracks (A = `extension/`, B = `mac-app/`, C = READMEs). Each track is implementable without reading the other track's code; the cross-track contract is fully stated in §3a/§3b and restated in §5.

---

## 1. Goals / non-goals

**Goals.** Close the six validated findings with the smallest change that is correct and testable: the content script honours the user's current site policy on every event instead of the policy captured at injection (EXT-01) and ignores script-dispatched clicks (EXT-02); content-script reconciliation in the service worker is serialized so a stale "everywhere" run can never overwrite a newer "listed" registration (EXT-03); the localhost bridge only accepts intents that carry a pairing token the app generated and showed the user, with no wildcard CORS (NATIVE-01); the dropdown's monthly stat is derived from the current calendar month rather than the stored counter (NATIVE-02); a catch is recorded and logged as performed only when the overlay actually admitted it (NATIVE-03). In the same PR: enforce the header cap even when the delimiter is present, bound `id` length, clip logged fields, and bring both READMEs in line with the two-half architecture and the new pairing step. Both test suites gain regression coverage and stay green with the exact commands in the brief.

**Non-goals.** No change to the intent payload shape (`{id,type,trigger,hostname,ts}` — nothing else leaves the page). No new visual style: everything reuses `Theme`, `.pixel()`, `PixelFrame`/`pxCorner`, `pixel.css`. No Native Messaging migration, no TLS, no per-request nonces, no token rotation policy, no keychain storage (UserDefaults is what `Store` uses for everything). No change to the 8 s bridge throttle, the 4 s extension fetch timeout, the 10 s connection timeout, the 1.5 s content cooldown, or the `429` semantics. No change to detection semantics in `detect.js`. Not touched: `sounds/`, `extension/preview.html`, `*.ai`, PRM/mission markdown at repo root. Sub-agents do not commit.

---

## 2. Architecture and trust boundaries after the change

Two halves, one trust boundary each:

- **Page → sensor (content script).** The page is hostile. The content script only acts on `isTrusted` clicks, re-reads the user's site policy from `chrome.storage.local` on every event, and emits at most `{id,type,trigger,hostname,ts}` to the service worker via `chrome.runtime.sendMessage`. The page cannot usefully reach the bridge itself: at most it can send an unauthenticated *simple* POST (`mode: "no-cors"`, safelisted Content-Type), which does arrive at `handle()` but is answered `401` before the body is decoded and is unreadable to the page. It cannot attach `Authorization`, because that is not a CORS-safelisted header and forces a preflight the bridge never satisfies (no `Access-Control-Allow-*` on any response), and it never sees the token in the first place.
- **Sensor (service worker) → app (bridge).** Anything on the Mac can open `127.0.0.1:17865`. The service worker proves it is the paired sensor by sending `Authorization: Bearer <token>`; the app compares it in constant time against the token it generated and showed in the dropdown. Wrong or missing token → `401`, nothing is logged that came from the body, nothing reaches the overlay.
- **Bridge → overlay.** The bridge hands validated intents to the app. The overlay is the single admission point: `performCatch` returns `Bool`, and only an admitted catch is counted and logged as `catch.performed`.

```mermaid
sequenceDiagram
    participant Page
    participant CS as content.js (per tab)
    participant SW as background.js
    participant App as BridgeServer (127.0.0.1:17865)
    participant OV as OverlayController
    participant ST as Store

    Page->>CS: trusted click on "Buy now"
    CS->>CS: isTrusted? cooldown? saShouldWatch(host, policy-from-storage)?
    CS->>SW: sendMessage {id,type,trigger,hostname,ts}
    SW->>SW: saBridgeToken present? (else bridge.unpaired, bridgeOk:false)
    SW->>App: POST /intent  Authorization: Bearer <token>
    App->>App: 405/404 → tokenMatches (401) → decode/validate (400) → throttle (429)
    App-->>SW: 200 (no CORS headers)
    App->>OV: performCatch(goal, character) -> Bool
    alt admitted
        OV-->>ST: recordCatch(); log catch.performed
    else busy
        OV-->>ST: log catch.skipped_busy (no count)
    end
    ST-->>ST: DropdownView shows catchCount(inMonthContaining: now)
```

Pairing is a one-time, human-mediated copy: app dropdown **PAIR SENSOR → Copy** → extension **Options → Bridge token → Save**. Regenerating in the app invalidates the extension's copy until it is pasted again.

---

## 3. API contracts

### 3a. Bridge HTTP contract (`BridgeServer.swift`)

**Endpoint.** `POST /intent HTTP/1.1` on `127.0.0.1:17865` (loopback only; `NWListener` with `requiredLocalEndpoint` unchanged). Path match is exact (`/intent`, no query string tolerance — `/intent?x` is `404`, unchanged).

**Required request headers.**

| Header | Requirement |
| --- | --- |
| `Authorization` | `Bearer <token>`. Header name matched case-insensitively; scheme `Bearer` matched case-insensitively; one or more spaces/tabs between scheme and token; token = remainder trimmed of whitespace; must be non-empty. First `Authorization` line wins if repeated. |
| `Content-Length` | Non-negative integer. Absent → treated as `0` (existing `contentLength()` semantics). Malformed → `400`. |
| `Content-Type` | Not enforced (extension sends `application/json`). |

**Body schema** (JSON, decoded into `Intent`; unchanged shape):

```json
{ "id": "uuid-string (optional, ≤ 128 UTF-8 bytes)",
  "type": "checkout_intent",
  "trigger": "click" | "load" | "simulated",
  "hostname": "1..253 UTF-8 bytes after trimming spaces",      ← (superseded by design-spec-r2 item 5: the 253-byte bound is on the raw value; trimming only feeds the non-empty check)
  "ts": 1700000000000 }
```

All length bounds in this spec are **UTF-8 byte counts** (`.utf8.count`), never Swift `String.count`. `String.count` counts extended grapheme clusters, and one cluster can carry thousands of combining marks, so a cluster-based bound is no bound at all (see §3e `Log.clip` and case 26).

**Status codes and exact evaluation order.** Steps 1–3 happen in `read()` while framing; 4–10 in `handle()`.

| Step | Status | Fires when |
| --- | --- | --- |
| 1 | `431 Request Header Fields Too Large` | Bytes before `\r\n\r\n` exceed `maxHeaderBytes` (8 192) — **checked both when the delimiter has not arrived yet (buffer > cap) and when it has (delimiter offset > cap)**. This is the hardening fix. |
| 2 | `400 Bad Request` | `Content-Length` present but unparseable/negative. |
| 3 | `413 Payload Too Large` | `Content-Length` > `maxBodyBytes` (1 000 000). |
| 4 | `204 No Content` | Method is `OPTIONS` (any path). **No auth required.** No CORS headers are sent, so a real browser preflight from a page fails by design; this is only kept so a stray preflight is answered instead of hanging. |
| 5 | `405 Method Not Allowed` | Method is not `POST` (after the OPTIONS check). |
| 6 | `404 Not Found` | Path ≠ `/intent`. |
| 7 | `401 Unauthorized` | `BridgeServer.tokenMatches(bearerToken(header), expected: tokenProvider())` is `false` — header missing, not `Bearer`, empty token, wrong length, or byte mismatch. Logged as `bridge.unauthorized` (info) with field `reason: "missing"` (when `bearerToken` returned `nil`) `\| "mismatch"` (a credential was presented). **The presented token is never logged. The body is never decoded or logged.** Steps 4–7 are one pure function, `gate(method:path:bearer:expected:)` (§3e), called first in `handle()` so the order is unit-tested, not just documented. |
| 8 | `400 Bad Request` | Body does not decode as `Intent` (`bridge.bad_payload`), or `validate()` returns a problem (`bridge.invalid_intent`, fields clipped — see caps). |
| 9 | `429 Too Many Requests` | Fewer than `minCatchInterval` (8 s) since the last **accepted** intent (`bridge.intent_throttled`). Unauthenticated or invalid requests never update `lastAccepted`. |
| 10 | `200 OK` | Accepted; `bridge.intent_received` logged; `onIntent(intent)` called; `lastAccepted = now`. |

**Response.** Always empty body. Headers, exactly:

```
HTTP/1.1 <status> <reason>\r\n
Content-Length: 0\r\n
Connection: close\r\n
WWW-Authenticate: Bearer realm="spending-angel"\r\n      ← 401 only
\r\n
```

`Access-Control-Allow-Origin` and `Access-Control-Allow-Headers` are **removed on every status** (including 204). The extension's service worker fetches with `host_permissions: ["http://127.0.0.1/*"]`, which exempts it from CORS, so no preflight occurs and no CORS headers are needed.

Two things in this block are new relative to the current `respond()` and must be added explicitly: `Connection: close` (today the response ends after `Content-Length: 0`), and the entry `401: "Unauthorized"` in the `reasons` dictionary `respond()` builds the status line from — without it the literal output is `HTTP/1.1 401 ` with an empty reason phrase.

**Timing.** `connectionTimeout` 10 s from accept to response (unchanged). `minCatchInterval` 8 s (unchanged). Extension-side fetch abort at `BRIDGE_TIMEOUT_MS` = 4 000 (unchanged). Token comparison is constant-time in the token content (length is public: 64).

**Size caps.**

| Cap | Value | Enforced where |
| --- | --- | --- |
| Header bytes (before delimiter) | `maxHeaderBytes = 8_192` | `read()` via `headerExceedsCap(_:delimiter:)` — both branches |
| Body bytes | `maxBodyBytes = 1_000_000` | `read()` (Content-Length gate, unchanged) |
| `id` length | `maxIDLength = 128` **UTF-8 bytes** (`i.id.utf8.count`; a UUID is 36) | `validate()` — `"bad id"` → `400` |
| `hostname` length | 1…253 **UTF-8 bytes** (`host.utf8.count`) after `trimmingCharacters(in: .whitespaces)` | `validate()` — the existing check switches from `host.count` to `host.utf8.count`; ASCII hostnames behave identically (superseded by design-spec-r2 item 5: the 253-byte bound is on the raw value; trimming only feeds the non-empty check) |
| Logged field truncation | `Log.clip(_:max:)` default `max = 256` **UTF-8 bytes**; result is the longest scalar-aligned prefix that fits in `max` bytes, plus `"…"` when cut, so `utf8.count <= max + 3` always holds | Every `BridgeServer` log field derived from request data (`intent_id`, `hostname`) **and** the interpolations inside `validate()`'s problem strings (`type`, `trigger` clipped to 64 bytes) |

### 3b. Pairing token contract

**Generation (Track B, `Store.swift`).**

```swift
/// 32 CSPRNG bytes → 64 lowercase hex chars. Pure; no UserDefaults.
static func generateBridgeToken() -> String
```
Uses `SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)` (`import Security`). If it returns anything but `errSecSuccess`, log `store.token_random_fallback` (error) and fill from `SystemRandomNumberGenerator` (`UInt8.random(in:using:)`, arc4random-backed on Apple platforms). Hex encoding: `String(format: "%02x", byte)` or a manual lookup — output must match `^[0-9a-f]{64}$`.

**Storage.** `UserDefaults.standard` key `"bridgeToken"`, a `String`. `Store.init` loads it; if the stored value is absent or does not match `^[0-9a-f]{64}$`, it calls `generateBridgeToken()`, assigns it, persists immediately (`d.set(_, forKey: "bridgeToken")`), and logs `store.token_generated` (info, field `reason: "first_launch" | "invalid_stored"`). Exposed as `@Published var bridgeToken: String` with the same `$bridgeToken.dropFirst().sink { d.set(...) }` persistence pattern as the other fields. **The token value is never logged** (log the last 4 characters at most if a log needs to identify it: field `token_tail`).

```swift
/// Mints a new token, invalidating any sensor paired with the old one.
func regenerateBridgeToken()        // sets bridgeToken; logs store.token_regenerated (info, token_tail)
```

**How BridgeServer receives the expected token.** Injected, read per request, so regeneration takes effect without restart and tests need no `Store`:

```swift
init(expectedToken: @escaping () -> String, onIntent: @escaping (Intent) -> Void)
```
`AppDelegate` passes `expectedToken: { Store.shared.bridgeToken }`.

**Pure static helpers (unit-tested).**

```swift
/// The bearer credential from a raw request header block, or nil when absent /
/// not a Bearer scheme / empty. Header name and scheme are case-insensitive.
static func bearerToken(_ header: String) -> String?

/// Constant-time comparison. false when `presented` is nil, when `expected` is
/// empty (never accept an unset token), or when lengths differ (token length is
/// public); otherwise ORs the XOR of every byte pair and returns diff == 0.
static func tokenMatches(_ presented: String?, expected: String) -> Bool
```
Implementation note for `tokenMatches`: convert both to `[UInt8]` via `.utf8`, loop over all indices with `diff |= a[i] ^ b[i]`, no early exit inside the loop.

**Regeneration semantics.** A new token replaces the old immediately in memory and in UserDefaults; the next bridge request from a sensor still holding the old token receives `401`, the extension logs `bridge.unauthorized` and the popup shows the re-pair state until the user pastes the new value. There is no grace period and no dual-accept window.

**Dropdown UI (Track B, `DropdownView.swift`).** New private section `pairRow`, inserted in `body`'s `VStack` **between `stat` and `controls`** (so it sits above the on/off button, below the brag box; `statHeight` and the 320 pt width are unchanged). Pixel theme only:

- Section label `Text("PAIR SENSOR")` — `.font(.pixel(9)).tracking(1).foregroundColor(Theme.pxDim)` (identical treatment to "SAVING FOR" / "PICK YOUR GUARDIAN").
- Below it an `HStack(spacing: 8)`:
  - Token box: `Text(store.bridgeToken)` in `.font(.pixel(9)).foregroundColor(Theme.pxInk)`, `.lineLimit(1)`, `.truncationMode(.middle)`, `.textSelection(.enabled)`, `.frame(maxWidth: .infinity, alignment: .leading)`, `.padding(.horizontal, 10).padding(.vertical, 9)`, `.background(pxCorner.fill(Theme.pxPanel))`, `.overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5))` — the same recipe as `goalField`.
  - Copy button: `Button { copyToken() } label: { Text(copied ? "COPIED" : "COPY").font(.pixel(9, bold: true)).foregroundColor(Theme.pxInk).padding(.horizontal, 10).padding(.vertical, 9).overlay(pxCorner.stroke(Theme.pxLine, lineWidth: 1.5)) }.buttonStyle(.plain)`. `copyToken()` does `NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.bridgeToken, forType: .string)`, logs `pair.token_copied` (info, `token_tail`), sets `@State private var copied = true` and resets it after 1.5 s via `DispatchQueue.main.asyncAfter`.
- Optional (allowed by the brief): a tertiary `linkButton("regenerate") { store.regenerateBridgeToken() }` right-aligned under the row, same helper as "▶ test"/"quit". No confirmation dialog.
- Hint line under the row: `Text("Paste it in the sensor's Options page.")` `.font(.pixel(8)).foregroundColor(Theme.pxDim)`.

### 3c. Extension storage contract (`chrome.storage.local`)

| Key | Type / default | Written by | Read by |
| --- | --- | --- | --- |
| `saMode` | `"listed" \| "everywhere"`, default `"listed"` | `background.seedIfNeeded`, `options.setMode` | `background.reconcileContentScripts`, `content.sendIntent` (**per event, new**), `content.main`, `popup.renderSite`, `options` |
| `saAllowlist` | `string[]`, seeded from `SPENDING_ANGEL_DOMAINS` on first run | `background.seedIfNeeded`, `popup.onSiteAction`, `options` | `background.reconcileContentScripts`, `content.sendIntent` (**new**), `popup`, `options` |
| `saBlocklist` | `string[]`, default `[]` | `background.seedIfNeeded`, `popup.onSiteAction`, `options` | `content.sendIntent` (**per event, replaces the once-at-injection read**), `popup`, `options` |
| `saInitialized` | `bool`, default `false` | `background.seedIfNeeded` | `background.seedIfNeeded` |
| `saLogs` | `LogEntry[]`, ring of `SA_LOG_MAX = 50` | `log.js saLog` (all surfaces) | `popup.renderEvents` |
| `lastIntent` | intent object or `null` | `content.sendIntent` (only after policy passes), `popup` simulate | `popup.renderIntent` |
| `bridgeOk` | `bool \| null` | `background.forward`; `options` token form (reset to `null` on a valid save and on unpair, **new**) | `popup.renderBridge`, `options.renderToken` (Round 2) |
| `bridgeAt` | epoch ms `\| null` | `background.forward`; `options` token form (reset to `null`, **new**) | `popup.renderBridge` |
| **`saBridgeToken`** (new) | `string` — 64 lowercase hex, or absent | `options` token form (`set` on valid input, `remove` on empty) | `background.forward`, `options.renderToken` (last 4 chars for the "Paired — …XXXX" state) |
| **`bridgeWhy`** (new) | `"unpaired" \| "unauthorized" \| "unreachable" \| null` | `background.forward` (set alongside `bridgeOk`; `null` on success/rejected-but-reachable); `options` token form (reset to `null`) | `popup.renderBridge`, `options.renderToken` (Round 2) |

Rule: every other key keeps its type, writers and readers exactly as today. One **meaning** changes: `bridgeOk === false` now also covers "unpaired" and "unauthorized" (previously it only meant "unreachable"), disambiguated by `bridgeWhy`. An old popup running against a new service worker therefore renders those as "App not reachable ✕" — the accepted one-PR degradation (case 3). Nothing new is written by the content script.

### 3d. Extension function contracts (Track A)

**`sites.js` — new pure helper (exported for tests, loaded everywhere `sites.js` already is).**

```js
// Bridge token as the user pasted it → canonical form, or "" for junk.
// Accepts surrounding whitespace and upper-case hex; anything else is rejected
// so a half-pasted token can't sit in storage looking valid.
function saNormalizeBridgeToken(raw) {
  const t = String(raw || "").trim().toLowerCase();
  return /^[0-9a-f]{64}$/.test(t) ? t : "";
}
```
Add to `module.exports`. Update the file's header comment to mention the pairing-token helper.

**`content.js`.**

- `sendIntent(trigger)` becomes `async`. Order, exactly:
  1. Synchronous cooldown gate (`now - lastTrigger < COOLDOWN_MS` → return) and stamp `lastTrigger = now` **before** any `await`, so concurrent events cannot both pass.
  2. `const cfg = await chrome.storage.local.get({ saMode: "listed", saAllowlist: [], saBlocklist: [] })`.
  3. `if (!saShouldWatch(host, { mode: cfg.saMode, allowlist: cfg.saAllowlist, blocklist: cfg.saBlocklist }))` → `saLog("debug", "sensor.suppressed", `${trigger} on ${host} — not watched right now`)` and **return without writing `lastIntent` or sending**.
  4. Build the unchanged payload (`id: crypto.randomUUID()`, `type`, `trigger`, `hostname: host`, `ts: now`), `saLog("info", "sensor.intent", …)`, `chrome.storage.local.set({ lastIntent })`, `chrome.runtime.sendMessage(payload).catch(() => {})`.
  5. The whole body is wrapped in `try { … } catch (e) { /* extension context invalidated (reload/uninstall) — nothing to do */ }`.
  `saShouldWatch` is the single policy oracle: listed mode → host must be in `saAllowlist`; everywhere mode → host must not be in `saBlocklist`. Non-watchable hosts (`saNormalizeHost` → `""`) are never watched.
- `attachClickWatcher()`: the capture-phase listener's **first statement** is `if (!e.isTrusted) return;` — no log, no storage write (a page dispatching thousands of synthetic clicks must not be able to thrash `saLogs`). Then the existing `findBuyButtonAncestor(e.target)` → `sendIntent("click")` (call is fire-and-forget: `void sendIntent("click")`).
- `main()`:
  1. `attachClickWatcher()` unconditionally — the old early-return for everywhere+blocklisted is removed because policy is now evaluated per event (a tab paused now may be resumed later without navigation).
  2. Load path: read `{ saMode }` once; schedule `setTimeout(() => { void sendIntent("load"); }, 800)` when `saMode === "listed"` **or** `saHostnameMatches(location.hostname, domainList)`. The scheduled `sendIntent` re-checks policy at fire time, so a site unlisted or paused during the 800 ms never fires.
- Globals used stay exactly `saNormalizeHost`, `saShouldWatch`, `saHostnameMatches`, `saIsBuyButtonText`, `saIsWholeBuyPhrase`, `saElementIsVisible`, `saLog`, `SPENDING_ANGEL_DOMAINS`. No `require`, no `module`.

**`background.js`.**

- Rename the existing async body to `async function reconcileContentScripts()` (contents unchanged: read mode/allowlist, check permissions, unregister `SCRIPT_ID`, register new matches, log `sites.registered` / `sites.register_failed`).
- New serialized wrapper with the **same public name** so all five call sites stay as they are:

  ```js
  // Reconciles run strictly one after another. Five listeners can fire within
  // the same tick (mode flip + list edit + permission grant); without a queue an
  // older "everywhere" run could finish after a newer "listed" run and
  // re-register *://*/*. The tail never rejects, so one failure can't wedge it.
  let scriptSyncTail = Promise.resolve();
  function syncContentScripts() {
    scriptSyncTail = scriptSyncTail
      .then(() => reconcileContentScripts())
      .catch((e) => saLog("error", "sites.sync_failed", String(e && e.message || e)));
    return scriptSyncTail;
  }
  ```
  Every reconcile reads storage at its own start, so the last queued run always reflects the latest state.
- `forward(payload)`:
  1. `const { saBridgeToken } = await chrome.storage.local.get({ saBridgeToken: "" }); const token = saNormalizeBridgeToken(saBridgeToken);` — this read is the **first statement** of the function, **before** `t0`, the `AbortController` and the 4 s `setTimeout` are created. Today those three sit above the `try`; they move below the unpaired check (or, equivalently, are created immediately before `fetch`). An unpaired/malformed-token call must leave no live timer behind: in the SW it would keep the worker awake for 4 s per dropped intent, and in the Node harness (where background `setTimeout` is real) it would keep the event loop alive for 4 s per test.
  2. If `token === ""`: `saLog("info", "bridge.unpaired", "no bridge token — open Options and paste the token from the app's PAIR SENSOR row", { intent_id: payload.id })`; `chrome.storage.local.set({ bridgeOk: false, bridgeAt: Date.now(), bridgeWhy: "unpaired" })`; **return without fetching** (no controller, no timer, no `finally` needed on this path).
  3. Otherwise create `t0`, the `AbortController` and the abort timer, then fetch as today with headers `{ "Content-Type": "application/json", "Authorization": `Bearer ${token}` }`; `finally { clearTimeout(timer) }` stays as today.
  4. Response handling: `res.ok` → `bridge.forwarded`, `{ bridgeOk: true, bridgeAt, bridgeWhy: null }`. `res.status === 401` → `saLog("error", "bridge.unauthorized", "app rejected the token — re-pair in Options", { intent_id, status: 401 })`, `{ bridgeOk: false, bridgeAt, bridgeWhy: "unauthorized" }`. Any other non-ok → existing `bridge.rejected` and `{ bridgeOk: true, bridgeAt, bridgeWhy: null }` (the app is reachable). Catch (abort/network) → existing `bridge.unreachable` and `{ bridgeOk: false, bridgeAt, bridgeWhy: "unreachable" }`.
  5. Update the header comment of `background.js` to say the SW authenticates to the bridge with the pairing token.

**`options.html` / `options.js` / `options.css`.**

- New first card (directly under the header, before the mode card): `<section class="card pixel" id="pair-card">` with `<h2>Pair with the app</h2>`, `<p class="note">Open Spending Angel in the menu bar, hit COPY under PAIR SENSOR, paste it here. The token never leaves this machine.</p>`, `<form id="token-form" class="add-row"><input id="token-input" class="field" type="text" placeholder="paste the 64-character token" autocomplete="off" spellcheck="false" /><button class="btn btn-cyan" type="submit">Save</button></form>`, `<p id="token-state" class="note"></p>`.
- `renderToken()`: reads `saBridgeToken`; state text is `Paired — token ends in …XXXX` (last 4 chars) or `Not paired — the app will not answer until you paste the token.`; the input shows the stored token masked as `••••…XXXX` via `placeholder`, with `value` empty (so a stray keystroke can't corrupt it).
- Submit handler: `const t = saNormalizeBridgeToken($("token-input").value)`. Empty raw input → `chrome.storage.local.remove(["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"])` (unpair; the popup reads those three with `null` defaults, so removing them is the same as nulling). Non-empty but `t === ""` → do not store; set `#token-state` to `hmm, that doesn't look like a token (64 hex characters)`. Valid → `chrome.storage.local.set({ saBridgeToken: t, bridgeOk: null, bridgeAt: null, bridgeWhy: null })` in **one** write, clear the field, `renderToken()`. Resetting all three bridge keys (not just `bridgeWhy`) matters: if only `bridgeWhy` were nulled, `bridgeOk` would still be `false` from the earlier unpaired/unauthorized write and the popup — which re-renders on `changes.bridgeWhy` — would show "App not reachable ✕ <old time>" at the exact moment the README tells the user to verify pairing. With the full reset the popup shows "Not tried yet" until "Simulate intent" runs.
- `renderAll()` calls `renderToken()` first. No new CSS classes needed; reuse `.card.pixel`, `.add-row`, `.field`, `.btn.btn-cyan`, `.note`.

**`popup.html` / `popup.js`.**

- `renderBridge(ok, at, why)`; `loadDebug()` also reads `bridgeWhy: null` and passes it; `chrome.storage.onChanged` re-runs `loadDebug()` when `changes.bridgeWhy` too.
- States: `ok === null/undefined` → "Not tried yet" (`status`); `ok` → "Connected ✓ <time>" (`status ok`); `why === "unpaired"` → "Not paired ✕ — paste the app's token" (`status bad`); `why === "unauthorized"` → "Token rejected ✕ — re-pair" (`status bad`); otherwise → "App not reachable ✕ <time>" (`status bad`).
- Under `#bridge-status` add `<p id="bridge-hint" class="hint" hidden><a href="#" id="open-options-pair">Pair in Options →</a></p>`; shown only for `unpaired`/`unauthorized`; click → `chrome.runtime.openOptionsPage()` (same handler pattern as `#open-options`).
- "Simulate intent" is unchanged and becomes the pairing smoke test: after pasting the token, clicking it should flip the status to Connected.

**Optional (Track A):** bump `manifest.json` version to `0.5.0` and the two footer strings (`sensor v0.4` → `v0.5`). Not required by the brief.

### 3e. Native function contracts (Track B)

**`OverlayController`.**

```swift
/// Whether a performance is on screen right now (admission gate + a
/// window-server-free way to reason about state).
var isPerforming: Bool { panel != nil }

/// Starts the catch sequence. Returns false — and does nothing else — when a
/// catch is already on screen or there is no main screen; true once the panel
/// is up. Callers must count/log the catch only on true.
@discardableResult
func performCatch(goal: String, character: CharacterID) -> Bool
```
Body: `guard panel == nil else { return false }` (silent — the caller logs); `guard let screen = NSScreen.main else { Log.error("overlay.no_screen", "no main screen — catch dropped"); return false }`; rest unchanged; `return true` at the end.

**Shared sequencing — new file `CatchRunner.swift` (the NATIVE-03 contract both call sites honour).**

```swift
/// One place that sequences a catch. Ask the overlay first; only when it
/// admitted the performance record the stat and log `catch.performed`,
/// otherwise log `catch.skipped_busy`. Both the bridge path and the manual
/// Test button go through here so the stat can never count a catch nobody saw.
enum CatchRunner {
    @discardableResult
    static func run(goal: String,
                    character: CharacterID,
                    source: String,                        // "bridge" | "test"
                    hostname: String,                      // intent hostname, or "manual test"
                    intentID: String?,
                    perform: (String, CharacterID) -> Bool,
                    record: () -> Void,
                    log: (String, String, [String: String]) -> Void = Log.info) -> Bool
}
```
Semantics: `let admitted = perform(goal, character)`; if `admitted` → `record()` then `log("catch.performed", hostname, fields)`; else `log("catch.skipped_busy", hostname, fields)`; return `admitted`. `fields = ["intent_id": intentID ?? "", "character": character.rawValue, "source": source]` (same keys as today). The `log` parameter defaults to `Log.info` so both production call sites below omit it; tests pass a capturing closure, which keeps `CatchRunnerTests` free of `Log.shared` side effects (its first write touches `UserDefaults.standard` for `installID` and creates `~/Library/Logs/SpendingAngel`) and lets them assert the exact event name and fields.

**`AppDelegate.applicationDidFinishLaunching`** — the bridge closure becomes:

```swift
let server = BridgeServer(expectedToken: { Store.shared.bridgeToken }) { [weak self] intent in
    guard Store.shared.onDuty else {
        Log.info("catch.skipped_off_duty", intent.hostname, ["intent_id": intent.id ?? ""])
        return
    }
    let character = Store.shared.nextCatchCharacter()   // honors Shake It Up
    CatchRunner.run(goal: Store.shared.goal, character: character,
                    source: "bridge", hostname: intent.hostname, intentID: intent.id,
                    perform: { g, c in self?.overlay.performCatch(goal: g, character: c) ?? false },
                    record: Store.shared.recordCatch)
}
```
`recordCatch()` and `catch.performed` are **no longer called before** `performCatch`. Known, accepted side effect: `nextCatchCharacter()` still advances the shuffle anti-repeat even when the catch is skipped.

**`SpendingAngelApp`** — the `onTest` closure becomes the same shape with `source: "test"`, `hostname: "manual test"`, `intentID: nil`, `perform: { g, c in delegate.overlay.performCatch(goal: g, character: c) }`, `record: store.recordCatch`.

**`Store`.**

```swift
/// The count to *display*: the stored counter only if it belongs to the month
/// containing `date`, else 0. `recordCatch()` still rolls the stored month.
static func catchCount(monthlyCount: Int, countMonth: String,
                       at date: Date, calendar: Calendar = .current) -> Int
func catchCount(inMonthContaining date: Date, calendar: Calendar = .current) -> Int   // delegates to the static with self's fields
```
Static body: `monthKey(date, calendar: calendar) == countMonth ? monthlyCount : 0`. `Store.init` is otherwise unchanged (no rollover at launch; the display derives).

**`DropdownView.stat`** — wrap the existing box in `TimelineView(.everyMinute) { context in … }` and replace both reads of `store.monthlyCount` with `let count = store.catchCount(inMonthContaining: context.date)`; `count == 0` → "No catches yet this month.", else `brag(count:goal:)`. Keep the `.frame(minHeight: statHeight, maxHeight: statHeight)` / padding / `pxCorner` modifiers on the outer view so the window never resizes. Optional: pass `context.date` into the streak line too (`Store.daysBetween(last, context.date)`); not required.

**`BridgeServer` additions** (all `static`, unit-tested unless noted):

```swift
static let maxIDLength = 128   // UTF-8 bytes

/// Pure framing check used by read() in BOTH branches: with the delimiter in
/// hand, the header is the bytes before it; without it, the whole buffer is
/// header-so-far. Either way it must fit maxHeaderBytes.
static func headerExceedsCap(_ buf: Data, delimiter: Range<Data.Index>?) -> Bool

/// The pre-body decision, in the exact order of §3a steps 4-7:
/// OPTIONS → 204 · not POST → 405 · path ≠ /intent → 404 ·
/// !tokenMatches(bearer, expected) → 401 · otherwise nil (proceed to decode).
/// Pure so the order is pinned by tests; handle() calls it first.
static func gate(method: String, path: String, bearer: String?, expected: String) -> Int?

static func bearerToken(_ header: String) -> String?                 // §3b
static func tokenMatches(_ presented: String?, expected: String) -> Bool   // §3b
static func validate(_ i: Intent) -> String?   // adds: if let id = i.id, id.utf8.count > maxIDLength → "bad id"; hostname check becomes host.utf8.count <= 253; clip type/trigger in problem strings via Log.clip(_, max: 64)
```
`headerExceedsCap` body, verbatim — the offset must be relative to the slice, not absolute, because a `Data` slice does not necessarily start at index 0 (today `read()` builds `buf` from `Data()` + `append`, so `startIndex == 0` happens to hold, but a future `subdata`/slice refactor must not silently break the cap):

```swift
let headerBytes = delimiter.map { $0.lowerBound - buf.startIndex } ?? buf.count
return headerBytes > maxHeaderBytes
```

`read()` computes `let sep = buf.range(of: Data("\r\n\r\n".utf8))`; `if Self.headerExceedsCap(buf, delimiter: sep) { log bridge.bad_request "headers exceed …"; respond 431; return }` **before** the existing Content-Length handling; then proceeds as today. `handle` gains the credential: `private func handle(method: String, path: String, bearer: String?, body: Data, conn: NWConnection, timeout: DispatchWorkItem)`. Its first statement is `if let status = Self.gate(method: method, path: path, bearer: bearer, expected: expectedToken()) { if status == 401 { Log.info("bridge.unauthorized", "rejected", ["reason": bearer == nil ? "missing" : "mismatch"]) }; respond(conn, status: status, timeout: timeout); return }`, replacing the three inline `OPTIONS`/`POST`/`/intent` guards; decoding, `validate`, and the throttle follow unchanged. Keep a one-line comment above the throttle: `// Only reached for authenticated, valid intents — lastAccepted never moves for a 401/400.` (case 23; the curl checklist in §6c covers the live path).

`respond()`: the header block is exactly §3a. Concretely, relative to the current code: drop the two `Access-Control-*` lines, add `Connection: close\r\n`, add `401: "Unauthorized"` to the `reasons` dictionary, and branch on `status == 401` to append `WWW-Authenticate: Bearer realm="spending-angel"\r\n`.

**`Log`** — new pure helper next to the level functions:

```swift
/// Bounded copy of an untrusted string for log fields: the longest prefix that
/// fits in `max` UTF-8 bytes without splitting a scalar, plus "…" when cut.
/// Bounds BYTES, not Characters: one grapheme cluster can carry thousands of
/// combining marks, so `prefix(max)` on a String is no bound at all. Keeps a
/// hostile 1 MB id from becoming a 1 MB log line.
static func clip(_ value: String, max: Int = 256) -> String
```
Body, verbatim:

```swift
if value.utf8.count <= max { return value }
var out = String.UnicodeScalarView()
var used = 0
for scalar in value.unicodeScalars {
    let n = scalar.utf8.count
    if used + n > max { break }
    out.append(scalar); used += n
}
return String(out) + "…"
```
Cutting on scalars (not raw bytes + `String(decoding:as:)`) means no U+FFFD replacement character and a hard guarantee `result.utf8.count <= max + 3` (`"…"` is 3 bytes). For ASCII input this is byte-for-byte the old "first `max` characters + …" behaviour, so the existing 300-char test expectation (`count == 257`) still holds. Every `BridgeServer` log field built from request data goes through it (`intent_id`, `hostname` on `bridge.invalid_intent`, `bridge.intent_throttled`, `bridge.intent_received`).

---

## 4. Edge cases (expected behaviour)

1. **Extension has no token, app running.** `forward()` logs `bridge.unpaired`, sets `bridgeOk:false, bridgeWhy:"unpaired"`, no fetch; popup shows "Not paired ✕" + "Pair in Options →". Content script still writes `lastIntent` (detection worked; delivery didn't).
2. **App token regenerated while the extension holds the old one.** Next POST → `401`; app logs `bridge.unauthorized reason:mismatch`; extension logs `bridge.unauthorized`, `bridgeWhy:"unauthorized"`; popup "Token rejected ✕ — re-pair". Recovers as soon as the new token is saved in Options (no reload of extension or app needed; both read per request); the save also resets `bridgeOk`/`bridgeAt`/`bridgeWhy` to `null`, so the popup reads "Not tried yet" until the next intent or "Simulate intent" flips it to "Connected ✓".
3. **New app, old extension (no `Authorization`).** `401 reason:missing`; the old extension logs `bridge.rejected 401` and keeps `bridgeOk:true`. Acceptable one-PR skew; README tells the user to reload the extension after pulling.
4. **New extension, old app.** Old app ignores the header and answers `200`; works.
5. **Tab injected in everywhere mode, then site paused, then resumed — no navigation.** Click while paused → `sensor.suppressed`, nothing stored/sent; click after resume → intent emitted. Same for listed mode "Stop watching"/"Watch this site".
6. **Load-path timer already scheduled, site unlisted during the 800 ms.** `sendIntent("load")` re-reads policy at fire time → suppressed.
7. **Everywhere → listed while a reconcile is in flight.** The second `syncContentScripts()` waits for the first; it reads `saMode:"listed"` at its own start; final registration = allowlist origins only. A reconcile that throws logs `sites.sync_failed` and the tail keeps accepting calls.
8. **`isTrusted === false` (page-dispatched `MouseEvent("click")` on a visible "Buy now").** Listener returns at its first line; no `lastIntent`, no `saLogs` entry, no message. Trusted clicks unaffected.
9. **Month boundary while the dropdown is open.** `TimelineView(.everyMinute)` re-evaluates at the next minute tick; `catchCount(inMonthContaining:)` returns 0 → "No catches yet this month." with no stored change. The next `recordCatch()` rolls `countMonth` and starts from 1.
10. **App restarted in a new month with an old count (e.g. `countMonth:"2026-08", monthlyCount:7` on 2026-09-14).** Dropdown shows 0 immediately; stored fields stay until the next catch rolls them.
11. **Manual "▶ test" while a catch is on screen.** `performCatch` → `false`; `catch.skipped_busy source:test`; no count, no `catch.performed`. Same for a bridge intent that passes the 8 s throttle while a 12 s wizard line is still holding the overlay (`source:bridge`).
12. **No main screen (`NSScreen.main == nil`).** `overlay.no_screen` logged, `performCatch` → `false`, not counted.
13. **12 KB header that includes `\r\n\r\n`** (single 64 KB TCP read). `headerExceedsCap` sees delimiter offset > 8 192 → `431`. Previously accepted.
14. **Header delimiter split across chunks, total header < 8 KB.** Accumulates as today; cap check on each pass; proceeds normally.
15. **950 KB `id` with valid `Content-Length` and valid token.** Body read (≤ 1 MB) → decodes → `validate` → `id.utf8.count > 128` → `"bad id"` → `400`; `bridge.invalid_intent` logs `intent_id` clipped to ≤ 259 bytes (256 + `"…"`). Without a valid token → `401` first and nothing from the body is logged.
16. **`type` of 900 KB.** `validate` problem string uses `Log.clip(i.type, max: 64)` → bounded log line (≤ 67 bytes of `type` inside it).
26. **Combining-mark padding (grapheme-cluster attack).** `id` = 128 clusters each of `"a"` + 7 000 × U+0301 (~1.8 MB, but `id.count == 128`): rejected by `Content-Length > maxBodyBytes` → `413` before decoding. A ~900 KB variant that fits the body cap decodes, then `id.utf8.count > 128` → `"bad id"` → `400`, and the logged `intent_id` is ≤ 259 bytes. The same payload shape in `hostname` → `host.utf8.count > 253` → `"bad hostname"`; in `type`/`trigger` → the problem string stays bounded by `Log.clip(_, max: 64)`. None of this holds with `String.count`/`prefix` — hence the byte-based rule in §3a. (superseded by design-spec-r2 item 5: the 253-byte bound is on the raw value; trimming only feeds the non-empty check)
17. **`Content-Length` absent on `POST /intent` with a token.** Treated as 0 → empty body → `bridge.bad_payload` → `400`. Without a token → `401`.
18. **`OPTIONS /intent` (any origin, any headers).** `204`, no auth, no CORS headers → a page-originated preflight fails CORS; the extension SW never sends one.
19. **`Authorization: bearer   <tok>` (lower-case scheme, extra spaces) or `AUTHORIZATION:` header name.** Accepted. `Authorization: Basic xyz` → `401 reason:missing`. `Authorization: Bearer` (empty) → `401 reason:missing`.
20. **Token pasted with upper-case hex / surrounding whitespace.** `saNormalizeBridgeToken` lowercases + trims before storing; the app's token is lowercase, so bytes match.
21. **Empty string saved in Options.** Unpairs (`remove(["saBridgeToken", "bridgeOk", "bridgeAt", "bridgeWhy"])`); the popup shows "Not tried yet" until the next intent, which then lands as case 1. Half-pasted 40-char token → not stored, inline hint.
22. **Stored `bridgeToken` corrupted (not 64 hex) in UserDefaults.** `Store.init` regenerates (`store.token_generated reason:invalid_stored`); the sensor will need re-pairing (surfaces as case 2).
23. **Two intents 3 s apart, both authenticated.** Second → `429` (unchanged). Unauthenticated requests never touch `lastAccepted`, so they cannot delay a legitimate catch.
24. **App not running.** `fetch` throws / aborts at 4 s → `bridge.unreachable`, `bridgeWhy:"unreachable"`; popup "App not reachable ✕".
25. **Extension context invalidated (extension reloaded) while a tab still has the old content script.** `sendIntent`'s `try/catch` swallows the `chrome.*` throw; no uncaught error in the page console.

---

## 5. Architectural dependencies and ordering

**Track A — `extension/`** (Node harness + tests): `content.js` (EXT-01, EXT-02), `background.js` (EXT-03, NATIVE-01 client side), `sites.js` (`saNormalizeBridgeToken`), `options.html` / `options.js` (token card), `popup.html` / `popup.js` (paired/unpaired state), `tests/harness.js` (new), `tests/content.test.js` (new), `tests/background.test.js` (new), `tests/sites.test.js` (extend). Optional: `manifest.json` 0.5.0 + footers. No change to `detect.js`, `domains.js`, `log.js`, `*.css`, `preview.html`.

**Track B — `mac-app/`**: `BridgeServer.swift` (NATIVE-01 server side, hardening), `Store.swift` (token + `catchCount`), `DropdownView.swift` (PAIR SENSOR row, `TimelineView` stat), `OverlayController.swift` (`performCatch -> Bool`, `isPerforming`), `CatchRunner.swift` (new), `AppDelegate.swift`, `SpendingAngelApp.swift`, `Log.swift` (`clip`), `Tests/SpendingAngelTests/BridgeAuthTests.swift` (new), `Tests/SpendingAngelTests/CatchRunnerTests.swift` (new), `BridgeParsingTests.swift` (extend), `StoreDateTests.swift` (extend). No change to `Package.swift` (Security framework is available without a new dependency; `import Security` in `Store.swift`).

**Track C — READMEs**: `README.md`, `mac-app/README.md`. Depends on A and B only for accuracy of what it describes (§7); can be written from this spec.

**Shared NATIVE-01 contract (both tracks must honour, verbatim):** header `Authorization: Bearer <token>`; token = 64 lowercase hex chars from 32 random bytes; app answers `401` (empty body, `WWW-Authenticate: Bearer realm="spending-angel"`) on missing/mismatch; app sends no CORS headers; `OPTIONS` → `204` without auth; success stays `200`; the extension does not fetch at all when it holds no token.

**Must land together (one PR):** A's `forward()` bearer header and B's `401` enforcement — shipping B alone silently breaks every existing install (case 3); shipping A alone is harmless. `CatchRunner.swift` must land with the `performCatch -> Bool` change (the `@discardableResult` keeps old call sites compiling, but the ordering fix is the point). The README pairing section must land with A+B. CI (`.github/workflows/ci.yml`) needs no change: the extension job's glob `extension/tests/*.test.js` will pick up the new test files and skip `harness.js`.

**Order of work within a track:** A: `sites.js` helper → `content.js` → `background.js` → options/popup → harness → tests. B: `Log.clip` → `BridgeServer` statics → `Store` token/`catchCount` → `OverlayController` → `CatchRunner` → `AppDelegate`/`App` → `DropdownView` → tests. Run the suite after each step; the baselines (28 / 18) must never dip.

---

## 6. Test plan

### 6a. Extension — Node `vm` harness (`extension/tests/harness.js`)

Runs with `node --test extension/tests/*.test.js` on Node 20 and 25. Use only: `node:test` (`test`, `describe`), `node:assert/strict`, `node:vm`, `node:fs`, `node:path`, `node:crypto` (`randomUUID`), `setImmediate`, global `AbortController`. Do **not** use `test.mock.timers`, `Promise.withResolvers`, `Array.prototype.toSorted`, or `--experimental-*` flags. `harness.js` is not a `*.test.js` file so the glob never runs it directly.

`harness.js` exports two loaders. Both read the **real** files from `path.join(__dirname, "..")` and evaluate them in one `vm.createContext` in manifest order, so the tests exercise the shipped code, not a copy.

```js
// loadContentScript({ hostname, config, clock }) -> ctx handle
//   evaluates domains.js, log.js, detect.js, sites.js, content.js (that order)
// loadBackground({ config, permissions, fetchImpl }) -> ctx handle
//   evaluates domains.js, log.js, sites.js, background.js (importScripts is a no-op:
//   the harness has already evaluated the three files into the same context)
```

**Mocked surface (the complete list; anything else the scripts touch must be added here, not stubbed ad hoc in a test):**

| Global | Content ctx | Background ctx | Behaviour |
| --- | --- | --- | --- |
| `chrome.storage.local.get(defaults[, cb])` | ✓ | ✓ | Two forms, mirroring Chrome. **Promise form** (no `cb`): returns `Promise` of `{...defaults, ...store}` (content/background use this). **Callback form** (`cb` given): schedules `cb({...defaults, ...store})` on a microtask and returns `undefined` — it **never rejects and never returns a Promise** (log.js's `saLog` uses this form and ignores the return value; a Promise that could reject here would surface as an unhandled rejection on the next `saLog`, which `node --test` counts as a failure). |
| `chrome.storage.local.set(obj)` | ✓ | ✓ | Merges into the in-memory `store`, pushes `obj` to `handle.writes`, resolves. |
| `chrome.storage.local.remove(key)` | — | ✓ | Deletes; resolves. |
| `chrome.storage.onChanged.addListener(fn)` | ✓ | ✓ | Captures into `handle.listeners.storageChanged` (array). |
| `chrome.runtime.sendMessage(p)` | ✓ | — | Pushes to `handle.messages`; resolves. |
| `chrome.runtime.onInstalled/onStartup/onMessage.addListener(fn)` | — | ✓ | Captured into `handle.listeners.<name>`. |
| `chrome.permissions.contains({origins})` | — | ✓ | Delegates to test-supplied `permissions(origins) -> Promise<bool>` (default: `async () => true`). A test that needs to hold a reconcile mid-flight supplies an impl that returns a promise whose resolver it keeps (`let release; const gate = new Promise((r) => { release = r; });` — not `Promise.withResolvers`). |
| `chrome.permissions.onAdded/onRemoved.addListener` | — | ✓ | Captured. |
| `chrome.scripting.registerContentScripts(entries)` | — | ✓ | Rejects with `Error("Duplicate script ID 'sa-detector'")` if `handle.active` is set (mirrors Chrome); else sets `handle.active = entries[0]` and pushes to `handle.registrations`. If `handle.failNextRegister(err)` is armed, rejects with `err` once instead (registers nothing). |
| `chrome.scripting.unregisterContentScripts({ids})` | — | ✓ | Rejects with `Error("Nonexistent script ID 'sa-detector'")` when `handle.active` is `null` (mirrors Chrome on the first run — this is exactly the path `reconcileContentScripts` guards with its `try {} catch { /* none yet */ }`; a mock that never rejects would let a regression that drops that catch pass the suite); otherwise sets `handle.active = null` and resolves. |
| `importScripts()` | — | ✓ | No-op. |
| `fetch(url, init)` | — | ✓ | Test-supplied `fetchImpl`; the harness records `{url, init}` into `handle.fetches` before delegating. Default impl resolves `{ ok: true, status: 200 }`. |
| `AbortController`, `setTimeout`, `clearTimeout` | ✓ (timers captured) | ✓ (real, for the abort timer; tests use a fetchImpl that rejects with `{name:"AbortError"}` instead of waiting) | Content ctx: `setTimeout(fn, ms)` pushes `{fn, ms}` to `handle.timers` and never fires on its own; `handle.fireTimers()` runs and clears them. |
| `Date` | ✓ | ✓ | `class FakeDate extends Date { static now() { return handle.clock.now; } }` so `Date.now()` is controllable while `new Date().toISOString()` (log.js) still works. `handle.clock.advance(ms)`. |
| `crypto.randomUUID` | ✓ | ✓ | `require("node:crypto").randomUUID`. |
| `console` | ✓ | ✓ | `{ log(){}, error(){} }` collecting into `handle.console` (log.js prints). |
| `location` | ✓ | — | `{ hostname }` from options. |
| `document.addEventListener(type, fn, capture)` | ✓ | — | Captured into `handle.listeners.click`; `handle.click({ target, isTrusted })` invokes it. |
| `getComputedStyle(el)` | ✓ | — | Returns `el.style || { display: "block", visibility: "visible", opacity: "1" }`. |
| `window` | ✓ | — | `undefined` is fine: domains.js guards with `typeof window`. Do not define it. |
| `saLog` | — | — | **Not mocked** — the real `log.js` is loaded and its entries land in `store.saLogs`, so tests assert on `handle.store.saLogs` (event names) rather than on a spy. |

**Handle knobs (part of the mocked surface; tests use these, never ad-hoc monkey-patching of `ctx.chrome`):**

| Knob | Ctx | Behaviour |
| --- | --- | --- |
| `handle.setConfig(obj)` | both | `Object.assign(store, obj)`; does **not** fire `storageChanged` listeners (tests that want the listener invoke it themselves). |
| `handle.failNextGet(err)` | both | The next **promise-form** `storage.local.get` rejects with `err` (consumed by exactly one call). Callback-form calls are never affected — see the `get` row — so `saLog` keeps working while a test exercises a rejecting `get` in `sendIntent`/`reconcileContentScripts`. |
| `handle.failNextRegister(err)` | background | The next `registerContentScripts` rejects with `err` once. |
| `handle.fireTimers()` | content | Runs and clears every captured `setTimeout`. |
| `handle.click({ target, isTrusted })` | content | Invokes the captured capture-phase click listener with that event object. |
| `handle.clock.advance(ms)` | both | Moves `Date.now()`. |
| `handle.tick()` | both | `new Promise((r) => setImmediate(r))`. |

`loadContentScript` returns synchronously after evaluating the scripts; `main()` has already started but is parked on its first `await storage.get({ saMode })`, so **the 800 ms load timer only exists after `await handle.tick()`**. Every test that asserts on `handle.timers` right after load must `await handle.tick()` first (the harness does not do it for you, so a test can also observe the pre-await state if it wants to).

Element fixtures: `handle.buyButton()` returns `{ innerText: "Buy now", parentElement: null, matches: (sel) => sel !== "a", getAttribute: () => "", getBoundingClientRect: () => ({ width: 100, height: 30 }) }`; `handle.buyLink(text)` same with `matches: (sel) => sel === "a" || sel.includes("a,") || sel.includes(" a")`; `handle.plainSpan()` never matches.

`await handle.tick()` = `new Promise((r) => setImmediate(r))` — enough to flush the `await storage.get` chain in `sendIntent`/`main`; call it twice where a test needs both the storage read and the subsequent `set`.

### 6b. Extension test cases

**`tests/content.test.js` — EXT-01 (policy per event).**
- `listed: click on an allowlisted host emits one intent` — config `{saMode:"listed", saAllowlist:["shop.example.test"]}`; trusted click; `messages.length === 1`, `messages[0].trigger === "click"`, `hostname === "shop.example.test"`, `writes` contains `lastIntent`, `saLogs` has `sensor.intent`.
- `everywhere: site paused after injection is suppressed without navigation` — start unpaused; `setConfig` blocklist `["shop.example.test"]`; click → `messages.length === 0`, no `lastIntent` write, `saLogs` last event `sensor.suppressed` (debug) and no `sensor.intent`.
- `everywhere: initially paused, resumed later, emits` — start paused; click → 0; unpause; `clock.advance(2000)`; click → 1.
- `listed: host removed from the list suppresses the queued load AND later clicks` — `await tick()` after load, then `timers.length === 1`; `setConfig({ saAllowlist: [] })`; `fireTimers()`; `await tick()` twice; `clock.advance(2000)` (so the click is judged by policy, not the cooldown); click → 0 messages, 0 `lastIntent` writes, two `sensor.suppressed` entries.
- `everywhere: load fires only on known shopping domains` — (each after `await tick()`) hostname `amazon.com` → one timer; hostname `blog.example.test` → zero timers; listed mode `blog.example.test` in allowlist → one timer.
- `everywhere: click watcher is attached even when the host is paused at injection` — paused config; `listeners.click` defined.
- `cooldown still applies` — two trusted clicks 100 ms apart → 1 message; `advance(1500)` → next click → 2.
- `does not throw when chrome.storage rejects (context invalidated)` — `handle.failNextGet(new Error("Extension context invalidated."))` (promise-form only, so log.js's callback-form `get` is untouched); trusted click; `await tick()` twice; no unhandled rejection (install a `process.on("unhandledRejection")` guard at the top of the test file that fails the test), 0 messages, 0 writes, `saLogs` unchanged (the catch is silent by contract).

**`tests/content.test.js` — EXT-02 (isTrusted).**
- `synthetic click is ignored entirely` — `click({ target: buyButton(), isTrusted: false })`; `messages.length === 0`, `writes.length === 0`, `saLogs.length` unchanged (**no log line, no storage write**).
- `trusted click on the same element emits` — same element, `isTrusted: true` → 1.
- `event without isTrusted (undefined) is ignored` — negative case for hand-rolled event objects.
- `synthetic click flood does not grow saLogs` — 200 synthetic clicks → `saLogs.length` unchanged.

**`tests/background.test.js` — EXT-03 (serialized sync).**
- `an older everywhere reconcile cannot overwrite a newer listed one` — `permissions` impl returns the held `gate` promise for `*://*/*` and `true` otherwise; config everywhere; `const p1 = syncContentScripts()`; `await tick()` (so run 1 is parked on the gate); `setConfig({ saMode: "listed", saAllowlist: ["shop.example.test"] })`; `const p2 = syncContentScripts()`; assert `active === null` and `registrations.length === 0` while gated; `release(true)`; `await Promise.all([p1, p2])`; `registrations.length === 2`; `active.matches` deep-equals `saHostToOrigins("shop.example.test")` and does not include `*://*/*`.
- `concurrent calls run in order` — three calls with distinct configs; `registrations` matches arrays in call order.
- `a rejecting reconcile logs sites.sync_failed and does not wedge the tail` — three **sequential, awaited** calls, arming each knob only after the previous call has fully resolved (a knob armed while a reconcile is still in flight would be consumed by that reconcile's own `get(DEFAULTS)`, because `syncContentScripts()` defers `reconcileContentScripts()` into a `.then`):
  1. `handle.failNextRegister(new Error("boom"))`; `await syncContentScripts()` → `saLogs` has `sites.register_failed` and **no** `sites.sync_failed` (the throw is caught inside reconcile); `active === null`.
  2. `handle.failNextGet(new Error("storage gone"))`; `await syncContentScripts()` → resolves (never rejects); `saLogs` has `sites.sync_failed` with the message `"storage gone"`.
  3. `await syncContentScripts()` → `active` set, `registrations.length === 1`.
- `syncContentScripts returns a promise that resolves after its reconcile` — await it; `active` set.
- `storage.onChanged listener triggers a sync only for policy keys` — invoke captured listener with `{ bridgeOk: {} }` → `registrations` unchanged; with `{ saMode: {} }` → +1.

**`tests/background.test.js` — NATIVE-01 (client side).**
- `forward without a token does not fetch and marks unpaired` — no `saBridgeToken`; invoke the captured `onMessage` listener with a `checkout_intent`; `await tick()`; `fetches.length === 0`; last write `{ bridgeOk: false, bridgeWhy: "unpaired" }`; `saLogs` has `bridge.unpaired`. The test file must finish promptly under `node --test`: if this or the malformed-token case leaves the process alive for ~4 s, `forward()` created its abort timer before the unpaired return (§3d step 1) — treat that as a failure, not a slow test.
- `forward with a token sends Authorization: Bearer` — token stored; `fetches[0].init.headers.Authorization === "Bearer " + token`; `Content-Type` still `application/json`; body JSON equals the payload; write `{ bridgeOk: true, bridgeWhy: null }`; `bridge.forwarded` logged.
- `401 marks unauthorized` — fetchImpl `{ ok: false, status: 401 }` → `bridge.unauthorized` (error), write `{ bridgeOk: false, bridgeWhy: "unauthorized" }`.
- `429 is rejected-but-reachable` — `{ ok: false, status: 429 }` → `bridge.rejected`, `bridgeOk: true`.
- `network failure is unreachable` — fetchImpl rejects `TypeError` → `bridge.unreachable`, `bridgeWhy: "unreachable"`; AbortError variant → message contains "timed out".
- `malformed stored token is treated as unpaired` — `saBridgeToken: "abc"` → no fetch, `bridge.unpaired`.
- `non-intent messages are ignored` — `onMessage` with `{type:"other"}` → no fetch, no writes.

**`tests/sites.test.js` — additions.**
- `saNormalizeBridgeToken accepts 64 hex, trims and lowercases` — `"  " + "AB".repeat(32) + "\n"` → `"ab".repeat(32)`.
- `saNormalizeBridgeToken rejects junk` — `""`, `null`, 63 chars, 65 chars, `"g".repeat(64)`, token with an inner space → `""`.

### 6c. Native — Swift Testing (`mac-app/Tests/SpendingAngelTests/`)

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app`. All new tests avoid the heavy objects: no `Store()` instance (its `init` writes `UserDefaults.standard`), no `NSPanel`, no `NWListener`. They also avoid `Log.shared` on their happy paths — `CatchRunnerTests` inject a capturing `log` closure (§3e) — with one known exception already present today: `Store.monthKey`'s error path calls `Log.error`, which the `catchCountUnknownMonthKey` case does not reach (an unknown `countMonth` string never makes the calendar fail). Any test that does reach `Log` writes a real line under `~/Library/Logs/SpendingAngel` and a `installID` default; harmless on CI, but not "pure", so do not add such a path without saying so.

**`BridgeAuthTests.swift` (NATIVE-01).**
- `tokenMatchesExact` — equal 64-hex strings → `true`.
- `tokenMatchesRejectsNil` — `nil` → `false`.
- `tokenMatchesRejectsEmptyExpected` — `("x", expected: "")` → `false`; `("", expected: "")` → `false`.
- `tokenMatchesRejectsLengthMismatch` — 63 vs 64 → `false`.
- `tokenMatchesRejectsSingleByteDifference` — flip the last char → `false`; flip the first → `false`.
- `tokenMatchesIsCaseSensitive` — upper-case copy → `false` (the extension lowercases; the app must not).
- `bearerTokenParsesStandardHeader` — `"POST /intent HTTP/1.1\r\nAuthorization: Bearer abc\r\nHost: x"` → `"abc"`.
- `bearerTokenIsCaseInsensitiveAndTrims` — `"authorization:   bearer \t abc  "` → `"abc"`.
- `bearerTokenRejectsOtherSchemes` — `Basic`, no scheme, `Bearer` with empty token, header absent → `nil`.
- `bearerTokenUsesFirstAuthorizationHeader` — two headers → first value.
- `gateOptionsNeedsNoToken` — `gate(method: "OPTIONS", path: "/anything", bearer: nil, expected: T)` → `204`.
- `gateRejectsNonPost` — `("GET", "/intent", bearer: T, expected: T)` → `405` (a good token does not rescue a wrong method).
- `gateRejectsWrongPathBeforeAuth` — `("POST", "/other", bearer: T, expected: T)` → `404`; `("POST", "/other", bearer: nil, …)` → `404` (path is decided before the token, so a probe cannot learn whether auth exists from the status).
- `gateRejectsBadToken` — `("POST", "/intent", bearer: "x" × 64, expected: T)` → `401`; `bearer: nil` → `401`; `expected: ""` → `401` even with `bearer: ""`.
- `gatePassesGoodToken` — `("POST", "/intent", bearer: T, expected: T)` → `nil`.
- `generateBridgeTokenFormat` — `Store.generateBridgeToken()` matches `^[0-9a-f]{64}$` (check `count == 64` and every char in `0-9a-f`).
- `generateBridgeTokenIsUnique` — two calls differ.

**`BridgeParsingTests.swift` additions (hardening).**
- `idWithinBoundPasses` — 128 ASCII chars → `nil` problem; `idOverBoundRejected` — 129 → `"bad id"`; `nilIDStillPasses`.
- `idBoundIsBytesNotGraphemes` — `id = "a" + String(repeating: "\u{0301}", count: 5_000)` (`id.count == 1`, `id.utf8.count == 10_001`) → `"bad id"`. This is the test that fails if anyone reintroduces `id.count`.
- `hostnameBoundIsBytesNotGraphemes` — same payload in `hostname` → `"bad hostname"`; a 253-byte ASCII hostname still passes.
- `oversizedTypeProblemIsClipped` — `type` of 10 000 ASCII chars → `validate` returns a string with `utf8.count < 200`; `type = "a" + 5_000 × U+0301` → same bound.
- `headerCapWithoutDelimiter` — 8 193 bytes of `"a"`, `delimiter: nil` → `true`; 8 192 → `false`.
- `headerCapWithDelimiter` — 12 000 header bytes + `"\r\n\r\n"` + body; pass the real `range(of:)` result → `true`; 8 000 + delimiter → `false`; delimiter at exactly 8 192 → `false`.
- `headerCapOnDataSlice` — pins the `lowerBound - startIndex` semantics with a slice whose indices do not start at 0. `let full = Data(repeating: 0x78, count: 4) + Data(repeating: 0x61, count: 8_192) + Data("\r\n\r\n".utf8)`; `let slice = full[4...]` (so `slice.startIndex == 4` and the header inside the slice is exactly 8 192 bytes); `headerExceedsCap(slice, delimiter: slice.range(of: Data("\r\n\r\n".utf8)))` → `false`. A body using `$0.lowerBound` alone sees 8 196 and wrongly returns `true`, so this single assertion is the discriminating one. Add the mirror: 8 193 header bytes built the same way → `true`.
- `contentLengthAbsentStillZero` — already covered; keep.

**`LogClipTests` (inside `BridgeParsingTests.swift` or its own file).**
- `clipLeavesShortStrings` — `"abc"` → `"abc"`; exactly 256 ASCII bytes → unchanged (identity, not a copy with `"…"`).
- `clipTruncatesWithEllipsis` — 300 ASCII chars → `count == 257`, `hasSuffix("…")`, `hasPrefix(first 256)`.
- `clipBoundsBytesNotGraphemes` — `"a" + String(repeating: "\u{0301}", count: 5_000)` (one grapheme, 10 001 bytes) with `max: 256` → `result.utf8.count <= 259`, `hasSuffix("…")`, `hasPrefix("a")`. A `prefix(max)`-on-Characters implementation returns the input untouched and fails this.
- `clipNeverSplitsAScalar` — `String(repeating: "é", count: 200)` (2 bytes each) with `max: 255` → `result.utf8.count == 254 + 3`, no `"\u{FFFD}"` in the result, every character is `"é"` except the trailing `"…"`.

**`StoreDateTests.swift` additions (NATIVE-02)** — pinned `America/Santo_Domingo` calendar as today.
- `catchCountSameMonth` — `(7, "2026-06", at: 2026-06-12)` → 7.
- `catchCountNewMonthIsZero` — `(7, "2026-06", at: 2026-07-01 00:30)` → 0.
- `catchCountLateNightLocal` — `(3, "2025-12", at: 2025-12-31 23:30)` → 3; `at: 2026-01-01 00:30` → 0.
- `catchCountUnknownMonthKey` — `countMonth: "unknown"` → 0.

**`CatchRunnerTests.swift` (NATIVE-03).**
Every case passes `log: { event, msg, fields in captured.append((event, msg, fields)) }` so nothing reaches `Log.shared`.
- `admittedCatchRecordsAfterPerform` — `perform` returns `true` and appends `"perform"` to a sequence array; `record` appends `"record"`; assert return `true`, sequence `== ["perform", "record"]`, and exactly one captured log with `event == "catch.performed"`, `msg == hostname`, `fields == ["intent_id": "abc", "character": character.rawValue, "source": "bridge"]`.
- `busyCatchDoesNotRecord` — `perform` returns `false`; `record` never called; return `false`; one captured log `catch.skipped_busy` with `source: "test"` and `intent_id: ""` (nil intent id maps to the empty string, as today).
- `performIsCalledExactlyOnce` — counter.
- `characterAndGoalPassThrough` — captured arguments equal inputs.
- `defaultLogIsLogInfo` — not tested (it would write a real log line); the default argument is reviewed by eye and exercised by the manual checklist below.

**Not unit-testable without a window server, and how it is covered.** `performCatch`'s `true` path (NSPanel/NSScreen), the `panel != nil` gate under real timing, `DropdownView` (PAIR SENSOR row, `TimelineView` refresh), `NSPasteboard` copy, and the live `NWListener` request flow. Covered by a manual checklist that the PR description must include, run once on the implementer's Mac with the app built from the branch and `TOKEN` copied from the dropdown:

```bash
# 401 without token
curl -si -X POST http://127.0.0.1:17865/intent -H 'Content-Type: application/json' \
  -d '{"id":"t1","type":"checkout_intent","trigger":"simulated","hostname":"a.com","ts":1}' | head -3
# 200 with token (overlay fires)
curl -si -X POST http://127.0.0.1:17865/intent -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"id":"t2","type":"checkout_intent","trigger":"simulated","hostname":"a.com","ts":1}' | head -3
# 429 within 8 s (repeat the previous line), 204 for OPTIONS, 431 for a 12 KB header:
curl -si -X OPTIONS http://127.0.0.1:17865/intent | head -3
curl -si -X POST http://127.0.0.1:17865/intent -H "X-Pad: $(head -c 12000 /dev/zero | tr '\0' a)" | head -3
# no CORS header on any response:
curl -si -X OPTIONS http://127.0.0.1:17865/intent | grep -ci access-control   # expect 0
```
Plus: press "▶ test" twice within 4 s → one overlay, log shows one `catch.performed` and one `catch.skipped_busy`, stat increments by exactly 1; set the Mac clock to the 1st of next month with the dropdown open → stat reads "No catches yet this month." within a minute; COPY → paste into Options → Save → popup reads "Not tried yet" (not "App not reachable") → "Simulate intent" → "Connected ✓"; then "regenerate" in the dropdown → "Simulate intent" → "Token rejected ✕ — re-pair" and the app log shows `bridge.unauthorized reason:mismatch` with no `intent_id` field.

---

## 7. README changes summary (Track C)

**Root `README.md`** — rewrite the top half to describe the real product (a macOS menu-bar app that performs the catch + a Chrome "Sensor" extension that only detects), and fix every drifted instruction:

- Install (dev): 1) run the app (`swift run --package-path mac-app` or open `mac-app/Package.swift` in Xcode); 2) `chrome://extensions` → Developer mode → **Load unpacked → pick the `extension/` folder** (not the repo root); 3) **Pair**: click the menu-bar icon → **PAIR SENSOR → COPY**, open the extension's **Options → Pair with the app**, paste, **Save**; 4) verify: toolbar popup → **Simulate intent** → "Connected ✓" and the character appears. Note: after pulling this change, reload the extension and re-pair once.
- Explain that the extension renders nothing and plays nothing (remove the DOM-overlay, `popup` sound picker, `onboarding.html`, `overlay.css` and `sounds/` instructions; mention `sounds/` only as legacy assets not used by the sensor).
- "How it decides to trigger": listed vs everywhere modes, the site list in Options, page-load path (listed sites; known shopping domains in everywhere mode), buy-button click path (**real user clicks only — synthetic clicks are ignored**), 1.5 s cooldown, and that the policy is honoured live in open tabs.
- Storage schema: replace the old keys with the §3c table (`saMode`, `saAllowlist`, `saBlocklist`, `saInitialized`, `saLogs`, `lastIntent`, `bridgeOk`, `bridgeAt`, `bridgeWhy`, `saBridgeToken`) and say the token is the only secret and never leaves the machine.
- File map: `extension/` (manifest, background.js, content.js, detect.js, sites.js, domains.js, log.js, popup.*, options.*, pixel.css, tests/), `mac-app/`, `.github/workflows/ci.yml`; tests: `node --test extension/tests/*.test.js`.
- Security note paragraph: bridge is loopback-only, bearer-token paired, no CORS, header/body/id caps, 401 on mismatch; regenerate in the dropdown if you suspect the token leaked.

**`mac-app/README.md`** — replace "No browser, no bridge yet — triggered from a menu item" with the current architecture:

- The dropdown (goal, guardian picker, Shake It Up, monthly stat, **PAIR SENSOR** with COPY, on/off, snooze, "▶ test", quit).
- The bridge: `http://127.0.0.1:17865/intent`, `POST` JSON, `Authorization: Bearer <token>`, status table (200/204/400/401/404/405/413/429/431), caps, and the pairing/regeneration flow; the port doubles as the single-instance lock.
- The catch sequence with real timings (hold = max(4 s, clip + 0.6 s) + 0.4 s exit; clips up to ~12 s) and the rule that a catch already on screen makes the next intent a `catch.skipped_busy` (not counted).
- Logs: `~/Library/Logs/SpendingAngel/spending-angel-YYYY-MM-DD.jsonl`, key events (`bridge.listening`, `bridge.unauthorized`, `bridge.intent_received`, `catch.performed`, `catch.skipped_busy`, `store.token_generated`, `pair.token_copied`).
- Tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path mac-app` (Command Line Tools alone lack `Testing`).
- File map updated with `BridgeServer.swift`, `Store.swift`, `DropdownView.swift`, `CatchRunner.swift`, `Log.swift`, `Theme.swift`, `PixelFrame.swift`, `AudioPlayer.swift`, `CatchView.swift`, `Resources/voice/<character>/`.
