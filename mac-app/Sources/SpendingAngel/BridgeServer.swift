import Foundation
import Network

/// A tiny localhost HTTP server. The browser sensor POSTs checkout intents to
/// http://127.0.0.1:<port>/intent; we decode and hand them up. One-way and
/// fire-and-forget — no WebSocket needed for v0. (Native Messaging is the ship
/// path; see PRM Q1.) Bound to loopback only, so no firewall prompt and nothing
/// off-machine can reach it.
final class BridgeServer {
    static let port: UInt16 = 17865

    private var listener: NWListener?
    private let onIntent: (Intent) -> Void

    init(onIntent: @escaping (Intent) -> Void) {
        self.onIntent = onIntent
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: BridgeServer.port)!
            )
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.stateUpdateHandler = { state in
                if case .failed(let e) = state { print("[bridge] listener failed: \(e)") }
            }
            listener.start(queue: .main)
            self.listener = listener
            print("[bridge] listening on http://127.0.0.1:\(BridgeServer.port)")
        } catch {
            print("[bridge] could not start: \(error)")
        }
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        read(conn, buffer: Data())
    }

    private func read(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }

            if let sep = buf.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buf.subdata(in: buf.startIndex..<sep.lowerBound), as: UTF8.self)
                let needed = Self.contentLength(header)
                let body = buf.subdata(in: sep.upperBound..<buf.endIndex)
                if body.count >= needed {
                    self.handle(method: Self.method(header), body: Data(body.prefix(needed)), conn: conn)
                    return
                }
            }
            if isComplete || error != nil { conn.cancel(); return }
            self.read(conn, buffer: buf)
        }
    }

    private func handle(method: String, body: Data, conn: NWConnection) {
        if method == "POST", let intent = try? JSONDecoder().decode(Intent.self, from: body) {
            onIntent(intent)
        }
        let resp = "HTTP/1.1 200 OK\r\n"
            + "Access-Control-Allow-Origin: *\r\n"
            + "Access-Control-Allow-Headers: Content-Type\r\n"
            + "Content-Length: 0\r\n\r\n"
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    static func method(_ header: String) -> String {
        let firstLine = header.components(separatedBy: "\r\n").first ?? ""
        return firstLine.split(separator: " ").first.map(String.init) ?? ""
    }

    static func contentLength(_ header: String) -> Int {
        for line in header.components(separatedBy: "\r\n") {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                return Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }
}

/// The intent payload the sensor sends. Mirrors the JS shape exactly.
struct Intent: Codable {
    let type: String
    let trigger: String
    let hostname: String
    let ts: Double
}
