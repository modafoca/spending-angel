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
        // Only requests carrying the pairing token get this far (the token is
        // read per request, so "regenerate" in the dropdown needs no restart).
        // Real intents respect on/off + snooze (unlike the manual Test button).
        // CatchRunner.decide maps that to an outcome the bridge sends back in
        // the 200 body (Round 3); CatchRunner.run asks the overlay first and
        // counts/logs only if admitted, and skipOffDuty owns the off-duty line
        // so every logged hostname is clipped. Log events are unchanged.
        let server = BridgeServer(expectedToken: { Store.shared.bridgeToken },
                                  snoozeUntil: { Store.shared.snoozeUntil }) { [weak self] intent in
            let store = Store.shared
            let outcome = CatchRunner.decide(enabled: store.enabled, snoozeUntil: store.snoozeUntil, now: Date()) {
                let character = store.nextCatchCharacter()   // honors Shake It Up
                let admitted = CatchRunner.run(goal: store.goal, character: character,
                                               source: "bridge", hostname: intent.hostname, intentID: intent.id,
                                               perform: { g, c in self?.overlay.performCatch(goal: g, character: c) ?? false },
                                               record: store.recordCatch)
                return admitted ? character : nil
            }
            switch outcome {
            case .skipped(.off), .skipped(.snoozed):
                CatchRunner.skipOffDuty(hostname: intent.hostname, intentID: intent.id)
            case .shown, .skipped(.busy):
                break   // CatchRunner.run already wrote catch.performed / catch.skipped_busy
            }
            return outcome
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
