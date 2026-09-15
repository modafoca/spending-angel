import Foundation
import Testing
@testable import SpendingAngel

/// NATIVE-03 — `CatchRunner` sequences perform → record → log so the stat can
/// never count a catch the overlay refused. Every case injects a capturing
/// `log` closure so nothing reaches `Log.shared`.
struct CatchRunnerTests {

    private struct Captured {
        var events: [(event: String, msg: String, fields: [String: String])] = []
        var sequence: [String] = []
    }

    @Test func admittedCatchRecordsAfterPerform() {
        var c = Captured()
        let admitted = CatchRunner.run(
            goal: "a bike", character: .papi, source: "bridge", hostname: "amazon.com", intentID: "abc",
            perform: { _, _ in c.sequence.append("perform"); return true },
            record: { c.sequence.append("record") },
            log: { e, m, f in c.events.append((e, m, f)) })

        #expect(admitted)
        #expect(c.sequence == ["perform", "record"])
        #expect(c.events.count == 1)
        #expect(c.events[0].event == "catch.performed")
        #expect(c.events[0].msg == "amazon.com")
        #expect(c.events[0].fields == ["intent_id": "abc", "character": "papi", "source": "bridge"])
    }

    @Test func busyCatchDoesNotRecord() {
        var c = Captured()
        var recorded = 0
        let admitted = CatchRunner.run(
            goal: "a bike", character: .angel, source: "test", hostname: "manual test", intentID: nil,
            perform: { _, _ in c.sequence.append("perform"); return false },
            record: { recorded += 1 },
            log: { e, m, f in c.events.append((e, m, f)) })

        #expect(!admitted)
        #expect(recorded == 0)
        #expect(c.sequence == ["perform"])
        #expect(c.events.count == 1)
        #expect(c.events[0].event == "catch.skipped_busy")
        #expect(c.events[0].msg == "manual test")
        #expect(c.events[0].fields == ["intent_id": "", "character": "angel", "source": "test"])
    }

    @Test func busyBridgeCatchIsLoggedWithBridgeSource() {
        // Case 11: an intent that passes the 8 s throttle while a 12 s clip holds the panel.
        var c = Captured()
        _ = CatchRunner.run(
            goal: "", character: .wizard, source: "bridge", hostname: "shop.example.test", intentID: "i-2",
            perform: { _, _ in false }, record: { c.sequence.append("record") },
            log: { e, m, f in c.events.append((e, m, f)) })
        #expect(c.sequence.isEmpty)
        #expect(c.events.map(\.event) == ["catch.skipped_busy"])
        #expect(c.events[0].fields["source"] == "bridge")
        #expect(c.events[0].fields["intent_id"] == "i-2")
        #expect(c.events[0].fields["character"] == "wizard")
    }

    @Test func performIsCalledExactlyOnce() {
        for outcome in [true, false] {
            var performs = 0
            _ = CatchRunner.run(
                goal: "g", character: .mom, source: "test", hostname: "h", intentID: nil,
                perform: { _, _ in performs += 1; return outcome },
                record: {}, log: { _, _, _ in })
            #expect(performs == 1)
        }
    }

    @Test func characterAndGoalPassThrough() {
        for character in CharacterID.allCases {
            var seenGoal: String?
            var seenCharacter: CharacterID?
            var fields: [String: String] = [:]
            _ = CatchRunner.run(
                goal: "goal for \(character.rawValue)", character: character, source: "bridge",
                hostname: "h", intentID: "x",
                perform: { g, ch in seenGoal = g; seenCharacter = ch; return true },
                record: {}, log: { _, _, f in fields = f })
            #expect(seenGoal == "goal for \(character.rawValue)")
            #expect(seenCharacter == character)
            #expect(fields["character"] == character.rawValue)
        }
    }

    @Test func emptyGoalPassesThroughUnchanged() {
        var seenGoal: String?
        _ = CatchRunner.run(goal: "", character: .angel, source: "test", hostname: "manual test", intentID: nil,
                            perform: { g, _ in seenGoal = g; return true }, record: {}, log: { _, _, _ in })
        #expect(seenGoal == "")
    }

    @Test func logIsEmittedExactlyOncePerRun() {
        for outcome in [true, false] {
            var count = 0
            _ = CatchRunner.run(goal: "g", character: .angel, source: "test", hostname: "h", intentID: nil,
                                perform: { _, _ in outcome }, record: {}, log: { _, _, _ in count += 1 })
            #expect(count == 1)
        }
    }

    @Test func returnValueMirrorsPerform() {
        #expect(CatchRunner.run(goal: "g", character: .angel, source: "test", hostname: "h", intentID: nil,
                                perform: { _, _ in true }, record: {}, log: { _, _, _ in }) == true)
        #expect(CatchRunner.run(goal: "g", character: .angel, source: "test", hostname: "h", intentID: nil,
                                perform: { _, _ in false }, record: {}, log: { _, _, _ in }) == false)
    }

    @Test func recordRunsBeforeLogOnAdmission() {
        // The stat is bumped before `catch.performed` is written, so a log reader
        // never sees "performed" with a stale count.
        var order: [String] = []
        _ = CatchRunner.run(goal: "g", character: .angel, source: "bridge", hostname: "h", intentID: "1",
                            perform: { _, _ in true },
                            record: { order.append("record") },
                            log: { e, _, _ in order.append(e) })
        #expect(order == ["record", "catch.performed"])
    }

    @Test func fieldsAreIdenticalAcrossOutcomes() {
        var admittedFields: [String: String] = [:]
        var busyFields: [String: String] = [:]
        _ = CatchRunner.run(goal: "g", character: .papi, source: "bridge", hostname: "h", intentID: "same",
                            perform: { _, _ in true }, record: {}, log: { _, _, f in admittedFields = f })
        _ = CatchRunner.run(goal: "g", character: .papi, source: "bridge", hostname: "h", intentID: "same",
                            perform: { _, _ in false }, record: {}, log: { _, _, f in busyFields = f })
        #expect(admittedFields == busyFields)
        #expect(Set(admittedFields.keys) == ["intent_id", "character", "source"])
    }

    @Test func backToBackRunsAgainstABusyThenFreeOverlay() {
        // The manual checklist in code: "▶ test" twice while busy, then once free —
        // exactly one record, one performed, two skipped_busy.
        var busy = true
        var records = 0
        var events: [String] = []
        let perform: (String, CharacterID) -> Bool = { _, _ in !busy }
        for _ in 0..<2 {
            _ = CatchRunner.run(goal: "g", character: .angel, source: "test", hostname: "manual test", intentID: nil,
                                perform: perform, record: { records += 1 }, log: { e, _, _ in events.append(e) })
        }
        busy = false
        _ = CatchRunner.run(goal: "g", character: .angel, source: "test", hostname: "manual test", intentID: nil,
                            perform: perform, record: { records += 1 }, log: { e, _, _ in events.append(e) })
        #expect(records == 1)
        #expect(events == ["catch.skipped_busy", "catch.skipped_busy", "catch.performed"])
    }

    // MARK: hostname is bounded at every log site (review R-03)

    @Test func hostnameIsBoundedEvenWhenValidateWasBypassed() {
        // 20,009 bytes of padded name straight into the runner (validate() is
        // upstream and could be bypassed by a future caller). Both outcomes log
        // a msg of exactly Log.clip's 256 + "…" = 259 bytes.
        let padded = String(repeating: " ", count: 20_000) + "shop.test"
        #expect(padded.utf8.count == 20_009)
        for outcome in [true, false] {
            var events: [(event: String, msg: String)] = []
            _ = CatchRunner.run(goal: "g", character: .angel, source: "bridge", hostname: padded, intentID: "p-1",
                                perform: { _, _ in outcome }, record: {},
                                log: { e, m, _ in events.append((e, m)) })
            #expect(events.count == 1)
            #expect(events[0].event == (outcome ? "catch.performed" : "catch.skipped_busy"))
            #expect(events[0].msg.utf8.count == 259)
            #expect(events[0].msg.hasSuffix("…"))
            #expect(!events[0].msg.contains("shop.test"))   // the name itself is beyond the clip
        }
    }

    @Test func shortHostnamePassesThroughUnchanged() {
        var msg: String?
        _ = CatchRunner.run(goal: "g", character: .papi, source: "bridge", hostname: "amazon.com", intentID: "x",
                            perform: { _, _ in true }, record: {}, log: { _, m, _ in msg = m })
        #expect(msg == "amazon.com")
    }

    @Test func skipOffDutyLogsBoundedHostname() {
        let padded = String(repeating: " ", count: 20_000) + "shop.test"
        var events: [(event: String, msg: String, fields: [String: String])] = []
        CatchRunner.skipOffDuty(hostname: padded, intentID: "abc", log: { e, m, f in events.append((e, m, f)) })
        #expect(events.count == 1)
        #expect(events[0].event == "catch.skipped_off_duty")
        #expect(events[0].msg.utf8.count == 259)
        #expect(events[0].msg.hasSuffix("…"))
        #expect(events[0].fields == ["intent_id": "abc"])

        // nil intent id → "" (same shape as CatchRunner.run's fields), short name untouched.
        var plain: [(event: String, msg: String, fields: [String: String])] = []
        CatchRunner.skipOffDuty(hostname: "amazon.com", intentID: nil, log: { e, m, f in plain.append((e, m, f)) })
        #expect(plain.count == 1)
        #expect(plain[0].event == "catch.skipped_off_duty")
        #expect(plain[0].msg == "amazon.com")
        #expect(plain[0].fields == ["intent_id": ""])
    }
}
