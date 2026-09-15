// Spending Angel — Node `vm` harness for the non-exportable extension scripts.
//
// content.js and background.js are classic scripts with no module.exports, so
// the tests evaluate the REAL files (read from extension/) inside one
// vm.createContext with a mocked `chrome` + the minimum DOM/SW surface they
// touch. Nothing here is a copy of shipped logic — if the scripts start using
// a global that isn't mocked below, add it HERE, not ad hoc in a test.
//
// Not a *.test.js file on purpose: the CI glob never runs it directly.
//
// Loaders (design-spec §6a):
//   loadContentScript({ hostname, config, clock, failFirstGet }) → handle
//     evaluates domains.js, log.js, detect.js, sites.js, content.js
//   loadBackground({ config, permissions, fetchImpl }) → handle
//     evaluates domains.js, log.js, sites.js, background.js
//   loadPopup({ config }) / loadOptions({ config }) → handle
//     evaluate the page scripts (status.js included, after sites.js, as the
//     pages load it) against a tiny element-by-id DOM stub so the pure-ish
//     render/save functions can be exercised without a browser.
//
// fetchImpl (background) may return { ok, status, json: async () => ({...}) };
// the default answers 200 with an empty JSON object, which forward() reads as
// an app that said nothing about what it did (lastResult.result "unknown").

const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");

const EXT_DIR = path.join(__dirname, "..");
// The fake epoch every handle's clock starts at. Not exported on purpose:
// tests read the live value via `h.clock.now` so there is one source of truth.
const START_CLOCK = 1_700_000_000_000; // 2023-11-14T22:13:20Z — any fixed epoch works

function readSource(name) {
  return fs.readFileSync(path.join(EXT_DIR, name), "utf8");
}

// The shipped manifest version, so chrome.runtime.getManifest() in the pages
// answers what Chrome would — tests compare against it rather than a literal.
const MANIFEST_VERSION = JSON.parse(readSource("manifest.json")).version;

// ---- Shared pieces ----------------------------------------------------------

// Controllable Date.now() while `new Date().toISOString()` (log.js) still works.
function makeFakeDate(clock) {
  return class FakeDate extends Date {
    static now() { return clock.now; }
  };
}

function makeClock() {
  const clock = { now: START_CLOCK };
  clock.advance = (ms) => { clock.now += ms; };
  return clock;
}

// chrome.storage.local over an in-memory object. Two `get` forms mirror Chrome:
// the promise form (content/background/log.js) and the callback form, which
// never rejects and never returns a Promise. Nothing shipped uses the callback
// form any more (log.js moved to the promise form in review R-02); it is kept
// for fidelity so a future callback-form caller still works.
//
// The promise-form snapshot is taken EAGERLY at call time, like Chrome's IPC
// answer: two saLog calls in one synchronous turn both read the pre-write ring
// and one line is lost (design-spec-r2 edge case 28). Tests that need N lines
// in the ring flush between calls; the harness does not try to serialize them.
function makeStorage(handle) {
  const { store } = handle;

  // failNextGet(err, key): does the armed failure apply to THIS read? Without a
  // key any promise-form get matches; with one, match on the KEYS the caller
  // asked for (never on default values), by defaults form.
  function getMatches(defaults, key) {
    if (!key) return true;
    if (defaults === null || defaults === undefined) return true;
    if (typeof defaults === "string") return defaults === key;
    if (Array.isArray(defaults)) return defaults.includes(key);
    return key in defaults;
  }

  function snapshot(defaults) {
    if (defaults === null || defaults === undefined) return Object.assign({}, store);
    if (typeof defaults === "string") {
      return defaults in store ? { [defaults]: store[defaults] } : {};
    }
    if (Array.isArray(defaults)) {
      const out = {};
      for (const k of defaults) if (k in store) out[k] = store[k];
      return out;
    }
    const out = {};
    for (const k of Object.keys(defaults)) out[k] = k in store ? store[k] : defaults[k];
    return out;
  }

  return {
    get(defaults, cb) {
      if (typeof cb === "function") {
        Promise.resolve().then(() => cb(snapshot(defaults)));
        return undefined;
      }
      const pending = handle.pendingGetError;
      if (pending && getMatches(defaults, pending.key)) {
        handle.pendingGetError = null;
        return Promise.reject(pending.err);
      }
      return Promise.resolve(snapshot(defaults));
    },
    set(obj) {
      // failNextSet(err, key): reject the next set() — or, with `key`, the next
      // one that writes that key — without recording it, mirroring a storage
      // torn down mid-flight. log.js's own ring write is skipped by using `key`.
      const pending = handle.pendingSetError;
      if (pending && (!pending.key || pending.key in obj)) {
        handle.pendingSetError = null;
        return Promise.reject(pending.err);
      }
      Object.assign(store, obj);
      // Recorded as a same-realm clone: objects built inside the vm carry a
      // different Object.prototype, which assert.deepStrictEqual rejects.
      handle.writes.push(structuredClone(obj));
      return Promise.resolve();
    },
    remove(keys) {
      const list = Array.isArray(keys) ? keys : [keys];
      for (const k of list) delete store[k];
      handle.removes.push(list);
      return Promise.resolve();
    },
  };
}

function makeListenerBag(handle, name) {
  handle.listeners[name] = [];
  return { addListener(fn) { handle.listeners[name].push(fn); } };
}

function makeConsole(handle) {
  return {
    log(...args) { handle.console.push({ level: "log", args }); },
    error(...args) { handle.console.push({ level: "error", args }); },
    warn(...args) { handle.console.push({ level: "warn", args }); },
    debug(...args) { handle.console.push({ level: "debug", args }); },
  };
}

function baseHandle(config) {
  const handle = {
    store: Object.assign({}, config || {}),
    writes: [],
    removes: [],
    listeners: {},
    console: [],
    clock: makeClock(),
    pendingGetError: null,
    pendingSetError: null,
  };
  handle.setConfig = (obj) => { Object.assign(handle.store, obj); };
  // failNextGet(err, key): reject the next promise-form get() — or, with `key`,
  // the next one that asks for that key — once. Scope it: log.js's ring read
  // (`get({ saLogs: [] })`) is a promise-form get too, so an unscoped knob armed
  // while a saLog chain is still pending is consumed by the ring read instead
  // of the read under test. Unscoped arming is only safe after a flush.
  handle.failNextGet = (err, key) => { handle.pendingGetError = { err, key }; };
  handle.failNextSet = (err, key) => { handle.pendingSetError = { err, key }; };
  handle.tick = () => new Promise((r) => setImmediate(r));
  // Convenience over handle.store.saLogs (log.js keeps the ring there).
  handle.logs = () => handle.store.saLogs || [];
  handle.logEvents = () => handle.logs().map((l) => l.event);
  handle.lastLog = () => handle.logs().at(-1);
  // Everything the scripts printed, as one string — for "this hostname appears
  // nowhere" assertions (design-spec-r2 edge case 6).
  handle.consoleText = () => JSON.stringify(handle.console);
  return handle;
}

function evaluate(ctx, files) {
  for (const name of files) {
    vm.runInContext(readSource(name), ctx, { filename: path.join(EXT_DIR, name) });
  }
}

// ---- Content script ---------------------------------------------------------

// failFirstGet: `{ err, key }` (or a bare Error) armed BEFORE the scripts are
// evaluated, so main()'s boot read is the one that fails — the handle does not
// exist yet when a test could otherwise arm it (design-spec-r2 edge case 4).
function loadContentScript({ hostname = "shop.example.test", config = {}, clock, failFirstGet } = {}) {
  const handle = baseHandle(config);
  if (clock) handle.clock = clock;
  handle.hostname = hostname;
  if (failFirstGet) {
    const spec = failFirstGet instanceof Error ? { err: failFirstGet } : failFirstGet;
    handle.failNextGet(spec.err, spec.key);
  }
  handle.messages = [];
  handle.timers = [];

  handle.fireTimers = () => {
    const pending = handle.timers.splice(0);
    for (const t of pending) t.fn();
  };
  handle.click = (evt) => {
    const fns = handle.listeners.click || [];
    if (!fns.length) throw new Error("no click listener attached");
    for (const fn of fns) fn(evt);
  };

  // Element fixtures: just enough surface for isBuyButton().
  handle.buyButton = (text = "Buy now") => ({
    innerText: text,
    parentElement: null,
    matches: (sel) => sel !== "a",
    getAttribute: () => "",
    getBoundingClientRect: () => ({ width: 100, height: 30 }),
  });
  handle.buyLink = (text = "Checkout") => ({
    innerText: text,
    parentElement: null,
    matches: (sel) => sel === "a" || sel.includes("a,") || sel.includes(" a"),
    getAttribute: () => "",
    getBoundingClientRect: () => ({ width: 100, height: 30 }),
  });
  handle.plainSpan = (text = "hello") => ({
    innerText: text,
    parentElement: null,
    matches: () => false,
    getAttribute: () => "",
    getBoundingClientRect: () => ({ width: 100, height: 30 }),
  });
  handle.hiddenBuyButton = () => Object.assign(handle.buyButton(), {
    style: { display: "none", visibility: "visible", opacity: "1" },
  });

  const chrome = {
    storage: {
      local: makeStorage(handle),
      onChanged: makeListenerBag(handle, "storageChanged"),
    },
    runtime: {
      sendMessage(p) { handle.messages.push(structuredClone(p)); return Promise.resolve(); },
    },
  };

  const ctx = vm.createContext({
    chrome,
    console: makeConsole(handle),
    crypto: { randomUUID },
    location: { hostname },
    document: {
      addEventListener(type, fn, capture) {
        if (!handle.listeners[type]) handle.listeners[type] = [];
        handle.listeners[type].push(fn);
        handle.listeners[type + "Capture"] = !!capture;
      },
    },
    getComputedStyle: (el) => el.style || { display: "block", visibility: "visible", opacity: "1" },
    setTimeout: (fn, ms) => { handle.timers.push({ fn, ms }); return handle.timers.length; },
    clearTimeout: () => {},
    Date: makeFakeDate(handle.clock),
    // Deliberately no `window`: domains.js guards with typeof window.
  });
  handle.ctx = ctx;
  handle.chrome = chrome;

  evaluate(ctx, ["domains.js", "log.js", "detect.js", "sites.js", "content.js"]);
  return handle;
}

// ---- Service worker ---------------------------------------------------------

function loadBackground({ config = {}, permissions, fetchImpl } = {}) {
  const handle = baseHandle(config);
  handle.permissions = permissions || (async () => true);
  handle.fetchImpl = fetchImpl || (async () => ({ ok: true, status: 200, json: async () => ({}) }));
  handle.fetches = [];
  handle.registrations = [];
  handle.unregisters = 0;
  handle.active = null;
  handle.pendingRegisterError = null;
  handle.failNextRegister = (err) => { handle.pendingRegisterError = err; };
  // The abort timer is REAL (Node's setTimeout) so clearTimeout works as in a
  // browser; the harness only records it so tests can assert none was created
  // on the unpaired path and that a created one was cleared.
  handle.timers = [];
  handle.clears = 0;

  const chrome = {
    storage: {
      local: makeStorage(handle),
      onChanged: makeListenerBag(handle, "storageChanged"),
    },
    runtime: {
      onInstalled: makeListenerBag(handle, "onInstalled"),
      onStartup: makeListenerBag(handle, "onStartup"),
      onMessage: makeListenerBag(handle, "onMessage"),
    },
    permissions: {
      contains({ origins }) { return Promise.resolve(handle.permissions(origins)); },
      onAdded: makeListenerBag(handle, "permissionsAdded"),
      onRemoved: makeListenerBag(handle, "permissionsRemoved"),
    },
    scripting: {
      registerContentScripts(entries) {
        if (handle.pendingRegisterError) {
          const err = handle.pendingRegisterError;
          handle.pendingRegisterError = null;
          return Promise.reject(err);
        }
        if (handle.active) return Promise.reject(new Error("Duplicate script ID 'sa-detector'"));
        handle.active = entries[0];
        handle.registrations.push(entries[0]);
        return Promise.resolve();
      },
      unregisterContentScripts() {
        handle.unregisters++;
        if (!handle.active) return Promise.reject(new Error("Nonexistent script ID 'sa-detector'"));
        handle.active = null;
        return Promise.resolve();
      },
    },
  };

  const ctx = vm.createContext({
    chrome,
    console: makeConsole(handle),
    crypto: { randomUUID },
    importScripts() {},
    fetch(url, init) {
      handle.fetches.push({ url, init });
      return handle.fetchImpl(url, init);
    },
    AbortController,
    setTimeout: (fn, ms) => {
      const id = setTimeout(fn, ms);
      handle.timers.push({ id, ms });
      return id;
    },
    clearTimeout: (id) => { handle.clears++; clearTimeout(id); },
    Date: makeFakeDate(handle.clock),
  });
  handle.ctx = ctx;
  handle.chrome = chrome;

  // Convenience: hand an intent to the captured onMessage listener(s).
  handle.message = (msg) => {
    for (const fn of handle.listeners.onMessage) fn(msg, { id: "sender" }, () => {});
  };
  handle.storageChanged = (changes, area = "local") => {
    for (const fn of handle.listeners.storageChanged) fn(changes, area);
  };
  handle.bridgeWrites = () => handle.writes.filter((w) => "bridgeOk" in w);

  evaluate(ctx, ["domains.js", "log.js", "sites.js", "background.js"]);
  return handle;
}

// ---- Popup / options pages --------------------------------------------------

// Element-by-id stub: every id resolves to a plain object that remembers what
// the script wrote to it (textContent, className, hidden, placeholder, value).
function makeDom(handle) {
  const els = new Map();
  const el = (id) => {
    if (!els.has(id)) {
      els.set(id, {
        id, textContent: "", className: "", hidden: false, placeholder: "", value: "",
        innerHTML: "", dataset: {}, listeners: {},
        addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); },
        appendChild() {},
      });
    }
    return els.get(id);
  };
  handle.el = el;
  return {
    getElementById: el,
    querySelectorAll: () => [],
    createElement: (tag) => ({ tag, className: "", textContent: "", addEventListener() {}, appendChild() {} }),
    addEventListener(type, fn) {
      if (!handle.listeners[type]) handle.listeners[type] = [];
      handle.listeners[type].push(fn);
    },
  };
}

function loadPage(files, { config = {}, tabUrl = "" } = {}) {
  const handle = baseHandle(config);
  handle.messages = [];
  handle.openedOptions = 0;
  const chrome = {
    storage: {
      local: makeStorage(handle),
      onChanged: makeListenerBag(handle, "storageChanged"),
    },
    runtime: {
      sendMessage(p) { handle.messages.push(p); return Promise.resolve(); },
      openOptionsPage() { handle.openedOptions++; },
      getManifest() { return { version: MANIFEST_VERSION }; },
    },
    permissions: {
      contains: async () => true,
      request: async () => true,
      remove: async () => {},
      onAdded: makeListenerBag(handle, "permissionsAdded"),
      onRemoved: makeListenerBag(handle, "permissionsRemoved"),
    },
    tabs: { query: async () => [{ url: tabUrl }] },
  };
  const ctx = vm.createContext({
    chrome,
    console: makeConsole(handle),
    crypto: { randomUUID },
    document: makeDom(handle),
    Date: makeFakeDate(handle.clock),
  });
  handle.ctx = ctx;
  handle.chrome = chrome;
  handle.domReady = async () => {
    for (const fn of handle.listeners.DOMContentLoaded || []) await fn();
  };
  handle.storageChanged = (changes, area = "local") => {
    for (const fn of handle.listeners.storageChanged) fn(changes, area);
  };
  evaluate(ctx, files);
  return handle;
}

function loadPopup(opts) {
  return loadPage(["domains.js", "sites.js", "status.js", "detect.js", "popup.js"], opts);
}

function loadOptions(opts) {
  return loadPage(["domains.js", "sites.js", "status.js", "options.js"], opts);
}

module.exports = { loadContentScript, loadBackground, loadPopup, loadOptions, MANIFEST_VERSION };
