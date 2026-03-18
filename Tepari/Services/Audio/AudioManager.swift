import Foundation
import Combine
import AVFoundation
import AudioToolbox

final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    let objectWillChange = ObservableObjectPublisher()

    private let speaker = SpeechAnnouncer()
    private var player: AVAudioPlayer?

    private init() {}

    // =====================================================
    // MARK: - Legacy simple sounds (fallback only)
    // =====================================================

    enum Sound: String, CaseIterable {
        case scanOK
        case weightOK
        case newAnimal
        case readOK
        case reScan
    }

    /// Legacy entry point kept for older call sites.
    /// This path does NOT use AppSettings because AudioManager does not own
    /// a settings singleton in your project.
    ///
    /// To use custom per-trigger speech / audio clips from Settings,
    /// call `playTrigger(_:settings:mobName:className:)` from the session.
    func play(_ sound: Sound, enabled: Bool) {
        guard enabled else { return }

        stopCurrentPlaybackIfNeeded()

        switch sound {
        case .scanOK:
            playDefaultBeep()

        case .weightOK:
            playDefaultBeep()

        case .newAnimal:
            speaker.say("New Animal")

        case .readOK:
            speaker.say("Read OK")

        case .reScan:
            speaker.say("Re-Scan")
        }
    }

    // =====================================================
    // MARK: - Trigger aware (speech or clip)
    // =====================================================

    func playTrigger(
        _ trigger: SpeechTrigger,
        settings: AppSettings,
        mobName: String? = nil,
        className: String? = nil
    ) {
        guard settings.audioEnabled else { return }

        let speechSetting = settings.speechSetting(for: trigger)
        guard speechSetting.enabled else { return }

        let config = settings.resolvedConfig(
            for: trigger,
            mobName: mobName,
            className: className
        )

        switch config.mode {
        case .speech:
            if let phrase = settings.phraseToSpeak(for: trigger),
               !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stopCurrentPlaybackIfNeeded()
                speaker.say(phrase)
            } else {
                playDefaultBeep()
            }

        case .clip:
            guard let clip = settings.clip(for: config.clipID) else {
                if let phrase = settings.phraseToSpeak(for: trigger),
                   !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stopCurrentPlaybackIfNeeded()
                    speaker.say(phrase)
                } else {
                    playDefaultBeep()
                }
                return
            }

            playUserClip(clip)
        }
    }

    // =====================================================
    // MARK: - Playback helpers
    // =====================================================

    private func playUserClip(_ clip: UserAudioClip) {
        do {
            stopCurrentPlaybackIfNeeded()
            let url = try AudioClipStore.fileURL(for: clip.storedFileName)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            playDefaultBeep()
        }
    }

    func playAudioFileFromDocuments(storedFileName: String) {
        do {
            stopCurrentPlaybackIfNeeded()
            let url = try AudioClipStore.fileURL(for: storedFileName)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            playDefaultBeep()
        }
    }

    private func stopCurrentPlaybackIfNeeded() {
        if player?.isPlaying == true {
            player?.stop()
        }
        player = nil
    }

    private func playDefaultBeep() {
        AudioServicesPlaySystemSound(1104)
    }
}
