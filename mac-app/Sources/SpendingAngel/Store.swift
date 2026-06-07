import Foundation
import Combine

/// The brain's persistent state: goal, active character, on/off, snooze, shuffle,
/// and the M-04 stat (monthly catch count + streak). Backed by UserDefaults.
/// A shared singleton so the SwiftUI scene + the AppDelegate bridge use one instance.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var goal: String
    @Published var activeCharacter: CharacterID
    @Published var enabled: Bool
    @Published var snoozeUntil: Date?
    @Published var shuffleMode: Bool          // M-07b — "Shake It Up"

    // M-04 — brag stat + streak
    @Published var monthlyCount: Int
    @Published var countMonth: String          // "yyyy-MM"
    @Published var lastCatchDate: Date?

    private var lastShuffled: CharacterID?     // anti-repeat for shuffle
    private let d = UserDefaults.standard
    private var bag = Set<AnyCancellable>()

    init() {
        goal = d.string(forKey: "goal") ?? ""
        activeCharacter = CharacterID(rawValue: d.string(forKey: "activeCharacter") ?? "") ?? .angel
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        let stored = d.object(forKey: "snoozeUntil") as? Date
        snoozeUntil = (stored.map { $0 > Date() } ?? false) ? stored : nil
        shuffleMode = d.bool(forKey: "shuffleMode")

        monthlyCount = d.integer(forKey: "monthlyCount")
        countMonth = d.string(forKey: "countMonth") ?? Store.monthKey(Date())
        lastCatchDate = d.object(forKey: "lastCatchDate") as? Date

        $goal.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "goal") }.store(in: &bag)
        $activeCharacter.dropFirst().sink { [weak self] in self?.d.set($0.rawValue, forKey: "activeCharacter") }.store(in: &bag)
        $enabled.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "enabled") }.store(in: &bag)
        $snoozeUntil.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "snoozeUntil") }.store(in: &bag)
        $shuffleMode.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "shuffleMode") }.store(in: &bag)
        $monthlyCount.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "monthlyCount") }.store(in: &bag)
        $countMonth.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "countMonth") }.store(in: &bag)
        $lastCatchDate.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "lastCatchDate") }.store(in: &bag)
    }

    var isSnoozed: Bool {
        if let u = snoozeUntil, u > Date() { return true }
        return false
    }

    var onDuty: Bool { enabled && !isSnoozed }

    var statusText: String {
        if !enabled { return "Off" }
        if isSnoozed { return "Snoozed" }
        return "On duty"
    }

    func snooze(hours: Double) { snoozeUntil = Date().addingTimeInterval(hours * 3600) }
    func wake() { snoozeUntil = nil }

    /// Which character performs the next catch: the active one normally, or a
    /// random one (no immediate repeat) when Shake It Up is on.
    func nextCatchCharacter() -> CharacterID {
        guard shuffleMode else { return activeCharacter }
        let pool = CharacterID.allCases.filter { $0 != lastShuffled }
        let pick = pool.randomElement() ?? activeCharacter
        lastShuffled = pick
        return pick
    }

    // MARK: - Stat

    func recordCatch() {
        let now = Date()
        let m = Store.monthKey(now)
        if m != countMonth { countMonth = m; monthlyCount = 0 }
        monthlyCount += 1
        lastCatchDate = now
    }

    var streakDays: Int? {
        guard let last = lastCatchDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }

    static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
