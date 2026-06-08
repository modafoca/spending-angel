import AppKit

/// Loads bundled art (character figures, portraits, animation frames, UI art),
/// cached. Transparent PNGs live under Resources/.
enum CastAssets {
    private static var cache: [String: NSImage] = [:]
    private static var frameCache: [String: [NSImage]] = [:]

    private static func load(_ name: String, subdir: String = "cast") -> NSImage? {
        let key = "\(subdir)/\(name)"
        if let hit = cache[key] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdir),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[key] = img
        return img
    }

    /// Full static performance figure for the overlay.
    static func art(_ c: CharacterID) -> NSImage? { load(c.rawValue) }

    /// Cropped head/bust for the dropdown picker + header.
    static func portrait(_ c: CharacterID) -> NSImage? { load("\(c.rawValue)-portrait") }

    /// UI art (e.g. the speech bubble) from Resources/ui/.
    static func ui(_ name: String) -> NSImage? { load(name, subdir: "ui") }

    /// Animation frames from `cast/<id>_sequence/`, sorted by filename. Empty if
    /// the character has no animation (then the overlay uses the static art).
    static func frames(_ c: CharacterID) -> [NSImage] {
        if let hit = frameCache[c.rawValue] { return hit }
        let urls = (Bundle.module.urls(forResourcesWithExtension: "png",
                                       subdirectory: "cast/\(c.rawValue)_sequence") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let imgs = urls.compactMap { NSImage(contentsOf: $0) }
        frameCache[c.rawValue] = imgs
        return imgs
    }
}
