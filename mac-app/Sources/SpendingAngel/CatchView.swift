import SwiftUI

/// Drives the entrance/exit animation. `visible` is flipped by OverlayController.
final class CatchModel: ObservableObject {
    @Published var visible = false
    let goal: String
    let emoji: String
    init(goal: String, emoji: String) {
        self.goal = goal
        self.emoji = emoji
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

    private let navy = Color(red: 0.11, green: 0.18, blue: 0.34)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)                 // hit-testable, ~invisible
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: -10) {
                bubble
                character
            }
            .padding(.top, 90)
            .padding(.trailing, 64)
            .rotationEffect(.degrees(-3))              // sticker tilt
            .scaleEffect(model.visible ? 1 : 0.6)
            .offset(x: model.visible ? 0 : 460)        // slide in from the right
            .opacity(model.visible ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: model.visible)
        }
    }

    // PLACEHOLDER — real Figma cast art lands in M-06. Emoji is an obvious
    // stand-in so nobody ships it by accident.
    private var character: some View {
        Text(model.emoji)
            .font(.system(size: 140))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private var bubble: some View {
        Text(model.bubbleText)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundColor(navy)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(navy, lineWidth: 3)
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .offset(y: 36)
    }
}
