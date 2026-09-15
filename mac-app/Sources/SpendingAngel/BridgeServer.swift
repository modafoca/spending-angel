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
/// the app generated and shows under PAIR SENSOR in the dropdown. Anything
/// else gets `401` before the body is even decoded, and no CORS headers are
/// sent on any response, so a web page can neither call the bridge nor read
/// its answer. The expected token is read per request (injected closure) so a
/// regeneration in the dropdown takes effect immediately.
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
    /// Called when the port is already taken — i.e. another instance is running.
    var onAddressInUse: (() -> Void)?
    private var lastAccepted: Date?

    init(expectedToken: @escaping () -> String, onIntent: @escaping (Intent) -> Void) {
        self.expectedToken = expectedToken
        self.onIntent = onIntent
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
                Log.error("bridge.bad_request", "headers exceed \(Self.maxHeaderBytes) bytes")
                self.respond(conn, status: 431, timeout: timeout); return
            }

            if let sep = sep {
                let header = String(decoding: buf.subdata(in: buf.startIndex..<sep.lowerBound), as: UTF8.self)
                guard let needed = Self.contentLength(header) else {
                    Log.error("bridge.bad_request", "unparseable Content-Length")
                    self.respond(conn, status: 400, timeout: timeout); return
                }
                guard needed <= Self.maxBodyBytes else {
                    Log.error("bridge.bad_request", "body too large (\(needed) bytes)")
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
                Log.info("bridge.unauthorized", "rejected", ["reason": bearer == nil ? "missing" : "mismatch"])
            }
            respond(conn, status: status, timeout: timeout); return
        }

        guard let intent = try? JSONDecoder().decode(Intent.self, from: body) else {
            Log.error("bridge.bad_payload", "POST /intent body is not a valid intent")
            respond(conn, status: 400, timeout: timeout); return
        }
        if let problem = Self.validate(intent) {
            Log.error("bridge.invalid_intent", problem, ["intent_id": Log.clip(intent.id ?? "")])
            respond(conn, status: 400, timeout: timeout); return
        }

        // Only reached for authenticated, valid intents — lastAccepted never moves for a 401/400.
        let now = Date()
        if let last = lastAccepted, now.timeIntervalSince(last) < Self.minCatchInterval {
            Log.info("bridge.intent_throttled", "dropped — last catch \(Int(now.timeIntervalSince(last)))s ago",
                     ["intent_id": Log.clip(intent.id ?? ""), "hostname": Log.clip(intent.hostname)])
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

    /// Constant-time comparison. false when `presented` is nil, when `expected`
    /// is empty (never accept an unset token), or when lengths differ (token
    /// length is public); otherwise ORs the XOR of every byte pair — no early
    /// exit inside the loop — and returns diff == 0.
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
    /// into the problem text are clipped so the log line stays small.
    static func validate(_ i: Intent) -> String? {
        guard i.type == "checkout_intent" else { return "unknown type \"\(Log.clip(i.type, max: 64))\"" }
        guard allowedTriggers.contains(i.trigger) else {
            return "unknown trigger \"\(Log.clip(i.trigger, max: 64))\""
        }
        if let id = i.id, id.utf8.count > maxIDLength { return "bad id" }
        let host = i.hostname.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, host.utf8.count <= 253 else { return "bad hostname" }
        return nil
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
