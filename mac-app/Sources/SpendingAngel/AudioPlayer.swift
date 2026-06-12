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
        if urls.isEmpty {
            Log.error("audio.no_lines", "no mp3s in voice/\(folder) — falling back to angel")
            urls = mp3s(in: "angel"); folder = "angel"
        }
        guard let url = urls.randomElement() else {
            Log.error("audio.no_lines", "no mp3s at all — catch will be silent")
            return nil
        }
        let caption = captions(folder)[url.lastPathComponent]
        if caption == nil {
            Log.debug("audio.caption_missing", "\(folder)/\(url.lastPathComponent) has no captions.json entry")
        }
        return CatchLine(url: url, caption: caption)
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
            Log.error("audio.play_failed", "\(line.url.lastPathComponent): \(error)")
            return 0
        }
    }

    private func mp3s(in folder: String) -> [URL] {
        Bundle.module.urls(forResourcesWithExtension: "mp3", subdirectory: "voice/\(folder)") ?? []
    }

    private func captions(_ folder: String) -> [String: String] {
        if let hit = captionCache[folder] { return hit }
        var dict: [String: String] = [:]
        if let url = Bundle.module.url(forResource: "captions", withExtension: "json", subdirectory: "voice/\(folder)") {
            if let data = try? Data(contentsOf: url),
               let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
                dict = parsed
            } else {
                // The file exists but won't parse — that's broken, not just absent.
                Log.error("audio.captions_malformed", "voice/\(folder)/captions.json failed to parse")
            }
        } else {
            Log.debug("audio.captions_missing", "voice/\(folder) has no captions.json — bubble uses fallback")
        }
        captionCache[folder] = dict
        return dict
    }
}
