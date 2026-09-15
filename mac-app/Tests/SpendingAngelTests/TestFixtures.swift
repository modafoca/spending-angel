import Foundation
@testable import SpendingAngel

// Fixtures shared by the bridge / log suites so each file does not carry its
// own copy (review 2026-09, R-09). Free functions, internal to the test module.

/// A well-formed intent with every field overridable. `ts` is a fixed epoch so
/// failures read the same across runs.
func makeIntent(type: String = "checkout_intent", trigger: String = "click",
                hostname: String = "amazon.com", id: String? = "abc-123") -> Intent {
    Intent(id: id, type: type, trigger: trigger, hostname: hostname, ts: 1_700_000_000_000)
}

/// One grapheme cluster ("a" + n combining acute accents), 1 + 2·n UTF-8 bytes.
/// The shape that proves a bound is in bytes, not `String.count`.
func combiningBomb(_ n: Int = 5_000) -> String {
    "a" + String(repeating: "\u{0301}", count: n)
}
