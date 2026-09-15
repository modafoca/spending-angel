import Foundation
import Network

/// A tiny localhost HTTP server. The browser sensor POSTs checkout intents to
/// http://127.0.0.1:<port>/intent; we decode, validate, and hand them up.
/// One-way and fire-and-forget — no WebSocket needed for v0. Loopback + bearer
/// token is the chosen path (no Native Messaging host manifest to install).
/// Bound to loopback only, so no firewall prompt and nothing off-machine can
/// reach it.
///
/// Hardened for M-F1: anything on this Mac can reach the port, so every request
/// is treated as untrusted — header/body size caps, a connection timeout,
/// strict intent validation, real HTTP status codes, and a catch throttle so a
/// buggy (or hostile) page can't spam the overlay.
///
/// Paired (audit 2026-09, NATIVE-01): the sensor proves it is *our* sensor by
/// sending `Authorization: Bearer <token>`, where the token is the 64-hex value
/// the app generated and shows under PAIR SENSOR in the dropdown. The request
/// is still framed first (header cap, Content-Length, body cap — 431/400/413),
/// but nothing from the body is decoded or logged until the token has matched:
/// a wrong or missing token gets `401` before decode. A web page *can* reach
/// this port with a simple POST (no preflight), but it gets `401`, cannot read
/// the answer (no CORS headers on any response), cannot attach `Authorization`
/// (a non-safelisted header forces a preflight this server never satisfies),
/// and never saw the token in the first place. The expected token is read per
/// request (injected closure) so a regeneration in the dropdown takes effect
/// immediately.
///
/// Rejection lines (401 / 400 / 413 / 431 / 429) are rate-limited per key —
/// one line per second, with `suppressed: "<n>"` + `suppressed_since: "<ts>"`
/// on the first line after a busy window (review 2026-09, S-04) — so a local
/// loop cannot grow the day's log by one line per connection. The key is the
/// event name, except `bridge.unauthorized`, which is keyed per reason so a
/// wrong-token probe is never hidden behind a no-token flood. Status codes are
/// never throttled.
///
/// Evaluation order (status codes): 431 header cap → 400 bad Content-Length →
/// 413 body cap (all while framing) → 204 OPTIONS → 405 → 404 → 401 (the pure
/// `gate`) → 400 decode/validate → 429 throttle → 200.
///
/// The port doubles as a single-instance lock: if it's already bound, another
/// copy of the app is running, and `onAddressInUse` fires so we can quit.
final class BridgeServer {
    static let port: UInt16 = 17865
    static let maxHeaderBytes = 8_192
    static let maxBodyBytes = 1_000_000        // a real intent is < 300 bytes
    static let maxIDLength = 128               // UTF-8 bytes; a UUID is 36
    static let maxHostnameLength = 253         // UTF-8 bytes of the RAW value, before trimming (RFC 1035 limit)
    static let allowedTriggers: Set<String> = ["click", "load", "simulated"]
    static let connectionTimeout: TimeInterval = 10
    /// Minimum gap between accepted intents. Clips run up to ~12 s so a catch
    /// can outlive this gap — that overlap is handled by the overlay's admission
    /// gate (CatchRunner), not here. Anything faster than this is a repeat click
    /// or a spammy page, not a new decision.
    static let minCatchInterval: TimeInterval = 8
    /// Reason phrases for every status this server can emit (also the table the
    /// header-contract tests iterate over).
    static let reasons: [Int: String] = [
        200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
        404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large",
        429: "Too Many Requests", 431: "Request Header Fields Too Large",
    ]

    private var listener: NWListener?
    private let onIntent: (Intent) -> Void
    /// The pairing token the sensor must present. Read per request so the
    /// dropdown's "regenerate" needs no restart and tests need no Store.
    private let expectedToken: () -> String
    /// Rejection lines share one log throttle so a local loop can't grow the
    /// log by one line per connection. Distinct from the catch throttle
    /// (`minCatchInterval`, the 429 path) — this one only decides whether a
    /// line is written. Injected so a test could pin the wiring with a fake
    /// clock; production uses the default. Not a function type, so the
    /// existing trailing-closure call `BridgeServer(expectedToken:) { intent in … }`
    /// is unaffected.
    private let logThrottle: LogThrottle
    /// Called when the port is already taken — i.e. another instance is running.
    var onAddressInUse: (() -> Void)?
    private var lastAccepted: Date?

    init(expectedToken: @escaping () -> String,
         logThrottle: LogThrottle = LogThrottle(),
         onIntent: @escaping (Intent) -> Void) {
        self.expectedToken = expectedToken
        self.logThrottle = logThrottle
        self.onIntent = onIntent
    }

    /// The one door for rejection lines. `sink` is `Log.info` or `Log.error` —
    /// passed as a value so this file keeps compiling against a minimal `Log`.
    /// `key` defaults to the event name; the 401 site passes the event plus its
    /// public reason word so a mismatch is never hidden behind a missing-token
    /// flood. Never given token or body bytes: callers pass only what they log
    /// today, and the key is built from constants and the reason word only.
    private func logRejected(_ event: String, _ msg: String, _ fields: [String: String] = [:],
                             key: String? = nil,
                             via sink: (String, String, [String: String]) -> Void) {
        guard let extra = logThrottle.admit(key ?? event) else { return }
        sink(event, msg, fields.merging(extra) { _, new in new })
    }

    func start() {
        guard let port = NWEndpoint.Port(rawValue: BridgeServer.port) else {
            Log.error("bridge.bad_port", "\(BridgeServer.port) is not a valid TCP port")
            return
        }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Log.info("bridge.listening", "http://127.0.0.1:\(BridgeServer.port)")
                case .failed(let error):
                    if case .posix(let code) = error, code == .EADDRINUSE {
                        Log.info("bridge.port_in_use", "another instance owns port \(BridgeServer.port)")
                        self?.onAddressInUse?()
                    } else {
                        Log.error("bridge.listener_failed", "\(error)")
                    }
                default:
                    break
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            Log.error("bridge.start_failed", "\(error)")
        }
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        // Hard deadline: a client that connects and stalls can't hold us open.
        let timeout = DispatchWorkItem { [weak conn] in conn?.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: timeout)
        read(conn, buffer: Data(), timeout: timeout)
    }

    private func read(_ conn: NWConnection, buffer: Data, timeout: DispatchWorkItem) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { timeout.cancel(); conn.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }

            // The header cap applies whether or not the delimiter has arrived:
            // a 12 KB header that happens to include "\r\n\r\n" in one read used
            // to slip through because only the no-delimiter branch checked.
            let sep = buf.range(of: Data("\r\n\r\n".utf8))
            if Self.headerExceedsCap(buf, delimiter: sep) {
                self.logRejected("bridge.bad_request", "headers exceed \(Self.maxHeaderBytes) bytes", via: Log.error)
                self.respond(conn, status: 431, timeout: timeout); return
            }

            if let sep = sep {
                let header = String(decoding: buf.subdata(in: buf.startIndex..<sep.lowerBound), as: UTF8.self)
                guard let needed = Self.contentLength(header) else {
                    self.logRejected("bridge.bad_request", "unparseable Content-Length", via: Log.error)
                    self.respond(conn, status: 400, timeout: timeout); return
                }
                guard needed <= Self.maxBodyBytes else {
                    self.logRejected("bridge.bad_request", "body too large (\(needed) bytes)", via: Log.error)
                    self.respond(conn, status: 413, timeout: timeout); return
                }
                let body = buf.subdata(in: sep.upperBound..<buf.endIndex)
                if body.count >= needed {
                    self.handle(method: Self.method(header), path: Self.path(header),
                                bearer: Self.bearerToken(header),
                                body: Data(body.prefix(needed)), conn: conn, timeout: timeout)
                    return
                }
            }

            if isComplete || error != nil { timeout.cancel(); conn.cancel(); return }
            self.read(conn, buffer: buf, timeout: timeout)
        }
    }

    private func handle(method: String, path: String, bearer: String?, body: Data,
                        conn: NWConnection, timeout: DispatchWorkItem) {
        // OPTIONS / method / path / token — decided before anything from the
        // body is touched, so an unpaired caller learns nothing and logs nothing.
        if let status = Self.gate(method: method, path: path, bearer: bearer, expected: expectedToken()) {
            if status == 401 {
                // Never log the presented credential — only whether one was there.
                // Keyed per reason (not per event) so the first wrong-token probe
                // is written even inside a no-token flood's window.
                let reason = bearer == nil ? "missing" : "mismatch"
                logRejected("bridge.unauthorized", "rejected", ["reason": reason],
                            key: "bridge.unauthorized/" + reason, via: Log.info)
            }
            respond(conn, status: status, timeout: timeout); return
        }

        guard let intent = try? JSONDecoder().decode(Intent.self, from: body) else {
            logRejected("bridge.bad_payload", "POST /intent body is not a valid intent", via: Log.error)
            respond(conn, status: 400, timeout: timeout); return
        }
        if let problem = Self.validate(intent) {
            logRejected("bridge.invalid_intent", problem, ["intent_id": Log.clip(intent.id ?? "")], via: Log.error)
            respond(conn, status: 400, timeout: timeout); return
        }

        // Only reached for authenticated, valid intents — lastAccepted never moves for a 401/400.
        let now = Date()
        if let last = lastAccepted, now.timeIntervalSince(last) < Self.minCatchInterval {
            logRejected("bridge.intent_throttled", "dropped — last catch \(Int(now.timeIntervalSince(last)))s ago",
                        ["intent_id": Log.clip(intent.id ?? ""), "hostname": Log.clip(intent.hostname)], via: Log.info)
            respond(conn, status: 429, timeout: timeout); return
        }
        lastAccepted = now

        Log.info("bridge.intent_received", Log.clip(intent.hostname),
                 ["intent_id": Log.clip(intent.id ?? ""), "trigger": intent.trigger])
        onIntent(intent)
        respond(conn, status: 200, timeout: timeout)
    }

    /// Empty-body response: writes `responseHead(status:)` and closes.
    private func respond(_ conn: NWConnection, status: Int, timeout: DispatchWorkItem) {
        timeout.cancel()
        conn.send(content: Data(Self.responseHead(status: status).utf8),
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    /// The exact bytes of an empty-body response head, pure so the header
    /// contract is unit-tested and not only curl-checked. Deliberately no
    /// `Access-Control-*` headers: the extension's service worker is exempt from
    /// CORS via host_permissions, and a web page must not be able to read (or
    /// preflight into) this server. `Connection: close` on every status; the
    /// `WWW-Authenticate` challenge only on 401.
    static func responseHead(status: Int) -> String {
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "")\r\n"
            + "Content-Length: 0\r\n"
            + "Connection: close\r\n"
        if status == 401 {
            head += "WWW-Authenticate: Bearer realm=\"spending-angel\"\r\n"
        }
        head += "\r\n"
        return head
    }

    // MARK: - Parsing + validation (static, unit-tested)

    static func method(_ header: String) -> String {
        let firstLine = header.components(separatedBy: "\r\n").first ?? ""
        return firstLine.split(separator: " ").first.map(String.init) ?? ""
    }

    static func path(_ header: String) -> String {
        let firstLine = header.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : ""
    }

    /// The trimmed value of the FIRST header line named `name` (lower-case), or
    /// nil when no such line exists. A line with nothing after the colon has no
    /// value and is skipped, so a later line of the same name can still match.
    /// The single header scan `contentLength` and `bearerToken` share.
    static func headerValue(_ header: String, named name: String) -> String? {
        for line in header.components(separatedBy: "\r\n") {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2, kv[0].lowercased().trimmingCharacters(in: .whitespaces) == name else { continue }
            return kv[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// 0 when the header is absent (no body), nil when present but malformed.
    static func contentLength(_ header: String) -> Int? {
        guard let value = headerValue(header, named: "content-length") else { return 0 }
        guard let n = Int(value), n >= 0 else { return nil }
        return n
    }

    /// Pure framing check used by read() in BOTH branches: with the delimiter in
    /// hand, the header is the bytes before it; without it, the whole buffer is
    /// header-so-far. Either way it must fit maxHeaderBytes. The offset is taken
    /// relative to the slice's own startIndex — a `Data` slice need not start at 0.
    static func headerExceedsCap(_ buf: Data, delimiter: Range<Data.Index>?) -> Bool {
        let headerBytes = delimiter.map { $0.lowerBound - buf.startIndex } ?? buf.count
        return headerBytes > maxHeaderBytes
    }

    /// The pre-body decision, in this exact order:
    /// OPTIONS → 204 · not POST → 405 · path ≠ /intent → 404 ·
    /// !tokenMatches(bearer, expected) → 401 · otherwise nil (proceed to decode).
    /// Pure so the order is pinned by tests; handle() calls it first. Path is
    /// decided before the token so a probe can't learn from the status whether
    /// auth exists on a given path.
    static func gate(method: String, path: String, bearer: String?, expected: String) -> Int? {
        if method == "OPTIONS" { return 204 }
        guard method == "POST" else { return 405 }
        guard path == "/intent" else { return 404 }
        guard tokenMatches(bearer, expected: expected) else { return 401 }
        return nil
    }

    /// The bearer credential from a raw request header block, or nil when absent /
    /// not a Bearer scheme / empty. Header name and scheme are case-insensitive;
    /// one or more spaces/tabs may separate scheme and token; the token is the
    /// remainder trimmed of whitespace. The first Authorization line wins.
    static func bearerToken(_ header: String) -> String? {
        guard let value = headerValue(header, named: "authorization") else { return nil }
        let parts = value.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
        guard let scheme = parts.first, scheme.lowercased() == "bearer", parts.count == 2 else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    /// Constant-time comparison at the source level: false when `presented` is
    /// nil, when `expected` is empty (never accept an unset token), or when the
    /// lengths differ (token length is public); otherwise ORs the XOR of every
    /// byte pair with no data-dependent early exit in the loop and returns
    /// diff == 0. This is a property of the source, not a guarantee about the
    /// machine code — the optimizer's timing behaviour is not controlled here.
    static func tokenMatches(_ presented: String?, expected: String) -> Bool {
        guard let presented = presented, !expected.isEmpty else { return false }
        let a = Array(presented.utf8)
        let b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in a.indices { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    /// Returns a problem description, or nil if the intent is acceptable. Every
    /// bound is in UTF-8 bytes (`.utf8.count`), never `String.count`: a single
    /// grapheme cluster can carry thousands of combining marks, so a
    /// cluster-based bound is no bound at all. Untrusted strings that make it
    /// into the problem text are clipped so the log line stays small. The
    /// hostname bound applies to the raw value *before* trimming, so padding
    /// cannot smuggle an oversized name past the check.
    static func validate(_ i: Intent) -> String? {
        guard i.type == "checkout_intent" else { return "unknown type \"\(Log.clip(i.type, max: 64))\"" }
        guard allowedTriggers.contains(i.trigger) else {
            return "unknown trigger \"\(Log.clip(i.trigger, max: 64))\""
        }
        if let id = i.id, id.utf8.count > maxIDLength { return "bad id" }
        // Bound the RAW hostname first (review R-03): trimming used to run before
        // the length check, so 20 KB of padding around a short name passed
        // validation and reached every log sink untouched. Then the trimmed
        // value must be non-empty (whitespace-only is not a hostname).
        guard i.hostname.utf8.count <= maxHostnameLength else { return "bad hostname" }
        let host = i.hostname.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return "bad hostname" }
        return nil
    }
}

extension BridgeServer {
    /// Per-key suppression window for rejection lines (review S-04/Q-12).
    /// Anything on this Mac can loop on the port; each rejected request used to
    /// add a line to the day's JSONL with nothing bounding the count. Now each
    /// key emits at most one line per `window`, and the first line after a
    /// busy window carries how many were dropped and when the first drop
    /// happened — a burst followed by hours of silence is still attributable.
    /// Main-queue confined like the rest of the server (no lock). `now` is
    /// injected so the algorithm is unit-tested with a fake clock.
    ///
    /// Lives in this file on purpose: the review fixtures compile
    /// `BridgeServer.swift` standalone against a stub `Log`, so the throttle
    /// must not need another file or anything beyond Foundation.
    final class LogThrottle {
        static let defaultWindow: TimeInterval = 1

        /// One key's state: when its window opened (the clock of the last
        /// emitted line), how many lines were dropped since, and the clock of
        /// the first of those drops.
        private struct Slot { var openedAt: Date; var dropped: Int; var firstDroppedAt: Date? }
        private var slots: [String: Slot] = [:]
        private let window: TimeInterval
        private let now: () -> Date
        /// ISO 8601 at second resolution (`2023-11-14T22:13:20Z`). Unlike the
        /// line's own `ts`, which carries fractional seconds, this drops them,
        /// so a lexical comparison against `ts` is exact only to the second —
        /// enough to bound the burst as `[suppressed_since, ts]` of the
        /// reporting line.
        private let iso = ISO8601DateFormatter()

        init(window: TimeInterval = LogThrottle.defaultWindow, now: @escaping () -> Date = Date.init) {
            self.window = window
            self.now = now
        }

        /// Decide whether a line for `key` may be written now.
        /// - Returns: `nil` → drop it. Otherwise the extra fields to merge into
        ///   the line: `[:]` normally, `["suppressed": "<n>", "suppressed_since":
        ///   "<ISO ts>"]` when `n ≥ 1` lines for this key were dropped since the
        ///   previous emitted line (`suppressed_since` = clock of the FIRST drop).
        ///
        /// The window is `[openedAt, openedAt + window)` and opens at the clock
        /// of an *emitted* line; a line at exactly `openedAt + window` is
        /// emitted, and dropped lines never extend it. A clock that went
        /// backwards (`elapsed < 0`) counts as "window over" — emit, report, and
        /// reopen at the new time — so a wall-clock adjustment can never mute a
        /// key for longer than one real window.
        func admit(_ key: String) -> [String: String]? {
            let t = now()
            guard let slot = slots[key] else {
                slots[key] = Slot(openedAt: t, dropped: 0, firstDroppedAt: nil)   // first line ever: emit
                return [:]
            }
            let elapsed = t.timeIntervalSince(slot.openedAt)
            if elapsed >= 0 && elapsed < window {
                var busy = slot
                busy.dropped += 1
                if busy.firstDroppedAt == nil { busy.firstDroppedAt = t }
                slots[key] = busy
                return nil                                                           // inside the window: drop
            }
            slots[key] = Slot(openedAt: t, dropped: 0, firstDroppedAt: nil)          // reopen at THIS line
            guard slot.dropped > 0, let since = slot.firstDroppedAt else { return [:] }
            return ["suppressed": String(slot.dropped), "suppressed_since": iso.string(from: since)]
        }
    }
}

/// The intent payload the sensor sends. Mirrors the JS shape exactly.
/// `id` is the trace id minted by the extension at detection time (optional so
/// older sensors keep working).
struct Intent: Codable {
    let id: String?
    let type: String
    let trigger: String
    let hostname: String
    let ts: Double
}
