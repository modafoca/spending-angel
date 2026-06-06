import Foundation
import Combine

/// The brain's persistent state: goal, active character, on/off, snooze.
/// Backed by UserDefaults. The stat + streak (M-04) and the bridge (M-05) read
/// from here later.
final class Store: ObservableObject {
    @Published var goal: String
    @Published var activeCharacter: CharacterID
    @Published var enabled: Bool
    @Published var snoozeUntil: Date?

    private let d = UserDefaults.standard
    private var bag = Set<AnyCancellable>()

    init() {
        goal = d.string(forKey: "goal") ?? ""
        activeCharacter = CharacterID(rawValue: d.string(forKey: "activeCharacter") ?? "") ?? .angel
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        let stored = d.object(forKey: "snoozeUntil") as? Date
        snoozeUntil = (stored.map { $0 > Date() } ?? false) ? stored : nil

        $goal.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "goal") }.store(in: &bag)
        $activeCharacter.dropFirst().sink { [weak self] in self?.d.set($0.rawValue, forKey: "activeCharacter") }.store(in: &bag)
        $enabled.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "enabled") }.store(in: &bag)
        $snoozeUntil.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "snoozeUntil") }.store(in: &bag)
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
}
