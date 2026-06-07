import SwiftUI

// Menu-bar only. The icon is a $ with a halo (AppIcons.menuBar). Clicking it
// opens the dropdown "brain" (window style so it can hold a text field + picker).
// Real catches arrive over the bridge (M-05, wired in AppDelegate); the dropdown's
// "Test the catch" button is the manual trigger.
@main
struct SpendingAngelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store) {
                // Manual test fires regardless of on-duty state, but still counts
                // toward the stat so you can watch the brag climb.
                store.recordCatch()
                delegate.overlay.performCatch(goal: store.goal, character: store.activeCharacter)
            }
        } label: {
            Image(nsImage: AppIcons.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
