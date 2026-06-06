import AppKit

enum AppIcons {
    /// A "$" with a halo, drawn as a monochrome *template* image so the menu bar
    /// tints it correctly for light/dark mode. Placeholder until Ian's real Figma
    /// mark lands (M-06) — but it's the actual concept: money meets angel.
    static let menuBar: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Dollar sign (SF Symbol → crisp + centered), sitting low to leave
            // headroom for the halo.
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .heavy)
            if let dollar = NSImage(systemSymbolName: "dollarsign", accessibilityDescription: "Spending Angel")?
                .withSymbolConfiguration(cfg) {
                let s = dollar.size
                dollar.draw(in: NSRect(x: (rect.width - s.width) / 2, y: 0, width: s.width, height: s.height))
            }

            // Halo: a thin ellipse ring floating just above the dollar sign.
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
