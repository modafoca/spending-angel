import AVFoundation

/// A catch-line: the audio file + its on-screen caption (the bubble text).
struct CatchLine {
    let url: URL
    let caption: String?
}

/// Plays catch-lines at full volume and pairs each with its caption.
/// Captions come from `voice/<id>/captions.json` ({ "filename.mp3": "text" }).
final class AudioPlayer {
    static let shared = AudioPlayer()
    private var player: AVAudioPlayer?
    private var captionCache: [String: [String: String]] = [:]

    /// Picks a random catch-line for the character (any `.mp3` in `voice/<id>/`)
    /// with its caption, falling back to the Angel folder. Does NOT play yet.
    func pickLine(for character: CharacterID) -> CatchLine? {
        var urls = mp3s(in: character.rawValue)
        var folder = character.rawValue
        if urls.isEmpty { urls = mp3s(in: "angel"); folder = "angel" }
        guard let url = urls.randomElement() else { return nil }
        return CatchLine(url: url, caption: captions(folder)[url.lastPathComponent])
    }

    /// Plays the line at full volume; returns its duration.
    @discardableResult
    func play(_ line: CatchLine) -> TimeInterval {
        player?.stop()                                   // clean handoff
        do {
            let p = try AVAudioPlayer(contentsOf: line.url)
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            player = p
            return p.duration
        } catch {
            print("[SpendingAngel] audio error: \(error)")
            return 0
        }
    }

    private func mp3s(in folder: String) -> [URL] {
        Bundle.module.urls(forResourcesWithExtension: "mp3", subdirectory: "voice/\(folder)") ?? []
    }

    private func captions(_ folder: String) -> [String: String] {
        if let hit = captionCache[folder] { return hit }
        var dict: [String: String] = [:]
        if let url = Bundle.module.url(forResource: "captions", withExtension: "json", subdirectory: "voice/\(folder)"),
           let data = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            dict = parsed
        }
        captionCache[folder] = dict
        return dict
    }
}
