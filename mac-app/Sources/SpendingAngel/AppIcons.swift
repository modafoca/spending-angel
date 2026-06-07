import AppKit

enum AppIcons {
    /// The menu-bar mark: Ian's vector $-with-halo from Figma, rendered as a
    /// monochrome template image so it auto-tints for light/dark. Falls back to
    /// the programmatic halo below if the asset ever fails to load.
    static let menuBar: NSImage = vectorMark() ?? halo

    private static func vectorMark() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "menubar", withExtension: "svg", subdirectory: "icon"),
              let img = NSImage(contentsOf: url), img.isValid else { return nil }
        let h: CGFloat = 18
        img.size = NSSize(width: h * (img.size.width / max(img.size.height, 1)), height: h)
        img.isTemplate = true
        return img
    }

    /// Previous mark — a $ with a halo drawn in code. Kept as a fallback, and so
    /// we can flip straight back to it if the vector mark ever needs reverting.
    static let halo: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .heavy)
            if let dollar = NSImage(systemSymbolName: "dollarsign", accessibilityDescription: "Spending Angel")?
                .withSymbolConfiguration(cfg) {
                let s = dollar.size
                dollar.draw(in: NSRect(x: (rect.width - s.width) / 2, y: 0, width: s.width, height: s.height))
            }
            NSColor.black.setStroke()
            let halo = NSBezierPath(ovalIn: NSRect(x: rect.midX - 4.5, y: rect.maxY - 4, width: 9, height: 3))
            halo.lineWidth = 1.3
            halo.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
