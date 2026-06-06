import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Owns the overlay so it survives across catches.
    let overlay = OverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no main window. This is the SPM stand-in
        // for Info.plist's LSUIElement = true (a real .app bundle comes at M-FINAL).
        NSApp.setActivationPolicy(.accessory)
    }
}
