// Spending Angel — onboarding script.
// Lives in its own file because MV3's default CSP blocks inline <script>.

const steps = [...document.querySelectorAll(".step")];
let i = 0;

function show(n) {
  steps.forEach((s, idx) => s.classList.toggle("active", idx === n));
  i = n;
}

document.querySelectorAll("[data-next]").forEach(btn => {
  btn.addEventListener("click", async () => {
    if (i === 1) {
      const goal = document.getElementById("goal").value.trim();
      await chrome.storage.local.set({ goal, onboarded: true });
      document.getElementById("done-title").textContent = goal
        ? `Got it. I'll remind you about ${goal}.`
        : "I've got your back.";
    }
    show(Math.min(i + 1, steps.length - 1));
  });
});

document.querySelector("[data-skip]").addEventListener("click", async () => {
  await chrome.storage.local.set({ onboarded: true });
  show(2);
});

document.querySelector("[data-close]").addEventListener("click", () => {
  window.close();
});
