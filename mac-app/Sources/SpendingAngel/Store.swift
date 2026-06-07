import Foundation
import Combine

/// The brain's persistent state: goal, active character, on/off, snooze, and the
/// M-04 stat (monthly catch count + streak). Backed by UserDefaults. The bridge
/// (M-05) calls `recordCatch()` on real intents, same as "Test the catch" does.
final class Store: ObservableObject {
    @Published var goal: String
    @Published var activeCharacter: CharacterID
    @Published var enabled: Bool
    @Published var snoozeUntil: Date?

    // M-04 — brag stat + streak
    @Published var monthlyCount: Int
    @Published var countMonth: String              // "yyyy-MM"
    @Published var lastCatchDate: Date?

    private let d = UserDefaults.standard
    private var bag = Set<AnyCancellable>()

    init() {
        goal = d.string(forKey: "goal") ?? ""
        activeCharacter = CharacterID(rawValue: d.string(forKey: "activeCharacter") ?? "") ?? .angel
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        let stored = d.object(forKey: "snoozeUntil") as? Date
        snoozeUntil = (stored.map { $0 > Date() } ?? false) ? stored : nil

        monthlyCount = d.integer(forKey: "monthlyCount")
        countMonth = d.string(forKey: "countMonth") ?? Store.monthKey(Date())
        lastCatchDate = d.object(forKey: "lastCatchDate") as? Date

        $goal.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "goal") }.store(in: &bag)
        $activeCharacter.dropFirst().sink { [weak self] in self?.d.set($0.rawValue, forKey: "activeCharacter") }.store(in: &bag)
        $enabled.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "enabled") }.store(in: &bag)
        $snoozeUntil.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "snoozeUntil") }.store(in: &bag)
        $monthlyCount.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "monthlyCount") }.store(in: &bag)
        $countMonth.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "countMonth") }.store(in: &bag)
        $lastCatchDate.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "lastCatchDate") }.store(in: &bag)
    }

    var isSnoozed: Bool {
        if let u = snoozeUntil, u > Date() { return true }
        return false
    }

    /// Whether a *real* checkout intent (M-05) would perform. The manual "Test
    /// the catch" button ignores this so you can always demo.
    var onDuty: Bool { enabled && !isSnoozed }

    var statusText: String {
        if !enabled { return "Off" }
        if isSnoozed { return "Snoozed" }
        return "On duty"
    }

    func snooze(hours: Double) { snoozeUntil = Date().addingTimeInterval(hours * 3600) }
    func wake() { snoozeUntil = nil }

    // MARK: - Stat

    /// Record a catch: bump the monthly count (resetting at month boundaries) and
    /// reset the streak clock.
    func recordCatch() {
        let now = Date()
        let m = Store.monthKey(now)
        if m != countMonth {
            countMonth = m
            monthlyCount = 0
        }
        monthlyCount += 1
        lastCatchDate = now
    }

    /// Whole days since the last catch ("almost slip"). nil if never caught.
    var streakDays: Int? {
        guard let last = lastCatchDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
