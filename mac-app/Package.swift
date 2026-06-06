// swift-tools-version: 5.9
import PackageDescription

// Spending Angel — macOS menu-bar performer.
// Shipped as a Swift Package (not a .xcodeproj) so it builds reliably from
// terminal AND opens/runs in Xcode. Wrapping into a signed, notarized .app
// bundle is M-FINAL work. See README.md.
let package = Package(
    name: "SpendingAngel",
    platforms: [.macOS(.v13)],            // MenuBarExtra requires macOS 13+
    targets: [
        .executableTarget(
            name: "SpendingAngel",
            resources: [
                // Preserves the voice/<character>/ folder structure in the
                // bundle so AudioPlayer can look up catch-N.mp3 by subdirectory.
                .copy("Resources/voice")
            ]
        )
    ]
)
