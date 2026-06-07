import AppKit
import SwiftUI

/// Owns the full-screen "performance" panel and runs the catch sequence:
///
///   t+0.0  show panel; character animates in; clicks intercepted
///   t+0.1  catch-line plays at full volume
///   t+0.5  intercept releases (panel becomes click-through)
///   t+4.0  auto-dismiss with an exit animation
///
/// The 0.5s intercept is the "get through me first" gag. After it, the overlay
/// is click-through so you proceed with your purchase; it fades on its own at 4s.
final class OverlayController {
    private var panel: NSPanel?
    private var model: CatchModel?
    private var autoDismiss: DispatchWorkItem?

    func performCatch(goal: String, character: CharacterID) {
        dismiss(animated: false)                       // never stack two

        guard let screen = NSScreen.main else { return }

        let model = CatchModel(goal: goal, character: character)
        self.model = model

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false               // intercept ON at the start
        panel.contentView = NSHostingView(rootView: CatchView(model: model))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // Entrance (next runloop tick so the transition animates from hidden).
        DispatchQueue.main.async { model.visible = true }

        // Voice ~0.1s in, full volume.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioPlayer.shared.playRandomCatch(for: character)
        }

        // Release the click-intercept after ~0.5s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak panel] in
            panel?.ignoresMouseEvents = true
        }

        // Auto-dismiss after ~4s.
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        autoDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    func dismiss(animated: Bool) {
        autoDismiss?.cancel()
        autoDismiss = nil
        guard panel != nil else { return }

        let close = { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.model = nil
        }

        if animated, let model = model {
            model.visible = false                      // triggers the exit animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: close)
        } else {
            close()
        }
    }
}
