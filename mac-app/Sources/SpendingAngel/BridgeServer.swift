import Foundation
import Network

/// A tiny localhost HTTP server. The browser sensor POSTs checkout intents to
/// http://127.0.0.1:<port>/intent; we decode, validate, and hand them up.
/// One-way and fire-and-forget — no WebSocket needed for v0. (Native Messaging
/// is the ship path; see PRM Q1.) Bound to loopback only, so no firewall prompt
/// and nothing off-machine can reach it.
///
/// Hardened for M-F1: anything on this Mac can reach the port, so every request
/// is treated as untrusted — header/body size caps, a connection timeout,
/// strict intent validation, real HTTP status codes, and a catch throttle so a
/// buggy (or hostile) page can't spam the overlay.
///
/// The port doubles as a single-instance lock: if it's already bound, another
/// copy of the app is running, and `onAddressInUse` fires so we can quit.
final class BridgeServer {
    static let port: UInt16 = 17865
    static let maxHeaderBytes = 8_192
    static let maxBodyBytes = 1_000_000        // a real intent is < 300 bytes
    static let connectionTimeout: TimeInterval = 10
    /// Minimum gap between accepted intents. The overlay holds ~4–8s per catch;
    /// anything faster is a repeat click or a spammy page, not a new decision.
    static let minCatchInterval: TimeInterval = 8

    private var listener: NWListener?
    private let onIntent: (Intent) -> Void
    /// Called when the port is already taken — i.e. another instance is running.
    var onAddressInUse: (() -> Void)?
    private var lastAccepted: Date?

    init(onIntent: @escaping (Intent) -> Void) {
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

            if let sep = buf.range(of: Data("\r\n\r\n".utf8)) {
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
                                body: Data(body.prefix(needed)), conn: conn, timeout: timeout)
                    return
                }
            } else if buf.count > Self.maxHeaderBytes {
                Log.error("bridge.bad_request", "headers exceed \(Self.maxHeaderBytes) bytes")
                self.respond(conn, status: 431, timeout: timeout); return
            }

            if isComplete || error != nil { timeout.cancel(); conn.cancel(); return }
            self.read(conn, buffer: buf, timeout: timeout)
        }
    }

    private func handle(method: String, path: String, body: Data, conn: NWConnection, timeout: DispatchWorkItem) {
        if method == "OPTIONS" { respond(conn, status: 204, timeout: timeout); return }
        guard method == "POST" else { respond(conn, status: 405, timeout: timeout); return }
        guard path == "/intent" else { respond(conn, status: 404, timeout: timeout); return }

        guard let intent = try? JSONDecoder().decode(Intent.self, from: body) else {
            Log.error("bridge.bad_payload", "POST /intent body is not a valid intent")
            respond(conn, status: 400, timeout: timeout); return
        }
        if let problem = Self.validate(intent) {
            Log.error("bridge.invalid_intent", problem, ["intent_id": intent.id ?? ""])
            respond(conn, status: 400, timeout: timeout); return
        }

        let now = Date()
        if let last = lastAccepted, now.timeIntervalSince(last) < Self.minCatchInterval {
            Log.info("bridge.intent_throttled", "dropped — last catch \(Int(now.timeIntervalSince(last)))s ago",
                     ["intent_id": intent.id ?? "", "hostname": intent.hostname])
            respond(conn, status: 429, timeout: timeout); return
        }
        lastAccepted = now

        Log.info("bridge.intent_received", intent.hostname,
                 ["intent_id": intent.id ?? "", "trigger": intent.trigger])
        onIntent(intent)
        respond(conn, status: 200, timeout: timeout)
    }

    private func respond(_ conn: NWConnection, status: Int, timeout: DispatchWorkItem) {
        timeout.cancel()
        let reasons = [200: "OK", 204: "No Content", 400: "Bad Request", 404: "Not Found",
                       405: "Method Not Allowed", 413: "Payload Too Large",
                       429: "Too Many Requests", 431: "Request Header Fields Too Large"]
        let resp = "HTTP/1.1 \(status) \(reasons[status] ?? "")\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Access-Control-Allow-Headers: Content-Type\r\n"
            + "Content-Length: 0\r\n\r\n"
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
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

    /// 0 when the header is absent (no body), nil when present but malformed.
    static func contentLength(_ header: String) -> Int? {
        for line in header.components(separatedBy: "\r\n") {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                guard let n = Int(kv[1].trimmingCharacters(in: .whitespaces)), n >= 0 else { return nil }
                return n
            }
        }
        return 0
    }

    /// Returns a problem description, or nil if the intent is acceptable.
    static func validate(_ i: Intent) -> String? {
        guard i.type == "checkout_intent" else { return "unknown type \"\(i.type)\"" }
        guard ["click", "load", "simulated"].contains(i.trigger) else { return "unknown trigger \"\(i.trigger)\"" }
        let host = i.hostname.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, host.count <= 253 else { return "bad hostname" }
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
