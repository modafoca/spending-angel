import AVFoundation

/// Plays catch-lines at full volume — no browser, no autoplay gating. This is
/// the whole reason the performer is native instead of in the browser.
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVAudioPlayer?

    /// Plays a random catch-line for the given character. Looks in
    /// Resources/voice/<character>/catch-{1,2,3}.mp3; falls back to the Angel
    /// folder (the only one with a placeholder for now). Ian drops real
    /// ElevenLabs recordings into each character's folder for M-06.
    func playRandomCatch(for character: CharacterID) {
        var urls = catchURLs(folder: character.rawValue)
        if urls.isEmpty { urls = catchURLs(folder: "angel") }   // placeholder fallback

        guard let url = urls.randomElement() else {
            print("[SpendingAngel] no catch-line audio found for \(character.rawValue)")
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

    private func catchURLs(folder: String) -> [URL] {
        (1...3).compactMap { n in
            Bundle.module.url(
                forResource: "catch-\(n)",
                withExtension: "mp3",
                subdirectory: "voice/\(folder)"
            )
        }
    }
}
