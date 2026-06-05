// Spending Angel — sensor service worker.
//
// The sensor is stateless: the macOS app holds the goal, the character, and all
// settings, so there's nothing to bootstrap or onboard here anymore (onboarding
// moved to the app — see the PRM, Q3: app-first).
//
// This file is intentionally minimal. The bridge connection to the app (a
// 127.0.0.1 WebSocket) lands in M-05 and will live here.

// (no listeners yet — M-05)
