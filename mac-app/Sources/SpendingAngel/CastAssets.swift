import AppKit

/// Loads bundled art (character figures, portraits, animation frames, UI art),
/// cached. Transparent PNGs live under Resources/.
enum CastAssets {
    private static var cache: [String: NSImage] = [:]
    private static var frameCache: [String: [NSImage]] = [:]
    private static var reported = Set<String>()    // log each missing asset once, not per render

    private static func load(_ name: String, subdir: String = "cast") -> NSImage? {
        let key = "\(subdir)/\(name)"
        if let hit = cache[key] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdir),
              let img = NSImage(contentsOf: url) else {
            if reported.insert(key).inserted {
                Log.error("assets.missing", "\(key).png not loadable from bundle")
            }
            return nil
        }
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
        if imgs.count < urls.count, reported.insert("frames/\(c.rawValue)").inserted {
            Log.error("assets.frames_unreadable", "\(urls.count - imgs.count) frame(s) in cast/\(c.rawValue)_sequence failed to load")
        }
        if imgs.isEmpty, reported.insert("noframes/\(c.rawValue)").inserted {
            Log.debug("assets.no_frames", "\(c.rawValue) has no animation — using static art")
        }
        frameCache[c.rawValue] = imgs
        return imgs
    }
}
