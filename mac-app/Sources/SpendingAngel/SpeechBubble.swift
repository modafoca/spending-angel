import SwiftUI

/// Ian's pixel speech bubble (art) with the goal text in the pixel font.
/// Aspect ratio is taken from the PNG itself, so dropping in a new bubble image
/// needs no code change. Tail is bottom-right (points at the character).
struct SpeechBubble: View {
    let text: String
    var width: CGFloat = 280

    private var img: NSImage? { CastAssets.ui("pixel-speech-bubble") }
    private var aspect: CGFloat {
        if let s = img?.size, s.width > 0 { return s.height / s.width }
        return 708.0 / 1694.0   // fallback if the asset is missing
    }
    private var height: CGFloat { width * aspect }

    var body: some View {
        ZStack {
            if let img = img {
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
                .frame(width: width * 0.80)         // keep text inside the body
                .offset(y: -height * 0.07)          // bias up, away from the bevel/tail
        }
        .frame(width: width, height: height)
    }
}
