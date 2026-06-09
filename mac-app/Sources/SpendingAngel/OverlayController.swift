import AppKit
import SwiftUI

/// Owns the full-screen "performance" panel and runs the catch sequence:
///
///   t+0.0  show panel; character animates/enters; clicks intercepted; voice plays
///   t+0.5  intercept releases (panel becomes click-through)
///   t+hold auto-dismiss (long enough for the whole voice line)
final class OverlayController {
    private var panel: NSPanel?
    private var model: CatchModel?
    private var autoDismiss: DispatchWorkItem?

    func performCatch(goal: String, character: CharacterID) {
        guard panel == nil else { return }             // a catch is already on screen — ignore
        guard let screen = NSScreen.main else { return }   // re-triggers (avoids audio/anim races)

        // Pick the line + its caption up front so the bubble can type the exact
        // text being spoken. Falls back to the goal reminder if no caption yet.
        let line = AudioPlayer.shared.pickLine(for: character)
        let caption = line?.caption ?? Self.fallbackCaption(goal: goal)

        let model = CatchModel(goal: goal, character: character, caption: caption)
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

        // Voice — full volume; duration sets how long we hold the overlay.
        let duration = line.map { AudioPlayer.shared.play($0) } ?? 0

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

    /// Used until a character has a captions.json — keeps the goal reminder.
    private static func fallbackCaption(goal: String) -> String {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? "Hey. Stop. Don't do that." : "You're saving for \(g)."
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
