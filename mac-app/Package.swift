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
                .copy("Resources/voice"),   // catch-line audio per character
                .copy("Resources/cast"),    // Figma character art + portraits
                .copy("Resources/icon"),    // menu-bar mark (vector $-halo)
                .copy("Resources/fonts"),   // pixel UI font (Silkscreen)
                .copy("Resources/ui")       // speech bubble + UI art
            ]
        )
    ]
)
