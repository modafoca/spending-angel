import SwiftUI

// Menu-bar only. The icon is the vector $-halo. Clicking it opens the dropdown
// "brain" (window style so it can hold a text field + picker). Real catches
// arrive over the bridge (M-05, wired in AppDelegate); "Test the catch" is manual.
@main
struct SpendingAngelApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var store: Store

    init() {
        // First statement, before anything that could touch `Log`: the bundled
        // app (net.modafoca.spendingangel) starts with an empty defaults domain,
        // and Log.installID lazily mints an id there on its first write — which
        // would make the migration see "already has an identity" and skip the
        // goal, character, counter and pairing token the bare binary saved under
        // the `SpendingAngel` domain (Round 3). The wrapped properties are
        // assigned afterwards for the same reason: AppDelegate must not exist
        // before this has run.
        let legacy = UserDefaults.standard.persistentDomain(forName: "SpendingAngel")
        if Store.migrateLegacyDefaults(legacy: legacy, into: .standard) {
            Log.info("store.defaults_migrated", "copied the bare-binary settings into the bundle's domain",
                     ["keys": String(legacy?.count ?? 0)])
        }
        _delegate = NSApplicationDelegateAdaptor(AppDelegate.self)
        _store = StateObject(wrappedValue: Store.shared)
    }

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
