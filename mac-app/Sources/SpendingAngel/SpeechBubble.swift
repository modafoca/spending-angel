import SwiftUI

/// Reveals text one character at a time (typewriter), matched to the spoken line.
final class Typewriter: ObservableObject {
    @Published var shown = ""
    private var timer: Timer?

    func type(_ full: String, cps: Double) {
        timer?.invalidate()
        let chars = Array(full)
        shown = ""
        guard !chars.isEmpty else { return }
        var i = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / cps, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            i += 1
            self.shown = String(chars[0..<min(i, chars.count)])
            if i >= chars.count { t.invalidate() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}

/// Ian's pixel speech bubble (art) with the spoken line typed out in the pixel
/// font. Pops in after a short delay (so the character enters first), then types.
struct SpeechBubble: View {
    let text: String
    var width: CGFloat = 220
    var delay: Double = 0.7            // wait for the character to enter / start talking

    @StateObject private var tw = Typewriter()
    @State private var shown = false

    private var img: NSImage? { CastAssets.ui("pixel-speech-bubble") }
    private var aspect: CGFloat {
        if let s = img?.size, s.width > 0 { return s.height / s.width }
        return 708.0 / 1694.0
    }
    private var height: CGFloat { width * aspect }

    var body: some View {
        ZStack {
            if let img = img {
                Image(nsImage: img)
                    .resizable()                          // smooth downscale (no nearest-neighbor grid)
                    .frame(width: width, height: height)
            }
            Text(tw.shown)
                .font(.pixel(10))
                .foregroundColor(Theme.bubbleInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width * 0.80)
                .offset(y: -height * 0.07)
        }
        .frame(width: width, height: height)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.85, anchor: .bottomTrailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shown)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                shown = true
                tw.type(text, cps: 24)
            }
        }
    }
}
