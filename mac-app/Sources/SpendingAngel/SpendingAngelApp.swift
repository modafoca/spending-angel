import SwiftUI

// Menu-bar only. The icon is the vector $-halo. Clicking it opens the dropdown
// "brain" (window style so it can hold a text field + picker). Real catches
// arrive over the bridge (M-05, wired in AppDelegate); "Test the catch" is manual.
@main
struct SpendingAngelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store) {
                // Manual test fires regardless of on-duty state; honors Shake It Up
                // for character choice, and counts toward the stat.
                let character = store.nextCatchCharacter()
                store.recordCatch()
                delegate.overlay.performCatch(goal: store.goal, character: character)
            }
        } label: {
            Image(nsImage: AppIcons.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
