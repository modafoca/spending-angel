import Foundation
import os

/// Structured, local-first logging (M-F1 — the house standard).
///
/// Every event is one JSON line in `~/Library/Logs/SpendingAngel/`
/// (`spending-angel-YYYY-MM-DD.jsonl`, files older than 14 days pruned at
/// launch), mirrored to os.log (subsystem `net.modafoca.spendingangel`) so
/// Console.app works during dev. Logs NEVER leave the machine — "nothing
/// leaves your Mac" is the product.
///
/// Levels: `debug` (dev builds only), `info` (normal ops), `error` (broken).
/// `install_id` is a stable anonymous id for this install; `intent_id` (passed
/// in `fields`) traces one catch end-to-end from the extension to the overlay.
final class Log {
    static let shared = Log()
    static let subsystem = "net.modafoca.spendingangel"
    static let retentionDays = 14

    /// Stable anonymous id for this install — stands in for a user id.
    static let installID: String = {
        let key = "installID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    enum Level: String { case debug, info, error }

    static func debug(_ event: String, _ msg: String, _ fields: [String: String] = [:]) {
        shared.write(.debug, event, msg, fields)
    }
    static func info(_ event: String, _ msg: String, _ fields: [String: String] = [:]) {
        shared.write(.info, event, msg, fields)
    }
    static func error(_ event: String, _ msg: String, _ fields: [String: String] = [:]) {
        shared.write(.error, event, msg, fields)
    }

    private let osLog = Logger(subsystem: Log.subsystem, category: "app")
    private let queue = DispatchQueue(label: Log.subsystem + ".log", qos: .utility)
    private let dir: URL
    private let iso = ISO8601DateFormatter()
    private let day: DateFormatter

    init(directory: URL? = nil) {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"

        dir = directory ?? FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/SpendingAngel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        queue.async { [weak self] in self?.prune() }
    }

    func write(_ level: Level, _ event: String, _ msg: String, _ fields: [String: String] = [:]) {
        #if !DEBUG
        if level == .debug { return }
        #endif

        // Mirror to os.log so Console.app / `log stream` see it live.
        let console = "\(event) — \(msg)"
        switch level {
        case .debug: osLog.debug("\(console, privacy: .public)")
        case .info: osLog.info("\(console, privacy: .public)")
        case .error: osLog.error("\(console, privacy: .public)")
        }

        var entry: [String: Any] = [
            "ts": iso.string(from: Date()),
            "level": level.rawValue,
            "event": event,
            "msg": msg,
            "install_id": Log.installID,
        ]
        for (k, v) in fields { entry[k] = v }

        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let file = dir.appendingPathComponent("spending-angel-\(day.string(from: Date())).jsonl")
        queue.async {
            var line = data
            line.append(Data("\n".utf8))
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: file)
            }
        }
    }

    /// Deletes log files older than `retentionDays`. Filenames carry the date,
    /// so this needs no metadata reads.
    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -Log.retentionDays, to: Date()) else { return }
        let cutoff = "spending-angel-\(day.string(from: cutoffDate)).jsonl"
        for f in files where f.lastPathComponent.hasPrefix("spending-angel-") && f.lastPathComponent < cutoff {
            try? FileManager.default.removeItem(at: f)
        }
    }
}
