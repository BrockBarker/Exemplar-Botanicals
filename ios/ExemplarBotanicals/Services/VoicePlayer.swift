import Foundation
import AVFoundation
import Observation
import GardenCore

/// Plays coach replies in David's cloned voice. Audio comes from the backend (ElevenLabs)
/// and is cached on the phone, so replaying a reply costs nothing.
@MainActor
@Observable
final class VoicePlayer {
    /// Cache key of the reply that is playing, or loading.
    private(set) var playingKey: String?
    private(set) var loadingKey: String?
    var errorMessage: String?

    private var player: AVAudioPlayer?
    private let delegate = PlayerDelegate()

    init() {
        delegate.onFinish = { [weak self] in
            Task { @MainActor in self?.playingKey = nil }
        }
    }

    func isPlaying(_ text: String) -> Bool { playingKey == SpeechText.cacheKey(text) }
    func isLoading(_ text: String) -> Bool { loadingKey == SpeechText.cacheKey(text) }

    /// Plays the reply, or stops it if it's already playing.
    func toggle(text: String, service: CoachService) async {
        if isPlaying(text) {
            stop()
        } else {
            await play(text: text, service: service)
        }
    }

    func play(text: String, service: CoachService) async {
        let key = SpeechText.cacheKey(text)
        stop()
        errorMessage = nil
        let file = Self.cacheDirectory.appendingPathComponent("\(key).mp3")
        var data = try? Data(contentsOf: file)
        if data == nil {
            loadingKey = key
            defer { loadingKey = nil }
            do {
                let audio = try await service.speak(text)
                try? audio.write(to: file, options: .atomic)
                data = audio
            } catch {
                errorMessage = (error as? CoachAPIError)?.userMessage ?? "Couldn't play the voice."
                return
            }
        }
        guard let audio = data else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: audio)
            player.delegate = delegate
            player.prepareToPlay()
            player.play()
            self.player = player
            playingKey = key
        } catch {
            errorMessage = "Couldn't play the voice."
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingKey = nil
    }

    func clearCache() {
        stop()
        try? FileManager.default.removeItem(at: Self.cacheDirectory)
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
