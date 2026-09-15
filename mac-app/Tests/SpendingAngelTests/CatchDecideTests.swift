import Foundation
import Testing
@testable import SpendingAngel

/// Round 3 — `CatchRunner.decide` maps the dropdown's switch + nap and the
/// overlay's admission gate to the outcome the bridge sends back. Pure: the
/// clock is a parameter and the catch is a closure that returns the character
/// that performed (nil when the overlay was busy), so nothing here needs AppKit.
struct CatchDecideTests {
    private let now = Date(timeIntervalSince1970: 1_789_500_000)

    @Test func offWinsAndNeverRunsTheCatch() {
        var ran = 0
        let out = CatchRunner.decide(enabled: false, snoozeUntil: now.addingTimeInterval(3600), now: now) {
            ran += 1; return .mom
        }
        #expect(out == .skipped(.off))
        #expect(ran == 0)
    }

    @Test func activeSnoozeSkipsWithoutRunning() {
        var ran = 0
        let out = CatchRunner.decide(enabled: true, snoozeUntil: now.addingTimeInterval(1), now: now) {
            ran += 1; return .mom
        }
        #expect(out == .skipped(.snoozed))
        #expect(ran == 0)
    }

    @Test func expiredOrAbsentSnoozeIsOnDuty() {
        // Same rule as Store.isSnoozed: only a deadline strictly ahead of now naps.
        for until in [nil, now.addingTimeInterval(-1), now] as [Date?] {
            var ran = 0
            let out = CatchRunner.decide(enabled: true, snoozeUntil: until, now: now) { ran += 1; return .angel }
            #expect(out == .shown(character: .angel))
            #expect(ran == 1)
        }
    }

    @Test func busyOverlayIsBusy() {
        #expect(CatchRunner.decide(enabled: true, snoozeUntil: nil, now: now) { nil } == .skipped(.busy))
    }

    @Test func shownCarriesTheCharacterThatPerformed() {
        for c in CharacterID.allCases {
            #expect(CatchRunner.decide(enabled: true, snoozeUntil: nil, now: now) { c } == .shown(character: c))
        }
        #expect(IntentOutcome.shown(character: .mom) != .shown(character: .papi))
    }

    @Test func skipReasonWordsAreTheWireWords() {
        #expect(IntentOutcome.SkipReason.off.rawValue == "off")
        #expect(IntentOutcome.SkipReason.snoozed.rawValue == "snoozed")
        #expect(IntentOutcome.SkipReason.busy.rawValue == "busy")
    }

    @Test func decideComposesWithRun() {
        // The AppDelegate wiring in miniature: admit = run the catch and return
        // the character only when the overlay admitted it. Busy → one
        // skipped_busy line and no record; admitted → one performed line, one record.
        for admitted in [true, false] {
            var events: [String] = []
            var records = 0
            let out = CatchRunner.decide(enabled: true, snoozeUntil: nil, now: now) {
                let ok = CatchRunner.run(goal: "g", character: .papi, source: "bridge", hostname: "shop.test", intentID: "i",
                                         perform: { _, _ in admitted }, record: { records += 1 },
                                         log: { e, _, _ in events.append(e) })
                return ok ? .papi : nil
            }
            #expect(out == (admitted ? .shown(character: .papi) : .skipped(.busy)))
            #expect(events == [admitted ? "catch.performed" : "catch.skipped_busy"])
            #expect(records == (admitted ? 1 : 0))
        }
    }
}
