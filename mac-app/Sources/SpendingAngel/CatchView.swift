import SwiftUI

/// Drives the entrance/exit animation. `visible` is flipped by OverlayController.
final class CatchModel: ObservableObject {
    @Published var visible = false
    let goal: String
    let character: CharacterID
    init(goal: String, character: CharacterID) {
        self.goal = goal
        self.character = character
    }

    /// Goal-agnostic fallback when no goal is set — the voice never names the
    /// goal anyway; only this on-screen text does.
    var bubbleText: String {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? "Hey. Stop. Don't do that." : "You're saving for \(g)."
    }
}

/// The full-screen, transparent performance. Only the character + bubble have
/// visual weight; the rest is a near-invisible backdrop that exists so the 0.5s
/// click intercept swallows clicks anywhere on screen, not just on the character.
struct CatchView: View {
    @ObservedObject var model: CatchModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)                 // hit-testable, ~invisible
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: -16) {
                bubble
                character
            }
            .padding(.top, 70)
            .padding(.trailing, 56)
            .rotationEffect(.degrees(-3))              // sticker tilt
            .scaleEffect(model.visible ? 1 : 0.6)
            .offset(x: model.visible ? 0 : 520)        // slide in from the right
            .opacity(model.visible ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: model.visible)
        }
    }

    private var character: some View {
        Group {
            if let art = CastAssets.art(model.character) {
                Image(nsImage: art).interpolation(.none).resizable().scaledToFit().frame(height: 380)
            } else {
                Text(model.character.placeholderEmoji).font(.system(size: 150)) // fallback
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private var bubble: some View {
        Text(model.bubbleText)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundColor(Theme.navy)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.navy, lineWidth: 3)
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .offset(y: 40)
    }
}
