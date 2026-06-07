import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Owns the overlay so it survives across catches.
    let overlay = OverlayController()
    private var bridge: BridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()                       // pixel UI font (Silkscreen)

        // Menu-bar only: no Dock icon, no main window. SPM stand-in for LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        // The bridge: real checkout intents from the browser sensor land here.
        // Unlike the manual "Test the catch" button, real intents respect the
        // on/off + snooze state.
        let server = BridgeServer { [weak self] intent in
            guard Store.shared.onDuty else {
                print("[bridge] intent from \(intent.hostname) ignored — off duty")
                return
            }
            Store.shared.recordCatch()
            self?.overlay.performCatch(goal: Store.shared.goal, character: Store.shared.activeCharacter)
        }
        // Single-instance guard: if the port's already bound, a copy is already
        // running — quit this one so we never stack two menu-bar icons.
        server.onAddressInUse = {
            print("[SpendingAngel] another instance is already running — quitting this one.")
            NSApp.terminate(nil)
        }
        server.start()
        bridge = server
    }
}
