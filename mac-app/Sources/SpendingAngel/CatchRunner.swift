import Foundation

/// One place that sequences a catch (audit 2026-09, NATIVE-03). Ask the overlay
/// first; only when it admitted the performance record the stat and log
/// `catch.performed`, otherwise log `catch.skipped_busy`. Both the bridge path
/// and the manual Test button go through here so the stat can never count a
/// catch nobody saw (voice clips run up to ~12 s against an 8 s bridge
/// throttle, so overlap is routine, not exotic).
///
/// Pure in the sense that every side effect is injected: `perform` is the
/// overlay, `record` is the Store, `log` defaults to `Log.info` so production
/// call sites omit it and tests pass a capturing closure. Hostnames are clipped
/// here as well as in `validate()`, so no caller can write an unbounded name.
enum CatchRunner {
    @discardableResult
    static func run(goal: String,
                    character: CharacterID,
                    source: String,                        // "bridge" | "test"
                    hostname: String,                      // intent hostname, or "manual test"
                    intentID: String?,
                    perform: (String, CharacterID) -> Bool,
                    record: () -> Void,
                    log: (String, String, [String: String]) -> Void = Log.info) -> Bool {
        let fields = ["intent_id": intentID ?? "", "character": character.rawValue, "source": source]
        let host = Log.clip(hostname)          // bounded even if validate() was bypassed (review R-03)
        let admitted = perform(goal, character)
        if admitted {
            record()
            log("catch.performed", host, fields)
        } else {
            log("catch.skipped_busy", host, fields)
        }
        return admitted
    }

    /// The bridge's on-duty decision, pure so the off / snoozed / busy / shown
    /// mapping is unit-tested without AppKit (Round 3): `!enabled` → off; a
    /// snooze deadline still ahead of `now` → snoozed; otherwise `admit` runs
    /// the catch and its result decides — the character that performed means
    /// shown, nil means the overlay was busy. `admit` is only called on the
    /// on-duty path, so the character pick (which consumes Shake It Up's
    /// anti-repeat) never happens for a skipped intent. Logging stays where it
    /// was: `admit` goes through `run` (performed / skipped_busy) and the caller
    /// writes the off-duty line via `skipOffDuty`.
    static func decide(enabled: Bool, snoozeUntil: Date?, now: Date,
                       admit: () -> CharacterID?) -> IntentOutcome {
        guard enabled else { return .skipped(.off) }
        if let until = snoozeUntil, until > now { return .skipped(.snoozed) }
        guard let character = admit() else { return .skipped(.busy) }
        return .shown(character: character)
    }

    /// The bridge's off-duty branch, here rather than inline in AppDelegate so
    /// the hostname bound is one rule in one place and unit-testable. Nothing is
    /// performed or recorded; the intent is only noted as skipped.
    static func skipOffDuty(hostname: String, intentID: String?,
                            log: (String, String, [String: String]) -> Void = Log.info) {
        log("catch.skipped_off_duty", Log.clip(hostname), ["intent_id": intentID ?? ""])
    }
}
