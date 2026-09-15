import Foundation
import Testing
@testable import SpendingAngel

/// NATIVE-02 — the displayed monthly count derives from the month containing
/// "now", so a stale August counter never shows in September (`Store.init` no
/// longer needs to roll). Pinned `America/Santo_Domingo` calendar, static only:
/// no `Store()` instance (its init writes UserDefaults.standard).
struct StoreRolloverTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Santo_Domingo")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func catchCountSameMonth() {
        #expect(Store.catchCount(monthlyCount: 7, countMonth: "2026-06", at: date(2026, 6, 12), calendar: cal) == 7)
        #expect(Store.catchCount(monthlyCount: 7, countMonth: "2026-06", at: date(2026, 6, 1, 0, 0), calendar: cal) == 7)
        #expect(Store.catchCount(monthlyCount: 7, countMonth: "2026-06", at: date(2026, 6, 30, 23, 59), calendar: cal) == 7)
    }

    @Test func catchCountNewMonthIsZero() {
        #expect(Store.catchCount(monthlyCount: 7, countMonth: "2026-06", at: date(2026, 7, 1, 0, 30), calendar: cal) == 0)
        // Case 10: app restarted in September with an August count.
        #expect(Store.catchCount(monthlyCount: 7, countMonth: "2026-08", at: date(2026, 9, 14), calendar: cal) == 0)
    }

    @Test func catchCountLateNightLocal() {
        // 11:30pm Dec 31 local is still December locally (would be January in UTC).
        #expect(Store.catchCount(monthlyCount: 3, countMonth: "2025-12", at: date(2025, 12, 31, 23, 30), calendar: cal) == 3)
        #expect(Store.catchCount(monthlyCount: 3, countMonth: "2025-12", at: date(2026, 1, 1, 0, 30), calendar: cal) == 0)
    }

    @Test func catchCountSameMonthDifferentYearIsZero() {
        #expect(Store.catchCount(monthlyCount: 5, countMonth: "2025-09", at: date(2026, 9, 14), calendar: cal) == 0)
    }

    @Test func catchCountFutureStoredMonthIsZero() {
        // A clock that went backwards: the stored month is "later" than now → 0, no crash.
        #expect(Store.catchCount(monthlyCount: 5, countMonth: "2026-10", at: date(2026, 9, 14), calendar: cal) == 0)
    }

    @Test func catchCountUnknownMonthKey() {
        #expect(Store.catchCount(monthlyCount: 9, countMonth: "unknown", at: date(2026, 6, 12), calendar: cal) == 0)
        #expect(Store.catchCount(monthlyCount: 9, countMonth: "", at: date(2026, 6, 12), calendar: cal) == 0)
        #expect(Store.catchCount(monthlyCount: 9, countMonth: "2026-6", at: date(2026, 6, 12), calendar: cal) == 0)   // unpadded ≠ key
    }

    @Test func catchCountZeroStaysZero() {
        #expect(Store.catchCount(monthlyCount: 0, countMonth: "2026-06", at: date(2026, 6, 12), calendar: cal) == 0)
    }

    @Test func catchCountAgreesWithMonthKey() {
        // The display rule is exactly "stored key == monthKey(now)".
        let now = date(2026, 9, 14, 9, 0)
        let key = Store.monthKey(now, calendar: cal)
        #expect(key == "2026-09")
        #expect(Store.catchCount(monthlyCount: 4, countMonth: key, at: now, calendar: cal) == 4)
    }

    @Test func catchCountMonthBoundaryTick() {
        // Case 9: the dropdown's minute tick crosses midnight on the 1st.
        let before = date(2026, 6, 30, 23, 59)
        let after = date(2026, 7, 1, 0, 0)
        #expect(Store.catchCount(monthlyCount: 2, countMonth: "2026-06", at: before, calendar: cal) == 2)
        #expect(Store.catchCount(monthlyCount: 2, countMonth: "2026-06", at: after, calendar: cal) == 0)
    }

    @Test func catchCountRespectsCalendarTimeZone() {
        // The same instant is June 30 in Santo Domingo and July 1 in UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = date(2026, 6, 30, 23, 30)   // 23:30 AST = 03:30 UTC July 1
        #expect(Store.catchCount(monthlyCount: 2, countMonth: "2026-06", at: instant, calendar: cal) == 2)
        #expect(Store.catchCount(monthlyCount: 2, countMonth: "2026-06", at: instant, calendar: utc) == 0)
        #expect(Store.catchCount(monthlyCount: 2, countMonth: "2026-07", at: instant, calendar: utc) == 2)
    }
}
