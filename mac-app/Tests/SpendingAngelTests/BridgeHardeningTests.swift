import Foundation
import Testing
@testable import SpendingAngel

/// Bridge hardening (audit 2026-09): the header cap is enforced whether or not
/// the "\r\n\r\n" delimiter has arrived, `id` is bounded, and every bound is in
/// UTF-8 bytes — a grapheme cluster can carry thousands of combining marks, so
/// `String.count` is no bound at all. All statics, no Log writes.
struct BridgeHardeningTests {

    private static let crlf2 = Data("\r\n\r\n".utf8)
    // `makeIntent` / `combiningBomb` come from TestFixtures.swift.

    // MARK: id bound (maxIDLength = 128 UTF-8 bytes)

    @Test func maxIDLengthIsPinned() {
        #expect(BridgeServer.maxIDLength == 128)
        #expect(BridgeServer.maxHeaderBytes == 8_192)
        #expect(BridgeServer.maxBodyBytes == 1_000_000)
    }

    @Test func idWithinBoundPasses() {
        #expect(BridgeServer.validate(makeIntent(id: String(repeating: "a", count: 128))) == nil)
        #expect(BridgeServer.validate(makeIntent(id: UUID().uuidString)) == nil)      // 36 chars, the real thing
        #expect(BridgeServer.validate(makeIntent(id: "")) == nil)                     // empty id is tolerated
    }

    @Test func idOverBoundRejected() {
        #expect(BridgeServer.validate(makeIntent(id: String(repeating: "a", count: 129))) == "bad id")
        #expect(BridgeServer.validate(makeIntent(id: String(repeating: "a", count: 950_000))) == "bad id")
    }

    @Test func nilIDStillPasses() {
        #expect(BridgeServer.validate(makeIntent(id: nil)) == nil)
    }

    @Test func idBoundIsBytesNotGraphemes() {
        let id = combiningBomb()
        #expect(id.count == 1)
        #expect(id.utf8.count == 10_001)
        #expect(BridgeServer.validate(makeIntent(id: id)) == "bad id")   // fails if anyone reintroduces id.count
    }

    @Test func idBoundCountsMultibyteScalars() {
        // 64 × "é" = 64 characters but 128 bytes → passes; 65 → 130 bytes → rejected.
        #expect(BridgeServer.validate(makeIntent(id: String(repeating: "é", count: 64))) == nil)
        #expect(BridgeServer.validate(makeIntent(id: String(repeating: "é", count: 65))) == "bad id")
    }

    // MARK: hostname bound (1…253 UTF-8 bytes after trimming)

    @Test func hostnameAtBoundPasses() {
        #expect(BridgeServer.validate(makeIntent(hostname: String(repeating: "a", count: 253))) == nil)
        #expect(BridgeServer.validate(makeIntent(hostname: "  " + String(repeating: "a", count: 253) + "  ")) == nil)
        #expect(BridgeServer.validate(makeIntent(hostname: "a")) == nil)
    }

    @Test func hostnameOverBoundRejected() {
        #expect(BridgeServer.validate(makeIntent(hostname: String(repeating: "a", count: 254))) == "bad hostname")
    }

    @Test func hostnameBoundIsBytesNotGraphemes() {
        let host = combiningBomb()
        #expect(host.count == 1)
        #expect(BridgeServer.validate(makeIntent(hostname: host)) == "bad hostname")
        // 127 × "é" = 254 bytes → rejected even though it is only 127 characters.
        #expect(BridgeServer.validate(makeIntent(hostname: String(repeating: "é", count: 127))) == "bad hostname")
        #expect(BridgeServer.validate(makeIntent(hostname: String(repeating: "é", count: 126))) == nil)
    }

    // MARK: type / trigger problem strings are clipped (64 bytes)

    @Test func unknownTypeAndTriggerProblemsNameTheValue() {
        #expect(BridgeServer.validate(makeIntent(type: "foo")) == "unknown type \"foo\"")
        #expect(BridgeServer.validate(makeIntent(trigger: "keypress")) == "unknown trigger \"keypress\"")
    }

    @Test func oversizedTypeProblemIsClipped() throws {
        let big = String(repeating: "a", count: 10_000)
        let problem = try #require(BridgeServer.validate(makeIntent(type: big)))
        #expect(problem.utf8.count < 200)
        #expect(problem.hasPrefix("unknown type \""))
        #expect(problem.contains("…"))
        #expect(problem.contains(String(repeating: "a", count: 64)))
        #expect(!problem.contains(String(repeating: "a", count: 65)))

        let bomb = try #require(BridgeServer.validate(makeIntent(type: combiningBomb())))
        #expect(bomb.utf8.count < 200)
        #expect(bomb.hasPrefix("unknown type \""))
    }

    @Test func oversizedTriggerProblemIsClipped() throws {
        let big = String(repeating: "z", count: 900_000)
        let problem = try #require(BridgeServer.validate(makeIntent(trigger: big)))
        #expect(problem.utf8.count < 200)
        #expect(problem.hasPrefix("unknown trigger \""))
        #expect(problem.contains("…"))

        let bomb = try #require(BridgeServer.validate(makeIntent(trigger: combiningBomb())))
        #expect(bomb.utf8.count < 200)
    }

    @Test func validationOrderTypeBeforeTriggerBeforeIDBeforeHost() {
        // Pins the order the problem strings come out in, so logs stay predictable.
        let bad = makeIntent(type: "x", trigger: "y", hostname: "", id: String(repeating: "a", count: 200))
        #expect(BridgeServer.validate(bad) == "unknown type \"x\"")
        let badTrigger = makeIntent(trigger: "y", hostname: "", id: String(repeating: "a", count: 200))
        #expect(BridgeServer.validate(badTrigger) == "unknown trigger \"y\"")
        let badID = makeIntent(hostname: "", id: String(repeating: "a", count: 200))
        #expect(BridgeServer.validate(badID) == "bad id")
    }

    // MARK: headerExceedsCap — both branches of read()

    @Test func headerCapWithoutDelimiter() {
        #expect(BridgeServer.headerExceedsCap(Data(repeating: 0x61, count: 8_193), delimiter: nil))
        #expect(!BridgeServer.headerExceedsCap(Data(repeating: 0x61, count: 8_192), delimiter: nil))
        #expect(!BridgeServer.headerExceedsCap(Data(), delimiter: nil))
        #expect(!BridgeServer.headerExceedsCap(Data("POST /intent HTTP/1.1\r\nHost: x".utf8), delimiter: nil))
    }

    @Test func headerCapWithDelimiter() {
        // A 12 KB header that arrives with its delimiter in one read used to slip through.
        let big = Data(repeating: 0x61, count: 12_000) + Self.crlf2 + Data("{}".utf8)
        #expect(BridgeServer.headerExceedsCap(big, delimiter: big.range(of: Self.crlf2)))

        let ok = Data(repeating: 0x61, count: 8_000) + Self.crlf2 + Data("{}".utf8)
        #expect(!BridgeServer.headerExceedsCap(ok, delimiter: ok.range(of: Self.crlf2)))

        let exact = Data(repeating: 0x61, count: 8_192) + Self.crlf2
        #expect(!BridgeServer.headerExceedsCap(exact, delimiter: exact.range(of: Self.crlf2)))

        let one = Data(repeating: 0x61, count: 8_193) + Self.crlf2
        #expect(BridgeServer.headerExceedsCap(one, delimiter: one.range(of: Self.crlf2)))
    }

    @Test func headerCapIgnoresBodyBytesWhenDelimiterPresent() {
        // Header well under the cap, body far over it: still fine — only header bytes count.
        let buf = Data("POST /intent HTTP/1.1\r\nContent-Length: 20000".utf8) + Self.crlf2 + Data(repeating: 0x7b, count: 20_000)
        #expect(!BridgeServer.headerExceedsCap(buf, delimiter: buf.range(of: Self.crlf2)))
    }

    @Test func headerCapDelimiterAtStart() {
        let buf = Self.crlf2 + Data(repeating: 0x61, count: 9_000)
        #expect(!BridgeServer.headerExceedsCap(buf, delimiter: buf.range(of: Self.crlf2)))
    }

    @Test func headerCapOnDataSlice() {
        // Pins the `lowerBound - startIndex` semantics: a Data slice does not
        // start at 0. With `$0.lowerBound` alone this sees 8 196 and wrongly trips.
        let full = Data(repeating: 0x78, count: 4) + Data(repeating: 0x61, count: 8_192) + Self.crlf2
        let slice = full[4...]
        #expect(slice.startIndex == 4)
        #expect(!BridgeServer.headerExceedsCap(slice, delimiter: slice.range(of: Self.crlf2)))

        let fullOver = Data(repeating: 0x78, count: 4) + Data(repeating: 0x61, count: 8_193) + Self.crlf2
        let sliceOver = fullOver[4...]
        #expect(BridgeServer.headerExceedsCap(sliceOver, delimiter: sliceOver.range(of: Self.crlf2)))

        // No-delimiter branch on a slice uses the slice's own count.
        let sliceNoSep = (Data(repeating: 0x78, count: 4) + Data(repeating: 0x61, count: 8_192))[4...]
        #expect(!BridgeServer.headerExceedsCap(sliceNoSep, delimiter: nil))
        let sliceNoSepOver = (Data(repeating: 0x78, count: 4) + Data(repeating: 0x61, count: 8_193))[4...]
        #expect(BridgeServer.headerExceedsCap(sliceNoSepOver, delimiter: nil))
    }

    @Test func headerCapChunkedAccumulationBelowCapProceeds() {
        // Case 14: delimiter split across chunks, total header < 8 KB — every pass passes.
        var buf = Data(repeating: 0x61, count: 4_000)
        #expect(!BridgeServer.headerExceedsCap(buf, delimiter: buf.range(of: Self.crlf2)))
        buf.append(Data("\r\n".utf8))
        #expect(!BridgeServer.headerExceedsCap(buf, delimiter: buf.range(of: Self.crlf2)))
        buf.append(Data("\r\n".utf8))
        let sep = buf.range(of: Self.crlf2)
        #expect(sep != nil)
        #expect(!BridgeServer.headerExceedsCap(buf, delimiter: sep))
    }

    // MARK: Content-Length semantics used by the 413 gate (unchanged, pinned)

    @Test func contentLengthAbsentStillZero() {
        #expect(BridgeServer.contentLength("POST /intent HTTP/1.1\r\nAuthorization: Bearer x") == 0)
    }

    @Test func contentLengthOverBodyCapIsDetectable() throws {
        // Case 26: ~1.8 MB combining-mark id is refused on Content-Length alone.
        let n = try #require(BridgeServer.contentLength("POST /intent HTTP/1.1\r\nContent-Length: 1800000"))
        #expect(n > BridgeServer.maxBodyBytes)
        let ok = try #require(BridgeServer.contentLength("POST /intent HTTP/1.1\r\nContent-Length: 1000000"))
        #expect(ok <= BridgeServer.maxBodyBytes)
    }

    // MARK: Case 15 / 26 end-to-end at the decode + validate layer

    @Test func oversizedIDDecodesThenFailsValidationWithClippedLog() throws {
        let id = String(repeating: "a", count: 950_000)
        let json = #"{"id":"\#(id)","type":"checkout_intent","trigger":"click","hostname":"a.com","ts":1}"#
        let body = Data(json.utf8)
        #expect(body.count <= BridgeServer.maxBodyBytes)
        let decoded = try JSONDecoder().decode(Intent.self, from: body)
        #expect(BridgeServer.validate(decoded) == "bad id")
        #expect(Log.clip(decoded.id ?? "").utf8.count <= 259)
    }
}
