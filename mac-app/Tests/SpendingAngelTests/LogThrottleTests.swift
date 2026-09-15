import Foundation
import Testing
@testable import SpendingAngel

/// `BridgeServer.LogThrottle` — the per-key suppression window that keeps a
/// local loop on the port from growing the day's log by one rejection line
/// per connection (review 2026-09, S-04 / Q-12). Every test drives a fake
/// clock through the injected `now`; nothing here touches `Log.shared`, and
/// no token or body bytes exist anywhere in the file — the throttle only ever
/// sees the key string.
struct LogThrottleTests {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Same shape the throttle uses for `suppressed_since`: default
    /// `ISO8601DateFormatter()` options, which drop fractional seconds — so
    /// `base + 0.2` renders as `2023-11-14T22:13:20Z`. Computed, not a literal.
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    /// A throttle whose clock is the returned `set` closure's last value.
    private func makeThrottle(window: TimeInterval = BridgeServer.LogThrottle.defaultWindow)
        -> (throttle: BridgeServer.LogThrottle, clock: Clock) {
        let clock = Clock(Self.base)
        let th = BridgeServer.LogThrottle(window: window, now: { clock.t })
        return (th, clock)
    }

    /// Mutable fake clock shared with the throttle's `now` closure.
    private final class Clock {
        var t: Date
        init(_ t: Date) { self.t = t }
        func at(_ offset: TimeInterval) { t = LogThrottleTests.base.addingTimeInterval(offset) }
    }

    @Test func defaultWindowIsOneSecond() {
        #expect(BridgeServer.LogThrottle.defaultWindow == 1)
    }

    @Test func firstLineIsEmittedWithoutSuppressed() {
        let (th, _) = makeThrottle()
        #expect(th.admit("bridge.unauthorized") == [:])
    }

    @Test func linesInsideTheWindowAreDropped() {
        let (th, clock) = makeThrottle()
        #expect(th.admit("bridge.unauthorized") == [:])
        clock.at(0.2)
        #expect(th.admit("bridge.unauthorized") == nil)
        clock.at(0.999)
        #expect(th.admit("bridge.unauthorized") == nil)
    }

    @Test func boundaryAtExactlyOneSecondEmits() {
        // Edge 10: the window is [openedAt, openedAt + 1); elapsed == 1.000 emits.
        let (th, clock) = makeThrottle()
        #expect(th.admit("k") == [:])
        clock.at(0.2)
        #expect(th.admit("k") == nil)
        clock.at(0.999)
        #expect(th.admit("k") == nil)
        clock.at(1.0)
        let out = th.admit("k")
        #expect(out?["suppressed"] == "2")
        #expect(out?["suppressed_since"] == iso(Self.base.addingTimeInterval(0.2)))
    }

    @Test func windowReopensAtTheEmittedLine() {
        // Continuing edge 10: after the emit at +1.0 the window is [1.0, 2.0),
        // not [2.0, 3.0) — +1.5 drops, +2.0 emits with exactly that one drop.
        let (th, clock) = makeThrottle()
        #expect(th.admit("k") == [:])
        clock.at(0.2); _ = th.admit("k")
        clock.at(0.999); _ = th.admit("k")
        clock.at(1.0)
        #expect(th.admit("k")?["suppressed"] == "2")
        clock.at(1.5)
        #expect(th.admit("k") == nil)
        clock.at(2.0)
        let out = th.admit("k")
        #expect(out?["suppressed"] == "1")
        #expect(out?["suppressed_since"] == iso(Self.base.addingTimeInterval(1.5)))
    }

    @Test func noSuppressedFieldWhenNothingWasDropped() {
        // Absent, not "0".
        let (th, clock) = makeThrottle()
        #expect(th.admit("k") == [:])
        clock.at(1.0)
        let out = th.admit("k")
        #expect(out == [:])
        #expect(out?["suppressed"] == nil)
        #expect(out?["suppressed_since"] == nil)
    }

    @Test func suppressedCountResetsAfterReport() {
        // Edge 12, the full sequence: the count is delivered once and reset.
        let (th, clock) = makeThrottle()
        #expect(th.admit("k") == [:])
        clock.at(0.5)
        #expect(th.admit("k") == nil)
        clock.at(1.0)
        let first = th.admit("k")
        #expect(first == ["suppressed": "1", "suppressed_since": iso(Self.base.addingTimeInterval(0.5))])
        clock.at(1.5)
        #expect(th.admit("k") == nil)
        clock.at(1.7)
        #expect(th.admit("k") == nil)
        clock.at(2.0)
        let second = th.admit("k")
        #expect(second == ["suppressed": "2", "suppressed_since": iso(Self.base.addingTimeInterval(1.5))])
        clock.at(3.0)
        #expect(th.admit("k") == [:])   // neither field: nothing dropped since +2.0
    }

    @Test func keysAreIndependent() {
        // Edge 11: two keys in the same window are both emitted and each
        // reports only its own drops.
        let (th, clock) = makeThrottle()
        let a = "bridge.unauthorized/missing"
        let b = "bridge.bad_payload"
        #expect(th.admit(a) == [:])
        clock.at(0.1)
        #expect(th.admit(b) == [:])
        clock.at(0.3)
        #expect(th.admit(a) == nil)
        clock.at(0.4)
        #expect(th.admit(b) == nil)
        clock.at(0.5)
        #expect(th.admit(b) == nil)
        clock.at(1.0)
        let outA = th.admit(a)
        #expect(outA?["suppressed"] == "1")
        #expect(outA?["suppressed_since"] == iso(Self.base.addingTimeInterval(0.3)))
        clock.at(1.1)
        let outB = th.admit(b)
        #expect(outB?["suppressed"] == "2")
        #expect(outB?["suppressed_since"] == iso(Self.base.addingTimeInterval(0.4)))
    }

    @Test func clockGoingBackwardsReopens() {
        // Edge 14: a wall-clock adjustment counts as "window over" — emit,
        // report the pending drop, reopen at the new time.
        let (th, clock) = makeThrottle()
        #expect(th.admit("k") == [:])
        clock.at(0.5)
        #expect(th.admit("k") == nil)
        clock.at(-5)
        let out = th.admit("k")
        #expect(out == ["suppressed": "1", "suppressed_since": iso(Self.base.addingTimeInterval(0.5))])
        clock.at(-4.5)
        #expect(th.admit("k") == nil)   // inside the reopened window [−5, −4)
        clock.at(-4)
        #expect(th.admit("k")?["suppressed"] == "1")
    }

    @Test func customWindow() {
        let (th, clock) = makeThrottle(window: 8)
        #expect(th.admit("k") == [:])
        clock.at(7.9)
        #expect(th.admit("k") == nil)
        clock.at(8)
        #expect(th.admit("k")?["suppressed"] == "1")
    }

    @Test func suppressedSinceIsTheFirstDroppedLine() {
        let (th, clock) = makeThrottle()
        #expect(th.admit("k") == [:])
        clock.at(0.2)
        #expect(th.admit("k") == nil)
        clock.at(0.5)
        #expect(th.admit("k") == nil)
        clock.at(1.0)
        let out = th.admit("k")
        #expect(out == ["suppressed": "2", "suppressed_since": iso(Self.base.addingTimeInterval(0.2))])
    }

    @Test func burstThenSilenceReportsWhenTheDropsHappened() {
        // Edge 23: 500 lines in one second, then two quiet hours. The reporting
        // line places the burst at [suppressed_since, ts], and the window
        // reopens at the reporting line, not at the burst.
        let (th, clock) = makeThrottle()
        #expect(th.admit("bridge.unauthorized/missing") == [:])
        for i in 1...499 {
            clock.at(Double(i) * 0.001)
            #expect(th.admit("bridge.unauthorized/missing") == nil)
        }
        clock.at(7200)
        let out = th.admit("bridge.unauthorized/missing")
        #expect(out == ["suppressed": "499", "suppressed_since": iso(Self.base.addingTimeInterval(0.001))])
        clock.at(7200.5)
        #expect(th.admit("bridge.unauthorized/missing") == nil)
    }

    @Test func unauthorizedReasonKeysAreIndependent() {
        // Edge 24: the keys `logRejected` builds ("bridge.unauthorized/" + reason)
        // keep the first wrong-token probe visible inside a no-token flood.
        let (th, clock) = makeThrottle()
        let missing = "bridge.unauthorized/" + "missing"
        let mismatch = "bridge.unauthorized/" + "mismatch"
        #expect(th.admit(missing) == [:])
        clock.at(0.1)
        #expect(th.admit(missing) == nil)
        clock.at(0.5)
        #expect(th.admit(mismatch) == [:])        // emitted inside the missing flood's window
        clock.at(0.7)
        #expect(th.admit(mismatch) == nil)
        clock.at(1.0)
        let out = th.admit(missing)
        #expect(out?["suppressed"] == "1")        // only its own drop, not the mismatch one
        #expect(out?["suppressed_since"] == iso(Self.base.addingTimeInterval(0.1)))
        clock.at(1.5)
        #expect(th.admit(mismatch)?["suppressed"] == "1")
    }

    @Test func resultKeysAreSuppressedPair() throws {
        // Every emitted result is either [:] or exactly the pair — never one
        // without the other — and both values parse.
        let (th, clock) = makeThrottle()
        var emitted: [[String: String]] = []
        let offsets: [TimeInterval] = [0, 0.1, 0.4, 1.0, 1.2, 2.0, 3.0, 3.5, 3.9, 4.0, 4.0, 5.0, -3, -2.5, -2]
        for o in offsets {
            clock.at(o)
            if let out = th.admit("k") { emitted.append(out) }
        }
        #expect(emitted.count >= 4)
        #expect(emitted.contains { $0.isEmpty })
        #expect(emitted.contains { !$0.isEmpty })
        let formatter = ISO8601DateFormatter()
        for out in emitted {
            let keys = Set(out.keys)
            #expect(keys.isEmpty || keys == ["suppressed", "suppressed_since"])
            if !keys.isEmpty {
                let raw = try #require(out["suppressed"])
                let n = try #require(Int(raw))
                #expect(n > 0)
                let since = try #require(out["suppressed_since"])
                #expect(formatter.date(from: since) != nil)
            }
        }
    }

    @Test func noTokenOrBodyBytesInAnyResult() {
        // The throttle only ever sees the key; whatever a caller logs, the
        // extra fields it hands back are the count and a clock reading.
        let (th, clock) = makeThrottle()
        let secret = String(repeating: "f", count: 64)
        for (i, key) in ["bridge.bad_request", "bridge.unauthorized/missing", "bridge.unauthorized/mismatch",
                         "bridge.bad_payload", "bridge.invalid_intent", "bridge.intent_throttled"].enumerated() {
            clock.at(Double(i) * 0.05)
            #expect(th.admit(key) == [:])
            clock.at(Double(i) * 0.05 + 0.2)
            #expect(th.admit(key) == nil)
            clock.at(Double(i) * 0.05 + 1.0)
            let out = th.admit(key) ?? [:]
            #expect(Set(out.keys) == ["suppressed", "suppressed_since"])
            for v in out.values {
                #expect(!v.contains(secret))
                #expect(!v.contains("Bearer"))
                #expect(!v.contains("{"))
            }
        }
    }
}
