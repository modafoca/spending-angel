import SwiftUI

/// Drives the entrance/exit animation. `visible` is flipped by OverlayController.
final class CatchModel: ObservableObject {
    @Published var visible = false
    let goal: String
    init(goal: String) { self.goal = goal }
}

/// The full-screen, transparent performance. Only the Angel + bubble have visual
/// weight; the rest is a near-invisible backdrop that exists so the 0.5s click
/// intercept swallows clicks anywhere on screen, not just on the character.
struct CatchView: View {
    @ObservedObject var model: CatchModel

    private let navy = Color(red: 0.11, green: 0.18, blue: 0.34)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)                 // hit-testable, ~invisible
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: -10) {
                bubble
                angel
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

    // PLACEHOLDER — real Figma cast art lands in M-06. The emoji is unmistakably
    // a stand-in so nobody ships it by accident.
    private var angel: some View {
        Text("😇")
            .font(.system(size: 140))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private var bubble: some View {
        Text("You're saving for \(model.goal).")
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
