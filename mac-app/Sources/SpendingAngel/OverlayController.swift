import AppKit
import SwiftUI

/// Owns the full-screen "performance" panel and runs the catch sequence:
///
///   t+0.0  show panel; character animates/enters; clicks intercepted; voice plays
///   t+0.5  intercept releases (panel becomes click-through)
///   t+hold auto-dismiss (hold = long enough for the whole voice line)
///
/// The 0.5s intercept is the "get through me first" gag.
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

        // Voice — full volume. Capture duration so the overlay stays up for the
        // whole line (animations + longer voiced lines need the room).
        let duration = AudioPlayer.shared.playRandomCatch(for: character)

        // Release the click-intercept after ~0.5s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak panel] in
            panel?.ignoresMouseEvents = true
        }

        // Auto-dismiss — at least 4s, or long enough for the voice line + a tail.
        let hold = max(4.0, duration + 0.6)
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        autoDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
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
