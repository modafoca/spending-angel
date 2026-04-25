// Spending Angel — background service worker.
// Almost nothing happens here. We set defaults on first install and open
// the onboarding tab. Everything else lives in the content script + popup.

const DEFAULTS = {
  enabled: true,
  goal: "",
  selectedSound: "stop.mp3",
  volume: 0.7,
  triggerMode: "both",
  mutedDomains: [],
  onboarded: false,
};

chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  if (reason !== "install") return;
  await chrome.storage.local.set(DEFAULTS);
  await chrome.tabs.create({ url: chrome.runtime.getURL("onboarding.html") });
});
