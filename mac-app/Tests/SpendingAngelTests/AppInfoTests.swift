import Foundation
import Testing
@testable import SpendingAngel

/// The two halves ship one version. `AppInfo.version` (app) and
/// `extension/manifest.json` (sensor) must be bumped together; the sensor's
/// version hint compares major.minor across the bridge, so a drift here would
/// tell the user to "update the app" right after they did.
struct AppInfoTests {

    /// `#filePath` is …/mac-app/Tests/SpendingAngelTests/AppInfoTests.swift;
    /// four hops up is the repo root, wherever the checkout lives.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func versionMatchesTheSensorManifest() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("extension/manifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sensor = try #require(manifest["version"] as? String)
        #expect(sensor == AppInfo.version, "bump AppInfo.version and extension/manifest.json together")
    }

    @Test func versionIsThreeNumbers() {
        let parts = AppInfo.version.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}
