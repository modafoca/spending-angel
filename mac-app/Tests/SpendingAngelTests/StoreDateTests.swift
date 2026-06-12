import Foundation
import Testing
@testable import SpendingAngel

/// Date math behind the brag stat + streak (M-F1). Uses a pinned calendar so
/// results don't depend on the machine running the tests.
struct StoreDateTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Santo_Domingo")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func monthKeyFormat() {
        #expect(Store.monthKey(date(2026, 6, 12), calendar: cal) == "2026-06")
        #expect(Store.monthKey(date(2026, 11, 1), calendar: cal) == "2026-11")
    }

    @Test func monthKeyLateNightStaysInLocalMonth() {
        // 11:30pm Dec 31 local is still December locally (would be January in UTC).
        #expect(Store.monthKey(date(2025, 12, 31, 23, 30), calendar: cal) == "2025-12")
        #expect(Store.monthKey(date(2026, 1, 1, 0, 30), calendar: cal) == "2026-01")
    }

    @Test func daysBetweenSameDay() {
        #expect(Store.daysBetween(date(2026, 6, 12, 9), date(2026, 6, 12, 22), calendar: cal) == 0)
    }

    @Test func daysBetweenMidnightEdge() {
        // Catch at 11:50pm, checked at 7am the next morning: that's 1 day, not 0.
        #expect(Store.daysBetween(date(2026, 6, 11, 23, 50), date(2026, 6, 12, 7, 0), calendar: cal) == 1)
    }

    @Test func daysBetweenLongGap() {
        #expect(Store.daysBetween(date(2026, 6, 1), date(2026, 6, 11), calendar: cal) == 10)
    }

    @Test func daysBetweenAcrossMonthAndYear() {
        #expect(Store.daysBetween(date(2025, 12, 31, 23, 0), date(2026, 1, 2, 1, 0), calendar: cal) == 2)
    }
}
