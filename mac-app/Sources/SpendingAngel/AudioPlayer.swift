import AVFoundation

/// Plays catch-lines at full volume — no browser, no autoplay gating.
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVAudioPlayer?

    /// Plays a random catch-line for the character — ANY `.mp3` in
    /// `voice/<id>/` (so Ian's files can be named anything), falling back to the
    /// Angel folder. Returns the clip duration so the overlay can stay up for the
    /// whole line.
    @discardableResult
    func playRandomCatch(for character: CharacterID) -> TimeInterval {
        var urls = mp3s(in: character.rawValue)
        if urls.isEmpty { urls = mp3s(in: "angel") }     // placeholder fallback
        guard let url = urls.randomElement() else {
            print("[SpendingAngel] no catch-line audio for \(character.rawValue)")
            return 0
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            player = p                                   // retain through playback
            return p.duration
        } catch {
            print("[SpendingAngel] audio error: \(error)")
            return 0
        }
    }

    private func mp3s(in folder: String) -> [URL] {
        Bundle.module.urls(forResourcesWithExtension: "mp3", subdirectory: "voice/\(folder)") ?? []
    }
}
