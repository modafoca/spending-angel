// Spending Angel — site-model helpers (pure, unit-tested).
//
// No chrome.* and no DOM here: shared by background.js, the popup, the options
// page, the content script, AND the tests. This is where the allowlist /
// blocklist / mode logic lives so all four surfaces agree on what "watched"
// means. Everything is local — these lists never leave the machine.

// Turn a URL or raw host into a bare, comparable host: no protocol, no path,
// no port, no leading "www.", lowercased. Returns "" for junk / non-http URLs
// (chrome://, about:, file:, extensions) — those are never watchable.
function saNormalizeHost(input) {
  if (!input) return "";
  let host = String(input).trim();
  if (host.includes("://")) {
    try {
      const u = new URL(host);
      if (u.protocol !== "http:" && u.protocol !== "https:") return "";
      host = u.hostname;
    } catch (e) {
      return "";
    }
  } else {
    // Bare host possibly with a path/port stuck on — keep the host part only.
    host = host.split("/")[0].split(":")[0];
  }
  host = host.toLowerCase().replace(/^www\./, "");
  // A real host has a dot and no spaces; reject "localhost", "newtab", etc.
  if (!host.includes(".") || /\s/.test(host)) return "";
  return host;
}

// The match patterns / permission origins for a stored host entry. A bare host
// covers itself + all subdomains; a "*.x" entry covers subdomains only.
function saHostToOrigins(host) {
  if (!host) return [];
  if (host.startsWith("*.")) return [`*://${host}/*`];
  return [`*://${host}/*`, `*://*.${host}/*`];
}

// Given the current mode + lists, should the sensor run on this host at all?
// (The content script only physically injects where we hold permission, but
// this keeps the decision in one tested place and drives the "everywhere"
// blocklist check.)
function saShouldWatch(host, { mode, allowlist, blocklist }) {
  host = saNormalizeHost(host);
  if (!host) return false;
  if (mode === "everywhere") {
    return !saHostInList(host, blocklist || []);
  }
  return saHostInList(host, allowlist || []);
}

// Does `host` match any entry in `list`? Entries may be bare ("amazon.com",
// matches subdomains too) or wildcard ("*.myshopify.com", subdomains only).
function saHostInList(host, list) {
  host = saNormalizeHost(host) || String(host || "").toLowerCase().replace(/^www\./, "");
  return (list || []).some((entry) => {
    entry = String(entry).toLowerCase();
    if (entry.startsWith("*.")) {
      const base = entry.slice(2);
      return host.endsWith("." + base);
    }
    return host === entry || host.endsWith("." + entry);
  });
}

// Add/remove a host in a list immutably, keeping it sorted + de-duped.
function saAddToList(list, host) {
  host = saNormalizeHost(host);
  if (!host) return (list || []).slice();
  const set = new Set([...(list || []), host]);
  return Array.from(set).sort();
}
function saRemoveFromList(list, host) {
  const target = saNormalizeHost(host) || host;
  return (list || []).filter((h) => h !== target);
}

if (typeof module !== "undefined") {
  module.exports = {
    saNormalizeHost, saHostToOrigins, saShouldWatch, saHostInList,
    saAddToList, saRemoveFromList,
  };
}
