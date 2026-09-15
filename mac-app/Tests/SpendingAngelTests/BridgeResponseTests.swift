import Foundation
import Testing
@testable import SpendingAngel

/// Round 3 — the bridge says what it did. Pins the exact bytes of every body
/// shape (sorted keys, no whitespace, second-resolution UTC snooze deadline)
/// and the head's Content-Type / Content-Length switch, because the sensor's
/// `status.js` renders straight from these fields. Statics only, no Log writes.
struct BridgeResponseTests {

    /// 2026-09-15T22:43:54.7Z — the fraction proves the body rounds to seconds.
    private let snooze = Date(timeIntervalSince1970: 1_789_512_234.7)

    private func body(_ outcome: IntentOutcome, snoozeUntil: Date? = nil, version: String = "0.6.0") -> String {
        String(decoding: BridgeServer.responseBody(outcome, snoozeUntil: snoozeUntil, appVersion: version), as: UTF8.self)
    }

    private func throttled(_ seconds: TimeInterval) -> String {
        String(decoding: BridgeServer.throttledBody(retryIn: seconds, appVersion: "0.6.0"), as: UTF8.self)
    }

    // MARK: the five shapes, byte for byte

    @Test func shownBody() {
        #expect(body(.shown(character: .mom)) == #"{"app_version":"0.6.0","character":"mom","result":"shown"}"#)
        for c in CharacterID.allCases {
            #expect(body(.shown(character: c)) == #"{"app_version":"0.6.0","character":"\#(c.rawValue)","result":"shown"}"#)
        }
    }

    @Test func offBody() {
        #expect(body(.skipped(.off)) == #"{"app_version":"0.6.0","reason":"off","result":"skipped"}"#)
    }

    @Test func snoozedBody() {
        #expect(body(.skipped(.snoozed), snoozeUntil: snooze)
                == #"{"app_version":"0.6.0","reason":"snoozed","result":"skipped","snooze_until":"2026-09-15T22:43:54Z"}"#)
    }

    @Test func busyBody() {
        #expect(body(.skipped(.busy)) == #"{"app_version":"0.6.0","reason":"busy","result":"skipped"}"#)
    }

    @Test func throttledBody() {
        #expect(throttled(4.3) == #"{"app_version":"0.6.0","reason":"throttled","result":"skipped","retry_in_s":5}"#)
    }

    // MARK: edges

    @Test func snoozeDeadlineOnlyTravelsWhenSnoozed() {
        // A deadline that is set but irrelevant (off, busy, shown) is not echoed.
        #expect(!body(.skipped(.off), snoozeUntil: snooze).contains("snooze_until"))
        #expect(!body(.skipped(.busy), snoozeUntil: snooze).contains("snooze_until"))
        #expect(!body(.shown(character: .angel), snoozeUntil: snooze).contains("snooze_until"))
        // Snoozed with no known deadline: the key is omitted, not null.
        #expect(body(.skipped(.snoozed)) == #"{"app_version":"0.6.0","reason":"snoozed","result":"skipped"}"#)
    }

    @Test func snoozeDeadlineIsUTCAtSecondResolution() {
        // Default formatter: "Z", no fraction — whatever the machine's zone.
        let s = body(.skipped(.snoozed), snoozeUntil: snooze)
        #expect(s.contains(#""snooze_until":"2026-09-15T22:43:54Z""#))
        #expect(!s.contains("54.7"))
        #expect(!s.contains("+"))
    }

    @Test func retryInSecondsRoundsUpAndNeverBelowOne() {
        #expect(throttled(8).contains(#""retry_in_s":8"#))
        #expect(throttled(7.01).contains(#""retry_in_s":8"#))
        #expect(throttled(0.2).contains(#""retry_in_s":1"#))
        #expect(throttled(0).contains(#""retry_in_s":1"#))
        #expect(throttled(-3).contains(#""retry_in_s":1"#))
    }

    @Test func versionIsPassedThroughNotHardcoded() {
        #expect(body(.skipped(.off), version: "9.9.9").hasPrefix(#"{"app_version":"9.9.9""#))
        #expect(String(decoding: BridgeServer.throttledBody(retryIn: 1, appVersion: "9.9.9"), as: UTF8.self)
                    .hasPrefix(#"{"app_version":"9.9.9""#))
    }

    @Test func bodiesAreObjectsWithOnlyTheDocumentedKeys() throws {
        let cases: [(Data, Set<String>)] = [
            (BridgeServer.responseBody(.shown(character: .papi), snoozeUntil: nil, appVersion: "0.6.0"),
             ["app_version", "character", "result"]),
            (BridgeServer.responseBody(.skipped(.off), snoozeUntil: nil, appVersion: "0.6.0"),
             ["app_version", "reason", "result"]),
            (BridgeServer.responseBody(.skipped(.snoozed), snoozeUntil: snooze, appVersion: "0.6.0"),
             ["app_version", "reason", "result", "snooze_until"]),
            (BridgeServer.responseBody(.skipped(.busy), snoozeUntil: nil, appVersion: "0.6.0"),
             ["app_version", "reason", "result"]),
            (BridgeServer.throttledBody(retryIn: 5, appVersion: "0.6.0"),
             ["app_version", "reason", "result", "retry_in_s"]),
        ]
        for (data, keys) in cases {
            let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(obj.keys) == keys)
        }
    }

    // MARK: responseHead(status:bodyLength:)

    @Test func headWithBodyDeclaresJSONAndLength() {
        #expect(BridgeServer.responseHead(status: 200, bodyLength: 57)
                == "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: 57\r\nConnection: close\r\n\r\n")
        #expect(BridgeServer.responseHead(status: 429, bodyLength: 80)
                == "HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: 80\r\nConnection: close\r\n\r\n")
    }

    @Test func headWithoutBodyIsUnchanged() {
        // `bodyLength: 0` (and anything non-positive) is the pre-Round-3 head.
        for status in BridgeServer.reasons.keys {
            #expect(BridgeServer.responseHead(status: status, bodyLength: 0) == BridgeServer.responseHead(status: status))
            #expect(!BridgeServer.responseHead(status: status, bodyLength: 0).contains("Content-Type"))
            #expect(BridgeServer.responseHead(status: status, bodyLength: -1).contains("Content-Length: 0\r\n"))
        }
        #expect(BridgeServer.responseHead(status: 200) == "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }

    @Test func headWithBodyStillHasNoCORSAndKeepsThe401Challenge() {
        for status in BridgeServer.reasons.keys {
            let head = BridgeServer.responseHead(status: status, bodyLength: 12)
            #expect(!head.lowercased().contains("access-control"), "status \(status)")
            #expect(head.contains("Connection: close\r\n"), "status \(status)")
            #expect(head.hasSuffix("\r\n\r\n"), "status \(status)")
            #expect(head.contains("WWW-Authenticate") == (status == 401), "status \(status)")
        }
    }

    @Test func declaredLengthMatchesTheRealBody() {
        let data = BridgeServer.responseBody(.shown(character: .wizard), snoozeUntil: nil, appVersion: "0.6.0")
        #expect(data.count == #"{"app_version":"0.6.0","character":"wizard","result":"shown"}"#.utf8.count)
        #expect(BridgeServer.responseHead(status: 200, bodyLength: data.count).contains("Content-Length: \(data.count)\r\n"))
    }
}
