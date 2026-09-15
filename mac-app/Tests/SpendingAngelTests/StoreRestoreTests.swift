import Foundation
import Testing
@testable import SpendingAngel

/// Restoring the monthly counter from disk when the month key is missing
/// (installs from before countMonth was written through on every catch).
struct StoreRestoreTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Santo_Domingo")!
        return c
    }()
    let sept15 = Date(timeIntervalSince1970: 1_789_500_000) // 2026-09-15

    @Test func storedMonthWins() {
        #expect(Store.restoredCountMonth(stored: "2026-06", monthlyCount: 251, now: sept15, calendar: cal) == "2026-06")
    }

    @Test func orphanedCounterIsUnknownAndDisplaysAsZero() {
        let month = Store.restoredCountMonth(stored: nil, monthlyCount: 251, now: sept15, calendar: cal)
        #expect(month == "unknown")
        #expect(Store.catchCount(monthlyCount: 251, countMonth: month, at: sept15, calendar: cal) == 0)
    }

    @Test func zeroCounterWithoutMonthIsThisMonth() {
        #expect(Store.restoredCountMonth(stored: nil, monthlyCount: 0, now: sept15, calendar: cal) == "2026-09")
    }
}
