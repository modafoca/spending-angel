import AppKit
import CoreText
import SwiftUI

enum Fonts {
    /// Registers the bundled pixel fonts so SwiftUI/AppKit can use them by name.
    /// Call once at launch — SPM apps have no Info.plist ATSApplicationFontsPath.
    static func register() {
        for name in ["Silkscreen-Regular", "Silkscreen-Bold"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    /// The pixel UI font (Silkscreen). Reads crispest at multiples of 8.
    static func pixel(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Silkscreen-Bold" : "Silkscreen-Regular", size: size)
    }
}
