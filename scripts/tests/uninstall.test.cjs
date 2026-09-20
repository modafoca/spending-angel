// Exercise the shipped uninstall script with command stubs. No real defaults,
// processes, login items, or app files are changed, and HOME is never replaced.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const script = path.resolve(__dirname, "../uninstall.sh");
const bundled = "net.modafoca.spendingangel";
const legacy = "SpendingAngel";
const initial = {
  [bundled]: { goal: "Current goal", bridgeToken: "synthetic-current-token", migratedFromLegacyDefaults: true },
  [legacy]: { goal: "Old goal", bridgeToken: "synthetic-old-token" },
  unrelated: { setting: "keep me" },
};

function fixture(t, domains = initial, failDelete = "") {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sa-uninstall-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const statePath = path.join(dir, "state.json");
  const mockPath = path.join(dir, "defaults.cjs");
  fs.writeFileSync(statePath, JSON.stringify({ domains, calls: [] }));
  fs.writeFileSync(mockPath, `
    const fs = require("node:fs");
    const statePath = process.env.SA_TEST_STATE;
    const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
    const [verb, domain] = process.argv.slice(2);
    state.calls.push([verb, domain]);
    let status = 0;
    if (!Object.hasOwn(state.domains, domain)) status = 1;
    else if (verb === "delete") {
      if (domain === process.env.SA_TEST_FAIL_DELETE) status = 2;
      else delete state.domains[domain];
    } else if (verb !== "read") status = 3;
    fs.writeFileSync(statePath, JSON.stringify(state));
    process.exitCode = status;
  `);
  return {
    state: () => JSON.parse(fs.readFileSync(statePath, "utf8")),
    run: (...args) => spawnSync("bash", ["-c", `
      defaults() { "$SA_TEST_NODE" "$SA_TEST_DEFAULTS" "$@"; }
      launchctl() { :; }
      pkill() { :; }
      rm() { :; }
      script="$1"
      shift
      source "$script" "$@"
    `, "uninstall-test", script, ...args], {
      encoding: "utf8",
      timeout: 10000,
      env: { ...process.env, SA_TEST_NODE: process.execPath, SA_TEST_DEFAULTS: mockPath,
        SA_TEST_STATE: statePath, SA_TEST_FAIL_DELETE: failDelete },
    }),
  };
}

test("explicit purge removes current and legacy settings without touching other domains", (t) => {
  const f = fixture(t);
  const result = f.run("--purge");
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.state().domains, { unrelated: initial.unrelated });
  // An empty legacy source cannot restore the goal/token on the next launch.
  assert.equal(f.state().domains[legacy], undefined);
  assert.match(result.stdout, /uninstall: done/);
});

test("ordinary uninstall preserves both settings stores and pairing tokens", (t) => {
  const f = fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.state().domains, initial);
  assert.deepEqual(f.state().calls, []);
});

test("purge tolerates an absent domain and can be repeated", (t) => {
  for (const domains of [{ [legacy]: initial[legacy] }, { [bundled]: initial[bundled] }, {}]) {
    const f = fixture(t, domains);
    for (let run = 0; run < 2; run++) {
      const result = f.run("--purge");
      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(f.state().domains, {});
    }
  }
});

test("a failed deletion is reported as failure rather than a completed purge", (t) => {
  const f = fixture(t, initial, legacy);
  const result = f.run("--purge");
  assert.equal(result.status, 2);
  assert.deepEqual(f.state().domains[legacy], initial[legacy]);
  assert.doesNotMatch(result.stdout, /uninstall: done/);
});
