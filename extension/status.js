// Spending Angel — app-status text (pure, unit-tested).
//
// One module, two surfaces: the popup and the Options page both show the
// "Connection" and "Last request" lines, and they must say the same thing.
// So the wording lives here, next to nothing else: no chrome.*, no DOM, and
// the clock formatter is injected (fmtTime) so tests pin exact strings.
//
// The inputs are the keys the service worker writes after each intent:
//   bridgeOk / bridgeAt / bridgeWhy  — could the sensor reach the app at all
//   lastResult                       — what the app said it did (Round 3 body)
//   appVersion                       — the app's version from that same body
// "Connected" and "Character shown" are kept apart on purpose: the app can
// answer perfectly well and still show nothing (off, snoozed, busy, throttled),
// and the user needs to see which of the two it was.

// Connection line. Same semantics the popup had before Round 3, moved here.
// `needsPairing` is true for the two states the user can fix in Options.
function saConnectionText({ bridgeOk, bridgeAt, bridgeWhy } = {}, fmtTime) {
  const when = bridgeAt ? fmtTime(bridgeAt) : "";
  if (bridgeOk === null || bridgeOk === undefined) {
    return { text: "Connection not checked yet", tone: "neutral", needsPairing: false };
  }
  if (bridgeOk) {
    return { text: `Last connected · ${when}`, tone: "ok", needsPairing: false };
  }
  if (bridgeWhy === "unpaired") {
    return { text: "Connect to the Mac app", tone: "bad", needsPairing: true };
  }
  if (bridgeWhy === "unauthorized") {
    return { text: "Reconnect to the Mac app", tone: "bad", needsPairing: true };
  }
  return { text: `App not reached · ${when}`, tone: "bad", needsPairing: false };
}

// Display names for the app's character ids. Anything new falls through to a
// plain capitalisation so a future character still reads as a name.
const SA_CHARACTER_NAMES = { angel: "Angel", papi: "Papi", wizard: "Wizard", mom: "Mom" };

function saCharacterName(id) {
  const key = String(id || "");
  if (SA_CHARACTER_NAMES[key]) return SA_CHARACTER_NAMES[key];
  return key ? key.charAt(0).toUpperCase() + key.slice(1) : "";
}

// Last-request line: what the app did with the most recent accepted intent.
// The strings are pinned by tests — change them there first.
function saLastResultText(lastResult, fmtTime) {
  if (!lastResult || typeof lastResult !== "object") {
    return { text: "No catch yet.", tone: "neutral" };
  }
  const r = lastResult;
  if (r.result === "shown") {
    const name = saCharacterName(r.character);
    return { text: `${name || "Your guardian"} appeared · ${fmtTime(r.at)}`, tone: "ok" };
  }
  if (r.result === "skipped") {
    if (r.reason === "off") {
      return { text: "Your guardian is off. Turn it on in the Mac menu bar.", tone: "bad" };
    }
    if (r.reason === "snoozed") {
      const until = typeof r.snooze_until === "string" ? Date.parse(r.snooze_until) : NaN;
      const text = Number.isFinite(until)
        ? `Snoozed until ${fmtTime(until)} · Wake up in the Mac menu bar.`
        : "Snoozed · Wake up in the Mac menu bar.";
      return { text, tone: "bad" };
    }
    if (r.reason === "busy") {
      return { text: "Your guardian was already on screen.", tone: "neutral" };
    }
    if (r.reason === "throttled") {
      const wait = typeof r.retry_in_s === "number" ? ` (wait ${r.retry_in_s} s)` : "";
      return { text: `Taking a breather after the last catch${wait}`, tone: "neutral" };
    }
  }
  // "unknown" (an app older than the body contract), or a result/reason this
  // sensor doesn't know yet — either way the honest line is the same.
  return { text: "Connected to an older app. Update it for catch details.", tone: "neutral" };
}

// Version handshake. Only major.minor matters (patch releases never change
// the bridge contract). null = nothing to say: versions agree, or the app has
// not answered with a version yet, or a version string can't be read.
function saParseVersion(v) {
  const m = /^(\d+)\.(\d+)/.exec(String(v || "").trim());
  return m ? [Number(m[1]), Number(m[2])] : null;
}

function saVersionHint(sensorVersion, appVersion) {
  const s = saParseVersion(sensorVersion);
  const a = saParseVersion(appVersion);
  if (!s || !a) return null;
  const cmp = s[0] !== a[0] ? s[0] - a[0] : s[1] - a[1];
  if (cmp === 0) return null;
  const pair = `Browser v${sensorVersion} · App v${appVersion}`;
  return cmp > 0
    ? `${pair} — update the app`
    : `${pair} — reload the extension at chrome://extensions`;
}

// The Test connection action sends the same five keys as a real detection.
function saSimulatedIntent(now = Date.now()) {
  return {
    id: crypto.randomUUID(),
    type: "checkout_intent",
    trigger: "simulated",
    hostname: "example-shop.test",
    ts: now,
  };
}

if (typeof module !== "undefined") {
  module.exports = {
    saConnectionText, saLastResultText, saVersionHint, saSimulatedIntent, saCharacterName,
  };
}
