import Foundation
import Testing
@testable import SpendingAngel

/// NATIVE-01 — the bridge's pairing-token gate (audit 2026-09). Everything here
/// is a pure static on `BridgeServer` / `Store`: no listener, no Store instance,
/// no Log writes. The order of the gate (204 → 405 → 404 → 401 → proceed) is
/// pinned here, not just documented.
struct BridgeAuthTests {

    /// A well-formed 64-hex token (deterministic so failures are readable).
    static let T = String(repeating: "0123456789abcdef", count: 4)

    // MARK: tokenMatches

    @Test func tokenMatchesExact() {
        #expect(BridgeServer.tokenMatches(Self.T, expected: Self.T))
        let fresh = Store.generateBridgeToken()
        #expect(BridgeServer.tokenMatches(fresh, expected: fresh))
    }

    @Test func tokenMatchesRejectsNil() {
        #expect(!BridgeServer.tokenMatches(nil, expected: Self.T))
    }

    @Test func tokenMatchesRejectsEmptyExpected() {
        // An unset expected token must never accept anything — not even "".
        #expect(!BridgeServer.tokenMatches("x", expected: ""))
        #expect(!BridgeServer.tokenMatches("", expected: ""))
        #expect(!BridgeServer.tokenMatches(nil, expected: ""))
    }

    @Test func tokenMatchesRejectsEmptyPresented() {
        #expect(!BridgeServer.tokenMatches("", expected: Self.T))
    }

    @Test func tokenMatchesRejectsLengthMismatch() {
        #expect(!BridgeServer.tokenMatches(String(Self.T.dropLast()), expected: Self.T))   // 63 vs 64
        #expect(!BridgeServer.tokenMatches(Self.T + "0", expected: Self.T))               // 65 vs 64
        #expect(!BridgeServer.tokenMatches(Self.T, expected: String(Self.T.dropLast())))
    }

    @Test func tokenMatchesRejectsSingleByteDifference() {
        var last = Array(Self.T)
        last[last.count - 1] = "0"                       // T ends in "f"
        #expect(!BridgeServer.tokenMatches(String(last), expected: Self.T))

        var first = Array(Self.T)
        first[0] = "1"                                   // T starts with "0"
        #expect(!BridgeServer.tokenMatches(String(first), expected: Self.T))

        var middle = Array(Self.T)
        middle[31] = "0"                                 // index 31 is "f"
        #expect(!BridgeServer.tokenMatches(String(middle), expected: Self.T))
    }

    @Test func tokenMatchesIsCaseSensitive() {
        // The extension lowercases before storing; the app must not "help".
        #expect(!BridgeServer.tokenMatches(Self.T.uppercased(), expected: Self.T))
        #expect(!BridgeServer.tokenMatches(Self.T, expected: Self.T.uppercased()))
    }

    @Test func tokenMatchesComparesBytesNotGraphemes() {
        // Same byte length, different bytes — a non-ASCII presented token must
        // not sneak past a byte-wise loop.
        let a = String(repeating: "é", count: 32)        // 64 UTF-8 bytes
        #expect(a.utf8.count == 64)
        #expect(!BridgeServer.tokenMatches(a, expected: Self.T))
    }

    // MARK: bearerToken

    @Test func bearerTokenParsesStandardHeader() {
        let header = "POST /intent HTTP/1.1\r\nAuthorization: Bearer abc\r\nHost: x"
        #expect(BridgeServer.bearerToken(header) == "abc")
    }

    @Test func bearerTokenParsesRealToken() {
        let header = "POST /intent HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: Bearer \(Self.T)\r\nContent-Length: 90"
        #expect(BridgeServer.bearerToken(header) == Self.T)
    }

    @Test func bearerTokenIsCaseInsensitiveAndTrims() {
        #expect(BridgeServer.bearerToken("authorization:   bearer \t abc  ") == "abc")
        #expect(BridgeServer.bearerToken("AUTHORIZATION: BEARER abc") == "abc")
        #expect(BridgeServer.bearerToken("Authorization:Bearer abc") == "abc")      // no space after colon
        #expect(BridgeServer.bearerToken("Authorization: Bearer\tabc") == "abc")    // tab separator
    }

    @Test func bearerTokenWorksWhenHeaderIsNotOnFirstLine() {
        let header = "POST /intent HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nAuthorization: Bearer abc"
        #expect(BridgeServer.bearerToken(header) == "abc")
    }

    @Test func bearerTokenRejectsOtherSchemes() {
        #expect(BridgeServer.bearerToken("Authorization: Basic eHl6") == nil)
        #expect(BridgeServer.bearerToken("Authorization: abc") == nil)            // no scheme
        #expect(BridgeServer.bearerToken("Authorization: Bearer") == nil)         // empty token
        #expect(BridgeServer.bearerToken("Authorization: Bearer   ") == nil)      // whitespace token
        #expect(BridgeServer.bearerToken("Authorization: Bearerabc") == nil)      // scheme glued to token
        #expect(BridgeServer.bearerToken("Authorization:") == nil)
        #expect(BridgeServer.bearerToken("POST /intent HTTP/1.1\r\nHost: x") == nil)   // absent
        #expect(BridgeServer.bearerToken("") == nil)
    }

    @Test func bearerTokenIgnoresLookalikeHeaders() {
        // Only the Authorization header counts; a "Bearer" elsewhere is noise.
        #expect(BridgeServer.bearerToken("X-Authorization: Bearer abc") == nil)
        #expect(BridgeServer.bearerToken("Proxy-Authorization: Bearer abc") == nil)
        #expect(BridgeServer.bearerToken("Cookie: Authorization=Bearer abc") == nil)
    }

    @Test func bearerTokenUsesFirstAuthorizationHeader() {
        let header = "POST /intent HTTP/1.1\r\nAuthorization: Bearer first\r\nAuthorization: Bearer second"
        #expect(BridgeServer.bearerToken(header) == "first")
    }

    @Test func bearerTokenFirstLineWinsEvenWhenNotBearer() {
        // "First Authorization line wins": a non-Bearer first line yields nil
        // rather than falling through to a later Bearer line.
        let header = "POST /intent HTTP/1.1\r\nAuthorization: Basic eHl6\r\nAuthorization: Bearer abc"
        #expect(BridgeServer.bearerToken(header) == nil)
    }

    @Test func bearerTokenReturnsRemainderVerbatim() {
        // Inner whitespace is part of the credential (only the ends are trimmed),
        // so such a value can never match a 64-hex token.
        #expect(BridgeServer.bearerToken("Authorization: Bearer abc def") == "abc def")
        #expect(!BridgeServer.tokenMatches("abc def", expected: Self.T))
    }

    // MARK: gate — order 204 → 405 → 404 → 401 → nil

    @Test func gateOptionsNeedsNoToken() {
        #expect(BridgeServer.gate(method: "OPTIONS", path: "/anything", bearer: nil, expected: Self.T) == 204)
        #expect(BridgeServer.gate(method: "OPTIONS", path: "/intent", bearer: nil, expected: Self.T) == 204)
        #expect(BridgeServer.gate(method: "OPTIONS", path: "/intent", bearer: "wrong", expected: Self.T) == 204)
        #expect(BridgeServer.gate(method: "OPTIONS", path: "/intent", bearer: nil, expected: "") == 204)
    }

    @Test func gateRejectsNonPost() {
        // A good token does not rescue a wrong method.
        #expect(BridgeServer.gate(method: "GET", path: "/intent", bearer: Self.T, expected: Self.T) == 405)
        #expect(BridgeServer.gate(method: "PUT", path: "/intent", bearer: Self.T, expected: Self.T) == 405)
        #expect(BridgeServer.gate(method: "DELETE", path: "/intent", bearer: nil, expected: Self.T) == 405)
        #expect(BridgeServer.gate(method: "", path: "/intent", bearer: Self.T, expected: Self.T) == 405)
        #expect(BridgeServer.gate(method: "post", path: "/intent", bearer: Self.T, expected: Self.T) == 405)  // case-sensitive method
    }

    @Test func gateRejectsWrongPathBeforeAuth() {
        // Path is decided before the token, so a probe cannot learn whether
        // auth exists from the status.
        #expect(BridgeServer.gate(method: "POST", path: "/other", bearer: Self.T, expected: Self.T) == 404)
        #expect(BridgeServer.gate(method: "POST", path: "/other", bearer: nil, expected: Self.T) == 404)
        #expect(BridgeServer.gate(method: "POST", path: "/intent?x=1", bearer: Self.T, expected: Self.T) == 404)
        #expect(BridgeServer.gate(method: "POST", path: "/intent/", bearer: Self.T, expected: Self.T) == 404)
        #expect(BridgeServer.gate(method: "POST", path: "", bearer: Self.T, expected: Self.T) == 404)
    }

    @Test func gateRejectsBadToken() {
        #expect(BridgeServer.gate(method: "POST", path: "/intent",
                                  bearer: String(repeating: "x", count: 64), expected: Self.T) == 401)
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: nil, expected: Self.T) == 401)
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: "", expected: Self.T) == 401)
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: Self.T.uppercased(), expected: Self.T) == 401)
        // An unset expected token never lets anything in — not even an empty credential.
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: "", expected: "") == 401)
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: nil, expected: "") == 401)
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: "x", expected: "") == 401)
    }

    @Test func gatePassesGoodToken() {
        #expect(BridgeServer.gate(method: "POST", path: "/intent", bearer: Self.T, expected: Self.T) == nil)
    }

    @Test func gateEndToEndFromRawHeader() {
        // The way handle() feeds it: bearerToken(header) → gate.
        let good = "POST /intent HTTP/1.1\r\nAuthorization: Bearer \(Self.T)\r\nContent-Length: 0"
        #expect(BridgeServer.gate(method: BridgeServer.method(good), path: BridgeServer.path(good),
                                  bearer: BridgeServer.bearerToken(good), expected: Self.T) == nil)

        let missing = "POST /intent HTTP/1.1\r\nContent-Length: 0"
        #expect(BridgeServer.gate(method: BridgeServer.method(missing), path: BridgeServer.path(missing),
                                  bearer: BridgeServer.bearerToken(missing), expected: Self.T) == 401)

        let basic = "POST /intent HTTP/1.1\r\nAuthorization: Basic eHl6"
        #expect(BridgeServer.bearerToken(basic) == nil)      // → logged as reason:"missing"
        #expect(BridgeServer.gate(method: "POST", path: "/intent",
                                  bearer: BridgeServer.bearerToken(basic), expected: Self.T) == 401)

        let preflight = "OPTIONS /intent HTTP/1.1\r\nOrigin: https://evil.example"
        #expect(BridgeServer.gate(method: BridgeServer.method(preflight), path: BridgeServer.path(preflight),
                                  bearer: nil, expected: Self.T) == 204)
    }

    // MARK: responseHead — the header contract (no CORS, Connection: close, 401 challenge)

    @Test func responseHeadStatusLineAndReasons() {
        #expect(BridgeServer.responseHead(status: 401).hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(BridgeServer.responseHead(status: 200).hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(BridgeServer.responseHead(status: 204).hasPrefix("HTTP/1.1 204 No Content\r\n"))
        #expect(BridgeServer.responseHead(status: 429).hasPrefix("HTTP/1.1 429 Too Many Requests\r\n"))
        for (status, reason) in BridgeServer.reasons {
            #expect(BridgeServer.responseHead(status: status).hasPrefix("HTTP/1.1 \(status) \(reason)\r\n"))
        }
    }

    @Test func responseHeadNeverCarriesCORSHeaders() {
        // A web page must not be able to read or preflight into the bridge —
        // re-adding `Access-Control-Allow-Origin: *` "for local debugging" fails here.
        for status in BridgeServer.reasons.keys {
            let head = BridgeServer.responseHead(status: status)
            #expect(!head.contains("Access-Control"), "status \(status) leaks a CORS header")
            #expect(!head.lowercased().contains("access-control"), "status \(status) leaks a CORS header")
        }
    }

    @Test func responseHeadClosesEveryConnectionWithEmptyBody() {
        for status in BridgeServer.reasons.keys {
            let head = BridgeServer.responseHead(status: status)
            #expect(head.contains("Connection: close\r\n"), "status \(status)")
            #expect(head.contains("Content-Length: 0\r\n"), "status \(status)")
            #expect(head.hasSuffix("\r\n\r\n"), "status \(status) must end the head with a blank line")
        }
    }

    @Test func responseHeadChallengesOnlyOn401() {
        let challenge = "WWW-Authenticate: Bearer realm=\"spending-angel\"\r\n"
        #expect(BridgeServer.responseHead(status: 401).contains(challenge))
        for status in BridgeServer.reasons.keys where status != 401 {
            #expect(!BridgeServer.responseHead(status: status).contains("WWW-Authenticate"), "status \(status)")
        }
    }

    @Test func responseHeadUnknownStatusHasEmptyReason() {
        // Not reachable from handle(), but pins that an unmapped code degrades
        // to an empty reason phrase rather than crashing.
        #expect(BridgeServer.responseHead(status: 418).hasPrefix("HTTP/1.1 418 \r\n"))
    }

    // MARK: headerValue — the single header scan contentLength/bearerToken share

    @Test func headerValueFirstMatchWinsAndIsTrimmed() {
        let header = "POST /intent HTTP/1.1\r\nX-A:  one \r\nx-a: two"
        #expect(BridgeServer.headerValue(header, named: "x-a") == "one")
        #expect(BridgeServer.headerValue(header, named: "x-b") == nil)
        #expect(BridgeServer.headerValue("", named: "x-a") == nil)
    }

    @Test func headerValueSkipsEmptyValueLines() {
        // "Name:" with nothing after the colon has no value; a later line still counts.
        #expect(BridgeServer.headerValue("X-A:\r\nX-A: later", named: "x-a") == "later")
        #expect(BridgeServer.headerValue("X-A:", named: "x-a") == nil)
    }

    // MARK: Store token generation

    private func isLowerHex64(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { "0123456789abcdef".contains($0) }
    }

    @Test func generateBridgeTokenFormat() {
        let t = Store.generateBridgeToken()
        #expect(t.count == 64)
        #expect(t.utf8.count == 64)
        #expect(isLowerHex64(t))
        #expect(Store.isValidBridgeToken(t))
    }

    @Test func generateBridgeTokenIsUnique() {
        #expect(Store.generateBridgeToken() != Store.generateBridgeToken())
        let many = (0..<64).map { _ in Store.generateBridgeToken() }
        #expect(Set(many).count == many.count)
    }

    @Test func generatedTokensAlwaysMatchThemselvesAndNotEachOther() {
        let a = Store.generateBridgeToken()
        let b = Store.generateBridgeToken()
        #expect(BridgeServer.tokenMatches(a, expected: a))
        #expect(!BridgeServer.tokenMatches(a, expected: b))
    }

    @Test func isValidBridgeTokenAcceptsOnlyLowerHex64() {
        #expect(Store.isValidBridgeToken(Self.T))
        #expect(Store.isValidBridgeToken(String(repeating: "0", count: 64)))
        #expect(Store.isValidBridgeToken(String(repeating: "f", count: 64)))
        #expect(!Store.isValidBridgeToken(""))
        #expect(!Store.isValidBridgeToken(String(Self.T.dropLast())))              // 63
        #expect(!Store.isValidBridgeToken(Self.T + "a"))                           // 65
        #expect(!Store.isValidBridgeToken(Self.T.uppercased()))                    // upper-case hex
        #expect(!Store.isValidBridgeToken(String(repeating: "g", count: 64)))      // non-hex
        #expect(!Store.isValidBridgeToken(" " + String(Self.T.dropFirst())))       // whitespace inside length
        #expect(!Store.isValidBridgeToken(String(repeating: "é", count: 32)))      // 64 bytes, not hex
        #expect(!Store.isValidBridgeToken(String(repeating: "é", count: 64)))      // 64 chars, 128 bytes
    }
}
