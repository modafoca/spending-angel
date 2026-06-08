import SwiftUI

/// Ian's pixel speech bubble (art) with the goal text in the pixel font.
/// Tail is bottom-right (points at the character to its right).
struct SpeechBubble: View {
    let text: String
    var width: CGFloat = 280

    private let aspect: CGFloat = 708.0 / 1694.0   // bubble PNG aspect
    private var height: CGFloat { width * aspect }

    var body: some View {
        ZStack {
            if let img = CastAssets.ui("pixel-speech-bubble") {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: width, height: height)
            }
            Text(text)
                .font(.pixel(10))
                .foregroundColor(Theme.bubbleInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width * 0.78)         // keep text inside the body
                .offset(y: -height * 0.07)          // bias up, away from the bevel/tail
        }
        .frame(width: width, height: height)
    }
}
