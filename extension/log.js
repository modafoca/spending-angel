// Spending Angel — structured sensor logging (M-F1, the house standard).
//
// Same shape as the app's JSONL: ts / level / event / msg + context fields.
// Events go to the console AND a small ring buffer in chrome.storage.local
// ("saLogs", newest last) that the popup's "Recent events" panel reads.
// Local-first: nothing ever leaves the machine.

var SA_LOG_MAX = 50;

function saLog(level, event, msg, fields = {}) {
  const entry = Object.assign(
    { ts: new Date().toISOString(), level, event, msg },
    fields
  );
  const print = level === "error" ? console.error : console.log;
  print(`[SA ${level}] ${event} — ${msg}`, fields);

  try {
    // Read-modify-write isn't atomic across tabs; for a debug ring buffer the
    // worst case is a lost line, which is fine.
    chrome.storage.local.get({ saLogs: [] }, (s) => {
      const logs = s.saLogs.concat(entry).slice(-SA_LOG_MAX);
      chrome.storage.local.set({ saLogs: logs });
    });
  } catch (e) {
    // chrome.storage unavailable (tests) — console output already happened.
  }
}

if (typeof module !== "undefined") {
  module.exports = { saLog, SA_LOG_MAX };
}
