import Foundation
import Testing
@testable import SpendingAngel

/// The bridge's HTTP parsing + intent validation (M-F1 hardening). Anything on
/// this Mac can hit the port, so every branch here is a trust boundary.
struct BridgeParsingTests {

    // MARK: Request line

    @Test func methodAndPath() {
        let header = "POST /intent HTTP/1.1\r\nHost: 127.0.0.1"
        #expect(BridgeServer.method(header) == "POST")
        #expect(BridgeServer.path(header) == "/intent")
    }

    @Test func garbageRequestLine() {
        #expect(BridgeServer.method("") == "")
        #expect(BridgeServer.path("POST") == "")
    }

    // MARK: Content-Length

    @Test func contentLengthPresent() {
        #expect(BridgeServer.contentLength("POST / HTTP/1.1\r\nContent-Length: 42") == 42)
    }

    @Test func contentLengthCaseInsensitiveAndPadded() {
        #expect(BridgeServer.contentLength("POST / HTTP/1.1\r\ncontent-length:  7 ") == 7)
    }

    @Test func contentLengthAbsentMeansNoBody() {
        #expect(BridgeServer.contentLength("GET / HTTP/1.1\r\nHost: x") == 0)
    }

    @Test func contentLengthMalformedIsRejected() {
        #expect(BridgeServer.contentLength("POST / HTTP/1.1\r\nContent-Length: abc") == nil)
        #expect(BridgeServer.contentLength("POST / HTTP/1.1\r\nContent-Length: -5") == nil)
    }

    // MARK: Intent decoding + validation

    private func intent(type: String = "checkout_intent", trigger: String = "click",
                        hostname: String = "amazon.com", id: String? = "abc-123") -> Intent {
        Intent(id: id, type: type, trigger: trigger, hostname: hostname, ts: 1_700_000_000_000)
    }

    @Test func validIntentPasses() {
        #expect(BridgeServer.validate(intent()) == nil)
        #expect(BridgeServer.validate(intent(trigger: "load")) == nil)
        #expect(BridgeServer.validate(intent(trigger: "simulated", id: nil)) == nil)  // old sensor, no id
    }

    @Test func wrongTypeRejected() {
        #expect(BridgeServer.validate(intent(type: "foo")) != nil)
    }

    @Test func unknownTriggerRejected() {
        #expect(BridgeServer.validate(intent(trigger: "keypress")) != nil)
    }

    @Test func badHostnameRejected() {
        #expect(BridgeServer.validate(intent(hostname: "")) != nil)
        #expect(BridgeServer.validate(intent(hostname: "   ")) != nil)
        #expect(BridgeServer.validate(intent(hostname: String(repeating: "a", count: 300))) != nil)
    }

    @Test func decodeWithAndWithoutID() throws {
        let with = #"{"id":"x1","type":"checkout_intent","trigger":"click","hostname":"a.com","ts":1}"#
        let without = #"{"type":"checkout_intent","trigger":"load","hostname":"b.com","ts":2}"#
        #expect(try JSONDecoder().decode(Intent.self, from: Data(with.utf8)).id == "x1")
        #expect(try JSONDecoder().decode(Intent.self, from: Data(without.utf8)).id == nil)
    }

    @Test func garbageBodyFailsDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Intent.self, from: Data("not json".utf8))
        }
    }
}
