import Foundation
import Testing
@testable import SpendingAngel

/// `Log.clip` — the byte-bounded copy every request-derived log field goes
/// through (audit 2026-09, bridge hardening). Pure; never touches `Log.shared`.
struct LogClipTests {

    // `combiningBomb` comes from TestFixtures.swift.

    @Test func clipLeavesShortStrings() {
        #expect(Log.clip("abc") == "abc")
        #expect(Log.clip("") == "")
        let exact = String(repeating: "a", count: 256)
        #expect(Log.clip(exact) == exact)                 // identity, not a copy with "…"
        #expect(!Log.clip(exact).hasSuffix("…"))
    }

    @Test func clipTruncatesWithEllipsis() {
        let long = String(repeating: "a", count: 300)
        let out = Log.clip(long)
        #expect(out.count == 257)
        #expect(out.utf8.count == 256 + 3)
        #expect(out.hasSuffix("…"))
        #expect(out.hasPrefix(String(repeating: "a", count: 256)))
    }

    @Test func clipOneOverIsCut() {
        let out = Log.clip(String(repeating: "a", count: 257))
        #expect(out.count == 257)
        #expect(out.hasSuffix("…"))
    }

    @Test func clipHonoursCustomMax() {
        #expect(Log.clip("abcdef", max: 3) == "abc…")
        #expect(Log.clip("abc", max: 3) == "abc")
        #expect(Log.clip(String(repeating: "a", count: 100), max: 64).utf8.count == 67)
    }

    @Test func clipBoundsBytesNotGraphemes() {
        // One grapheme cluster, 10 001 bytes. A `prefix(max)`-on-Characters
        // implementation returns the input untouched and fails this.
        let value = combiningBomb()
        #expect(value.count == 1)
        #expect(value.utf8.count == 10_001)
        let out = Log.clip(value, max: 256)
        #expect(out.utf8.count <= 259)
        #expect(out.utf8.count == 258)                    // 1 + 127×2 = 255 fits; 257 would not
        #expect(out.hasSuffix("…"))
        // `hasPrefix("a")` compares grapheme clusters, and "a"+marks is one
        // cluster ≠ "a" — assert at scalar level instead.
        #expect(out.unicodeScalars.first == "a")
        #expect(out.utf8.first == UInt8(ascii: "a"))
    }

    @Test func clipNeverSplitsAScalar() {
        let value = String(repeating: "é", count: 200)    // 2 bytes each, 400 total
        let out = Log.clip(value, max: 255)
        #expect(out.utf8.count == 254 + 3)                // 127 × "é" fits in 255; 128 would be 256
        #expect(!out.contains("\u{FFFD}"))
        #expect(out.hasSuffix("…"))
        let body = out.dropLast()
        #expect(body.count == 127)
        #expect(body.allSatisfy { $0 == "é" })
    }

    @Test func clipNeverSplitsFourByteScalars() {
        let value = String(repeating: "😀", count: 100)   // 4 bytes each
        let out = Log.clip(value, max: 10)
        #expect(out.utf8.count == 8 + 3)                  // two emoji fit in 10 bytes
        #expect(!out.contains("\u{FFFD}"))
        #expect(out == "😀😀…")
    }

    @Test func clipHardBoundAlwaysHolds() {
        // utf8.count <= max + 3 for every shape we throw at it.
        let samples = [String(repeating: "a", count: 1_000), combiningBomb(20_000),
                       String(repeating: "é", count: 1_000), String(repeating: "😀", count: 300),
                       "short", ""]
        for s in samples {
            for max in [0, 1, 2, 3, 4, 64, 255, 256] {
                let out = Log.clip(s, max: max)
                #expect(out.utf8.count <= max + 3, "clip(\(s.utf8.count) bytes, max: \(max)) → \(out.utf8.count) bytes")
                if s.utf8.count <= max { #expect(out == s) }
            }
        }
    }

    @Test func clipWithZeroMaxIsJustEllipsis() {
        #expect(Log.clip("abc", max: 0) == "…")
        #expect(Log.clip("", max: 0) == "")
    }

    @Test func clipKeepsBridgeLogFieldsUnder259Bytes() {
        // The bound BridgeServer relies on for intent_id / hostname (case 15).
        let hostileID = String(repeating: "x", count: 950_000)
        #expect(Log.clip(hostileID).utf8.count == 259)
        #expect(Log.clip(combiningBomb(400_000)).utf8.count <= 259)
    }
}
