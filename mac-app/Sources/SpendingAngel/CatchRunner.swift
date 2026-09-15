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
/// call sites omit it and tests pass a capturing closure.
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
        let admitted = perform(goal, character)
        if admitted {
            record()
            log("catch.performed", hostname, fields)
        } else {
            log("catch.skipped_busy", hostname, fields)
        }
        return admitted
    }
}
