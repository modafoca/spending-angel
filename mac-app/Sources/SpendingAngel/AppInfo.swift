import Foundation

/// The app's version, in one place. Read by the bridge's 200/429 bodies
/// (`app_version`, so the sensor can compare it with its own manifest and say
/// "update the app" or "reload the extension"), shown small in the dropdown
/// footer, and grepped by `scripts/bundle.sh` for `CFBundleShortVersionString`.
///
/// Bump rule: change this AND `extension/manifest.json` `version` together, in
/// the same commit. `AppInfoTests` fails when they drift, because the handshake
/// compares major.minor across the two halves.
enum AppInfo {
    static let version = "0.6.1"
}
