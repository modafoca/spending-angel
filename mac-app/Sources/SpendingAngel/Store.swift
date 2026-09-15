import Foundation
import Combine
import Security

/// The brain's persistent state: goal, active character, on/off, snooze, shuffle,
/// the M-04 stat (monthly catch count + streak), and the bridge pairing token.
/// Backed by UserDefaults. A shared singleton so the SwiftUI scene + the
/// AppDelegate bridge use one instance.
///
/// The pairing token (audit 2026-09, NATIVE-01) is the one secret in the app:
/// 32 random bytes as 64 lowercase hex, minted on first launch, shown under
/// PAIR SENSOR in the dropdown and pasted into the extension's Options page.
/// It is never logged — at most its last 4 chars (`token_tail`).
final class Store: ObservableObject {
    static let shared = Store()

    @Published var goal: String
    @Published var activeCharacter: CharacterID
    @Published var enabled: Bool
    @Published var snoozeUntil: Date?
    @Published var shuffleMode: Bool          // M-07b — "Shake It Up"

    // M-04 — brag stat + streak
    @Published var monthlyCount: Int
    @Published var countMonth: String          // "yyyy-MM"
    @Published var lastCatchDate: Date?

    // NATIVE-01 — bridge pairing token (64 lowercase hex)
    @Published var bridgeToken: String

    private var lastShuffled: CharacterID?     // anti-repeat for shuffle
    private let d = UserDefaults.standard
    private var bag = Set<AnyCancellable>()

    init() {
        goal = d.string(forKey: "goal") ?? ""
        activeCharacter = CharacterID(rawValue: d.string(forKey: "activeCharacter") ?? "") ?? .angel
        enabled = d.object(forKey: "enabled") as? Bool ?? true
        let stored = d.object(forKey: "snoozeUntil") as? Date
        snoozeUntil = (stored.map { $0 > Date() } ?? false) ? stored : nil
        shuffleMode = d.bool(forKey: "shuffleMode")

        // No rollover here: the dropdown derives the displayed count from the
        // current month (`catchCount(inMonthContaining:)`); recordCatch() rolls.
        let storedCount = d.integer(forKey: "monthlyCount")
        monthlyCount = storedCount
        countMonth = Store.restoredCountMonth(stored: d.string(forKey: "countMonth"),
                                             monthlyCount: storedCount, now: Date())
        lastCatchDate = d.object(forKey: "lastCatchDate") as? Date

        // A missing or corrupted token is replaced immediately and persisted
        // before any sink exists, so the bridge never sees an empty expected token.
        let storedToken = d.string(forKey: "bridgeToken")
        if let t = storedToken, Store.isValidBridgeToken(t) {
            bridgeToken = t
        } else {
            let fresh = Store.generateBridgeToken()
            bridgeToken = fresh
            d.set(fresh, forKey: "bridgeToken")
            Log.info("store.token_generated", "new pairing token",
                     ["reason": storedToken == nil ? "first_launch" : "invalid_stored",
                      "token_tail": String(fresh.suffix(4))])
        }

        $goal.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "goal") }.store(in: &bag)
        $activeCharacter.dropFirst().sink { [weak self] in self?.d.set($0.rawValue, forKey: "activeCharacter") }.store(in: &bag)
        $enabled.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "enabled") }.store(in: &bag)
        $snoozeUntil.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "snoozeUntil") }.store(in: &bag)
        $shuffleMode.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "shuffleMode") }.store(in: &bag)
        $monthlyCount.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "monthlyCount") }.store(in: &bag)
        $countMonth.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "countMonth") }.store(in: &bag)
        $lastCatchDate.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "lastCatchDate") }.store(in: &bag)
        $bridgeToken.dropFirst().sink { [weak self] in self?.d.set($0, forKey: "bridgeToken") }.store(in: &bag)
    }

    var isSnoozed: Bool {
        if let u = snoozeUntil, u > Date() { return true }
        return false
    }

    var onDuty: Bool { enabled && !isSnoozed }

    var statusText: String {
        if !enabled { return "Off" }
        if isSnoozed { return "Snoozed" }
        return "On duty"
    }

    func snooze(hours: Double) { snoozeUntil = Date().addingTimeInterval(hours * 3600) }
    func wake() { snoozeUntil = nil }

    /// Which character performs the next catch: the active one normally, or a
    /// random one (no immediate repeat) when Shake It Up is on.
    func nextCatchCharacter() -> CharacterID {
        guard shuffleMode else { return activeCharacter }
        let pool = CharacterID.allCases.filter { $0 != lastShuffled }
        let pick = pool.randomElement() ?? activeCharacter
        lastShuffled = pick
        return pick
    }

    // MARK: - Legacy defaults migration (Round 3)

    /// The bare `swift run` binary persisted under the process-name domain
    /// `SpendingAngel`; the bundled app (`net.modafoca.spendingangel`) starts
    /// from an empty domain, which would cost the goal, character, counter,
    /// token (= re-pair) and `installID`. This copies the old domain over
    /// exactly once. Pure decision + copy, so the matrix is unit-tested with an
    /// isolated suite: no-op (false) when the marker is already set, when there
    /// is nothing to copy, or when the new domain already has an identity
    /// (`installID` or `bridgeToken`) — a fresh install that ran first must not
    /// be overwritten by a stale one. Must run before any `Log` call: `Log.installID`
    /// lazily writes a fresh id into the new domain, which would turn this into
    /// the "already has an identity" no-op.
    @discardableResult
    static func migrateLegacyDefaults(legacy: [String: Any]?, into d: UserDefaults,
                                      marker: String = "migratedFromLegacyDefaults") -> Bool {
        if d.bool(forKey: marker) { return false }
        guard let legacy = legacy, !legacy.isEmpty else { return false }
        if d.object(forKey: "installID") != nil || d.object(forKey: "bridgeToken") != nil { return false }
        for (key, value) in legacy { d.set(value, forKey: key) }
        d.set(true, forKey: marker)
        return true
    }

    // MARK: - Pairing token

    /// 32 CSPRNG bytes → 64 lowercase hex chars. Pure; no UserDefaults.
    /// SecRandomCopyBytes is the source; if it ever fails we log it and fall
    /// back to the system generator (arc4random-backed on Apple platforms)
    /// rather than ship an empty token.
    static func generateBridgeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            Log.error("store.token_random_fallback", "SecRandomCopyBytes failed (\(status)) — using SystemRandomNumberGenerator")
            var g = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &g) }
        }
        let hex: [Character] = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(64)
        for b in bytes {
            out.append(hex[Int(b >> 4)])
            out.append(hex[Int(b & 0x0f)])
        }
        return out
    }

    /// `^[0-9a-f]{64}$` — what the extension stores and the bridge compares.
    static func isValidBridgeToken(_ t: String) -> Bool {
        t.utf8.count == 64 && t.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// Mints a new token, invalidating any sensor paired with the old one. Takes
    /// effect on the very next bridge request (no restart, no grace period).
    func regenerateBridgeToken() {
        bridgeToken = Store.generateBridgeToken()
        Log.info("store.token_regenerated", "sensor must be re-paired", ["token_tail": String(bridgeToken.suffix(4))])
    }

    // MARK: - Stat

    func recordCatch() {
        let now = Date()
        let m = Store.monthKey(now)
        if m != countMonth { monthlyCount = 0 }
        countMonth = m          // always written through — see restoredCountMonth
        monthlyCount += 1
        lastCatchDate = now
        Log.info("store.catch_recorded", "monthly count now \(monthlyCount)", ["month": m])
    }

    /// Which month a restored counter belongs to. Before 2026-09 `countMonth` was
    /// only persisted when a rollover happened inside `recordCatch()`, so an
    /// install that never crossed a month boundary has a counter on disk and no
    /// month for it. Defaulting that to *this* month would resurrect a stale
    /// count as if it were current (the NATIVE-02 symptom by another door), so an
    /// orphaned counter is tagged "unknown": it displays as 0 and the next catch
    /// rolls it over. A zero counter with no month is simply this month.
    static func restoredCountMonth(stored: String?, monthlyCount: Int, now: Date,
                                   calendar: Calendar = .current) -> String {
        if let stored = stored { return stored }
        return monthlyCount > 0 ? "unknown" : monthKey(now, calendar: calendar)
    }

    /// The count to *display*: the stored counter only if it belongs to the
    /// month containing `date`, else 0. `recordCatch()` still rolls the stored
    /// month; this keeps a stale August count from showing in September (NATIVE-02).
    static func catchCount(monthlyCount: Int, countMonth: String,
                           at date: Date, calendar: Calendar = .current) -> Int {
        monthKey(date, calendar: calendar) == countMonth ? monthlyCount : 0
    }

    func catchCount(inMonthContaining date: Date, calendar: Calendar = .current) -> Int {
        Store.catchCount(monthlyCount: monthlyCount, countMonth: countMonth, at: date, calendar: calendar)
    }

    // The calendar parameter makes the date math deterministic and unit-testable;
    // callers get the user's local calendar, which is the semantics we want (a
    // catch at 11pm belongs to that local day/month).

    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        guard let y = c.year, let m = c.month else {
            Log.error("store.month_key_failed", "calendar returned no year/month for \(date)")
            return "unknown"
        }
        return String(format: "%04d-%02d", y, m)
    }

    /// Whole calendar days between two dates, midnight-based — so a catch
    /// yesterday at 11pm reads as "1 day ago" at 7am, not "0 days ago".
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }
}
