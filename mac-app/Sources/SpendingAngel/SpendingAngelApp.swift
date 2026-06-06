import SwiftUI

// The app is menu-bar only. Its body is a single MenuBarExtra; the real magic
// (the full-screen "catch") lives in OverlayController, fired from the menu.
// No global hotkey on purpose — that would need Input-Monitoring permission,
// and a core principle is that this app requests no invasive permissions.
@main
struct SpendingAngelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Spending Angel", systemImage: "sparkles") {
            Button("▶︎ Test the catch (Angel)") {
                delegate.overlay.performCatch(goal: "Tokyo")
            }
            Divider()
            Button("Quit Spending Angel") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
