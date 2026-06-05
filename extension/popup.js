// Spending Angel — sensor debug popup.
//
// Shows the last detected intent and lets you fire a fake one. The real
// controls (goal, character, mute, snooze) live in the macOS app, not here.

const $ = id => document.getElementById(id);

function render(intent) {
  $("last-intent").textContent = intent ? JSON.stringify(intent, null, 2) : "none yet";
}

async function load() {
  const { lastIntent } = await chrome.storage.local.get({ lastIntent: null });
  render(lastIntent);
}

document.addEventListener("DOMContentLoaded", async () => {
  await load();

  $("simulate").addEventListener("click", async () => {
    const payload = {
      type: "checkout_intent",
      trigger: "simulated",
      hostname: "example-shop.test",
      ts: Date.now(),
    };
    console.log("[SA sensor]", payload);
    await chrome.storage.local.set({ lastIntent: payload });
    render(payload);
    // TODO M-05: also push over the bridge so the app performs the catch.
  });

  // Live-update if a real intent lands while the popup is open.
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes.lastIntent) render(changes.lastIntent.newValue);
  });
});
