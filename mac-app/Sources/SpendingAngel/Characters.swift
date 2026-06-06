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
}
