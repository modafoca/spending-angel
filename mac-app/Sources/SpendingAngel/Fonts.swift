import AppKit
import CoreText
import SwiftUI

enum Fonts {
    /// Registers the bundled pixel fonts so SwiftUI/AppKit can use them by name.
    /// Call once at launch — SPM apps have no Info.plist ATSApplicationFontsPath.
    static func register() {
        for name in ["Silkscreen-Regular", "Silkscreen-Bold"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "fonts") else {
                Log.error("fonts.missing", "\(name).ttf not in bundle — pixel UI will fall back to system font")
                continue
            }
            var cfError: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError) {
                let err = cfError?.takeRetainedValue()
                // kCTFontManagerErrorAlreadyRegistered (105) is benign on re-register.
                if let err = err, CFErrorGetCode(err) == 105 {
                    Log.debug("fonts.already_registered", name)
                } else {
                    Log.error("fonts.register_failed", "\(name): \(err.map(String.init(describing:)) ?? "unknown error")")
                }
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
