import Foundation
import Testing
@testable import SpendingAngel

/// Round 3 — the bare binary's `SpendingAngel` defaults domain is copied into
/// the bundle's domain exactly once. Every case runs against a throwaway
/// `UserDefaults(suiteName:)` that is removed on the way out, so nothing here
/// touches `UserDefaults.standard` or leaves a plist behind.
struct StoreMigrationTests {

    private static let legacy: [String: Any] = [
        "goal": "Tokyo trip", "activeCharacter": "mom", "enabled": false, "shuffleMode": true,
        "monthlyCount": 7, "countMonth": "2026-09",
        "lastCatchDate": Date(timeIntervalSince1970: 1_789_500_000),
        "bridgeToken": String(repeating: "ab", count: 32),
        "installID": "1D0E4C1E-0000-4000-8000-000000000001",
    ]

    private func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let name = "net.modafoca.spendingangel.tests." + UUID().uuidString
        let d = try #require(UserDefaults(suiteName: name))
        defer { d.removePersistentDomain(forName: name) }
        try body(d)
    }

    @Test func copiesEveryKeyOnceAndSetsTheMarker() throws {
        try withSuite { d in
            #expect(Store.migrateLegacyDefaults(legacy: Self.legacy, into: d))
            #expect(d.string(forKey: "goal") == "Tokyo trip")
            #expect(d.string(forKey: "activeCharacter") == "mom")
            #expect(d.object(forKey: "enabled") as? Bool == false)
            #expect(d.bool(forKey: "shuffleMode"))
            #expect(d.integer(forKey: "monthlyCount") == 7)
            #expect(d.string(forKey: "countMonth") == "2026-09")
            #expect(d.object(forKey: "lastCatchDate") as? Date == Date(timeIntervalSince1970: 1_789_500_000))
            #expect(d.string(forKey: "bridgeToken") == String(repeating: "ab", count: 32))
            #expect(d.string(forKey: "installID") == "1D0E4C1E-0000-4000-8000-000000000001")
            #expect(d.bool(forKey: "migratedFromLegacyDefaults"))
            // Next launch: a no-op even though the old domain still exists.
            #expect(!Store.migrateLegacyDefaults(legacy: Self.legacy, into: d))
        }
    }

    @Test func markerAloneBlocksAnyFutureCopy() throws {
        try withSuite { d in
            d.set(true, forKey: "migratedFromLegacyDefaults")
            #expect(!Store.migrateLegacyDefaults(legacy: Self.legacy, into: d))
            #expect(d.object(forKey: "goal") == nil)
        }
    }

    @Test func nothingToCopyIsANoOpWithoutAMarker() throws {
        // No marker on purpose: a bare-binary run that happens later could still
        // leave something worth migrating.
        try withSuite { d in
            #expect(!Store.migrateLegacyDefaults(legacy: nil, into: d))
            #expect(!Store.migrateLegacyDefaults(legacy: [:], into: d))
            #expect(!d.bool(forKey: "migratedFromLegacyDefaults"))
            #expect(d.dictionaryRepresentation()["goal"] == nil)
        }
    }

    @Test func anExistingIdentityIsNeverOverwritten() throws {
        // A bundle that already launched once (Log.installID minted an id, or
        // Store minted a token) keeps its own state; the stale domain is ignored.
        try withSuite { d in
            d.set("fresh-id", forKey: "installID")
            #expect(!Store.migrateLegacyDefaults(legacy: Self.legacy, into: d))
            #expect(d.string(forKey: "installID") == "fresh-id")
            #expect(d.object(forKey: "goal") == nil)
            #expect(!d.bool(forKey: "migratedFromLegacyDefaults"))
        }
        try withSuite { d in
            d.set(String(repeating: "cd", count: 32), forKey: "bridgeToken")
            #expect(!Store.migrateLegacyDefaults(legacy: Self.legacy, into: d))
            #expect(d.string(forKey: "bridgeToken") == String(repeating: "cd", count: 32))
            #expect(d.object(forKey: "goal") == nil)
        }
    }

    @Test func nonIdentityKeysAloneDoNotBlock() throws {
        // Only installID / bridgeToken count as "already has an identity"; a
        // stray preference in the new domain is overwritten by the legacy copy.
        try withSuite { d in
            d.set("scratch", forKey: "goal")
            #expect(Store.migrateLegacyDefaults(legacy: Self.legacy, into: d))
            #expect(d.string(forKey: "goal") == "Tokyo trip")
        }
    }

    @Test func customMarkerKeyIsHonoured() throws {
        try withSuite { d in
            #expect(Store.migrateLegacyDefaults(legacy: ["goal": "x"], into: d, marker: "m2"))
            #expect(d.bool(forKey: "m2"))
            #expect(!d.bool(forKey: "migratedFromLegacyDefaults"))
            #expect(!Store.migrateLegacyDefaults(legacy: ["goal": "y"], into: d, marker: "m2"))
            #expect(d.string(forKey: "goal") == "x")
        }
    }
}
