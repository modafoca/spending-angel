import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Owns the overlay so it survives across catches.
    let overlay = OverlayController()
    private var bridge: BridgeServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("app.launch", "Spending Angel starting")
        Fonts.register()                       // pixel UI font (Silkscreen)

        // Menu-bar only: no Dock icon, no main window. SPM stand-in for LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        // The bridge: real checkout intents from the browser sensor land here.
        // Real intents respect on/off + snooze (unlike the manual Test button).
        let server = BridgeServer { [weak self] intent in
            guard Store.shared.onDuty else {
                Log.info("catch.skipped_off_duty", intent.hostname, ["intent_id": intent.id ?? ""])
                return
            }
            let character = Store.shared.nextCatchCharacter()   // honors Shake It Up
            Store.shared.recordCatch()
            Log.info("catch.performed", intent.hostname,
                     ["intent_id": intent.id ?? "", "character": character.rawValue, "source": "bridge"])
            self?.overlay.performCatch(goal: Store.shared.goal, character: character)
        }
        // Single-instance guard: if the port's already bound, a copy is already
        // running — quit this one so we never stack two menu-bar icons.
        server.onAddressInUse = {
            Log.info("app.duplicate_instance", "port already bound — quitting this copy")
            NSApp.terminate(nil)
        }
        server.start()
        bridge = server
    }
}
