// Spending Angel — structured sensor logging (M-F1, the house standard).
//
// Same shape as the app's JSONL: ts / level / event / msg + context fields.
// Events go to the console AND a small ring buffer in chrome.storage.local
// ("saLogs", newest last) that the popup's "Recent events" panel reads; the
// ring write never surfaces a storage failure (it would recurse), and two
// calls in one synchronous turn may lose a line (accepted; nothing shipped
// does it). Local-first: nothing ever leaves the machine.

var SA_LOG_MAX = 50;

function saLog(level, event, msg, fields = {}) {
  const entry = Object.assign(
    { ts: new Date().toISOString(), level, event, msg },
    fields
  );
  const print = level === "error" ? console.error : console.log;
  print(`[SA ${level}] ${event} — ${msg}`, fields);

  // Ring write: one awaited chain with a terminal catch (review R-02). A torn-
  // down storage (extension reloaded under a live tab, worker shutting down)
  // must neither surface as an unhandled rejection nor be re-logged — logging
  // the failure would recurse into the same dead storage. Console already has
  // the line. Read-modify-write isn't atomic across tabs; for a debug ring the
  // worst case is a lost line, which is fine. A corrupted ring (not an array)
  // is replaced rather than left wedged.
  void (async () => {
    const s = await chrome.storage.local.get({ saLogs: [] });
    const prior = Array.isArray(s.saLogs) ? s.saLogs : [];
    await chrome.storage.local.set({ saLogs: prior.concat(entry).slice(-SA_LOG_MAX) });
  })().catch(() => {});
}

if (typeof module !== "undefined") {
  module.exports = { saLog, SA_LOG_MAX };
}
