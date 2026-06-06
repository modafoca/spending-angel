import SwiftUI

// Menu-bar only. The icon is a $ with a halo (AppIcons.menuBar). Clicking it
// opens the dropdown "brain" (window style so it can hold a text field + picker).
// The real catch still fires from the dropdown's "Test the catch" button — the
// browser-driven trigger arrives in M-05.
@main
struct SpendingAngelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store) {
                delegate.overlay.performCatch(goal: store.goal, character: store.activeCharacter)
            }
        } label: {
            Image(nsImage: AppIcons.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
