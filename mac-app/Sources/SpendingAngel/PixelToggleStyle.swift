import SwiftUI

/// A chunky pixel switch with a clearly visible OFF state. The macOS default
/// `.switch` off-track is nearly invisible against our dark theme, so we draw
/// our own: a bordered track (cyan on / mid-blue off) with a sliding knob.
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isOn ? Theme.pxAccent : Theme.pxLine)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.pxInk.opacity(0.25), lineWidth: 1))
                    .frame(width: 40, height: 22)
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? Theme.pxBG : Theme.pxInk)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: configuration.isOn)
    }
}
