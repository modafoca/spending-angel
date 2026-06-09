import Foundation

/// The locked cast. Art + voices are placeholders until M-06 (emoji stand-ins
/// here); this is the single source for the roster the dropdown + overlay read.
enum CharacterID: String, CaseIterable, Identifiable {
    case angel, papi, wizard, mom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .angel:  return "The Angel"
        case .papi:   return "Dominican Papi"
        case .wizard: return "The Wizard"
        case .mom:    return "Asian Mom"
        }
    }

    /// PLACEHOLDER portrait — real Figma art swaps in at M-06.
    var placeholderEmoji: String {
        switch self {
        case .angel:  return "😇"
        case .papi:   return "🧔🏽"
        case .wizard: return "🧙"
        case .mom:    return "👩"
        }
    }

    var tagline: String {
        switch self {
        case .angel:  return "Gentle. Always watching."
        case .papi:   return "Ay, no, mi amor."
        case .wizard: return "You shall not pass… checkout."
        case .mom:    return "You have one already!"
        }
    }

    /// Whether the overlay entrance slides in from the right (vs. playing the
    /// animation in place). Papi slides; Angel/Wizard play in place.
    var slidesIn: Bool {
        switch self {
        case .papi, .mom: return true
        default:          return false
        }
    }

    /// The brag stat — the character flexes the (real) catch count, anchored to
    /// the goal where it fits. Written copy, not voiced.
    func brag(count n: Int, goal: String) -> String {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .angel:
            return "I've stopped you \(n) times. You're welcome."
        case .papi:
            return g.isEmpty
                ? "Te he cuidado \(n) veces, mi amor."
                : "Te he cuidado \(n) veces pa' \(g), mi amor."
        case .wizard:
            return g.isEmpty
                ? "\(n) times I have stayed your hand."
                : "\(n) times I have stayed your hand. \(g) thanks you."
        case .mom:
            return "\(n) times. \(n). And not one thank you."
        }
    }

    /// The streak — days since the last "almost slip" (last catch). A catch resets it.
    func streak(days d: Int) -> String {
        let day = d == 1 ? "day" : "days"
        switch self {
        case .angel:  return "\(d) \(day) clean. Proud of you."
        case .papi:   return "\(d) \(d == 1 ? "día" : "días") sin resbalar. Así me gusta."
        case .wizard: return "\(d) \(day) the realm has held. Do not falter now."
        case .mom:    return "\(d) \(day) good. Don't ruin it."
        }
    }
}
