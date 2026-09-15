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
                // for character choice, and counts toward the stat — but only when
                // the overlay actually admitted it (CatchRunner, NATIVE-03).
                let character = store.nextCatchCharacter()
                CatchRunner.run(goal: store.goal, character: character,
                                source: "test", hostname: "manual test", intentID: nil,
                                perform: { g, c in delegate.overlay.performCatch(goal: g, character: c) },
                                record: store.recordCatch)
            }
        } label: {
            Image(nsImage: AppIcons.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
