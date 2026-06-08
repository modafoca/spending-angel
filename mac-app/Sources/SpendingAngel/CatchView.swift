import SwiftUI

/// Drives the entrance/exit. `visible` is flipped by OverlayController.
final class CatchModel: ObservableObject {
    @Published var visible = false
    let goal: String
    let character: CharacterID
    init(goal: String, character: CharacterID) {
        self.goal = goal
        self.character = character
    }

    var bubbleText: String {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? "Hey. Stop. Don't do that." : "You're saving for \(g)."
    }
}

/// The full-screen, transparent performance. Animated characters play their
/// frame sequence in place (the animation IS the entrance — no slide); static
/// ones still slide in. A near-invisible backdrop lets the 0.5s intercept swallow
/// clicks anywhere on screen.
struct CatchView: View {
    @ObservedObject var model: CatchModel

    private var frames: [NSImage] { CastAssets.frames(model.character) }
    private var animated: Bool { !frames.isEmpty }
    private let charHeight: CGFloat = 285   // 25% smaller than the old 380

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001).ignoresSafeArea()

            HStack(alignment: .top, spacing: -70) {     // bubble tight to the character
                bubble
                character
            }
            .padding(.top, 70)
            .padding(.trailing, 20)
            .rotationEffect(.degrees(animated ? 0 : -3))
            .scaleEffect((model.visible || animated) ? 1 : 0.6)
            .offset(x: animated ? 0 : (model.visible ? 0 : 520))   // animated = no slide
            .opacity(model.visible ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: model.visible)
        }
    }

    private var character: some View {
        Group {
            if animated {
                FrameAnimationView(frames: frames, fps: 12, loops: false)
                    .frame(height: charHeight)
            } else if let art = CastAssets.art(model.character) {
                Image(nsImage: art).interpolation(.none).resizable().scaledToFit()
                    .frame(height: charHeight)
            } else {
                Text(model.character.placeholderEmoji).font(.system(size: 120))
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private var bubble: some View {
        SpeechBubble(text: model.bubbleText, width: 220)   // smaller bubble (type stays the same)
    }
}
