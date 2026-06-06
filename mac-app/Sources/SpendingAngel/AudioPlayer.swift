import AVFoundation

/// Plays catch-lines at full volume — no browser, no autoplay gating. This is
/// the whole reason the performer is native instead of in the browser.
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVAudioPlayer?

    /// Plays a random Angel catch-line. Looks for
    /// Resources/voice/angel/catch-{1,2,3}.mp3 in the module bundle. Ian drops
    /// his real ElevenLabs recordings there; until then catch-1.mp3 is a
    /// placeholder copied from the old extension sound.
    func playRandomAngelCatch() {
        let urls = (1...3).compactMap { n in
            Bundle.module.url(
                forResource: "catch-\(n)",
                withExtension: "mp3",
                subdirectory: "voice/angel"
            )
        }
        guard let url = urls.randomElement() else {
            print("[SpendingAngel] no Angel catch-line audio found in bundle")
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            player = p                                 // retain through playback
        } catch {
            print("[SpendingAngel] audio error: \(error)")
        }
    }
}
