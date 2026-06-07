import AppKit

/// Loads the Figma character art (full figure + cropped portrait) from the
/// bundle, cached. Real transparent PNGs live in Resources/cast/.
enum CastAssets {
    private static var cache: [String: NSImage] = [:]

    private static func load(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "cast"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }

    /// Full performance figure for the overlay.
    static func art(_ c: CharacterID) -> NSImage? { load(c.rawValue) }

    /// Cropped head/bust for the dropdown picker + header.
    static func portrait(_ c: CharacterID) -> NSImage? { load("\(c.rawValue)-portrait") }
}
