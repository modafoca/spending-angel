import Foundation
import Testing
@testable import SpendingAngel

/// NATIVE-03 — the overlay's admission state that can be checked without a
/// window server: a fresh controller is idle, `isPerforming` mirrors the panel,
/// and `dismiss` on an idle controller is a harmless no-op. The `true` path of
/// `performCatch` (NSPanel + NSScreen + audio) is covered by the manual
/// checklist in docs/design-spec.md §6c, not here. The perform → record → log
/// sequencing lives in CatchRunnerTests; the `(String, CharacterID) -> Bool`
/// shape of `performCatch` is pinned at compile time by the production call
/// sites in AppDelegate / SpendingAngelApp.
struct CatchAdmissionTests {

    @Test func freshOverlayIsNotPerforming() {
        let overlay = OverlayController()
        #expect(!overlay.isPerforming)
    }

    @Test func dismissOnIdleOverlayIsNoOp() {
        let overlay = OverlayController()
        overlay.dismiss(animated: false)
        #expect(!overlay.isPerforming)
        overlay.dismiss(animated: true)
        #expect(!overlay.isPerforming)
    }
}
