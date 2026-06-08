import SwiftUI

/// Drives a one-shot (or looping) frame animation from an array of NSImages.
final class SpriteAnimator: ObservableObject {
    @Published var index = 0
    private var timer: Timer?
    private let count: Int
    private let fps: Double
    private let loops: Bool

    init(count: Int, fps: Double, loops: Bool) {
        self.count = count
        self.fps = fps
        self.loops = loops
    }

    func start() {
        index = 0
        timer?.invalidate()
        guard count > 1, fps > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.index + 1 < self.count {
                self.index += 1
            } else if self.loops {
                self.index = 0
            } else {
                t.invalidate()                 // hold the last frame
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}

/// Plays a sequence of NSImage frames, rendered pixel-crisp.
struct FrameAnimationView: View {
    let frames: [NSImage]
    let fps: Double
    let loops: Bool
    @StateObject private var anim: SpriteAnimator

    init(frames: [NSImage], fps: Double = 12, loops: Bool = false) {
        self.frames = frames
        self.fps = fps
        self.loops = loops
        _anim = StateObject(wrappedValue: SpriteAnimator(count: frames.count, fps: fps, loops: loops))
    }

    var body: some View {
        Image(nsImage: frames[min(anim.index, max(frames.count - 1, 0))])
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .onAppear { anim.start() }
            .onDisappear { anim.stop() }
    }
}
