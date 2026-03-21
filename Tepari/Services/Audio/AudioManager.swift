import Foundation
import Combine
import AVFoundation
import AudioToolbox

final class AudioManager: NSObject, ObservableObject {
    static let shared = AudioManager()

    let objectWillChange = ObservableObjectPublisher()

    private let speaker = SpeechAnnouncer()
    private var player: AVAudioPlayer?

    private enum QueueItem {
        case speech(String)
        case clip(UserAudioClip)
        case documentClip(String)
        case beep
    }

    private var queue: [QueueItem] = []
    private var isPlayingQueueItem = false

    private override init() {
        super.init()
    }

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

        switch sound {
        case .scanOK:
            enqueue(.beep)

        case .weightOK:
            enqueue(.beep)

        case .newAnimal:
            enqueue(.speech("New Animal"))

        case .readOK:
            enqueue(.speech("Read OK"))

        case .reScan:
            enqueue(.speech("Re-Scan"))
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
                enqueue(.speech(phrase))
            } else {
                enqueue(.beep)
            }

        case .clip:
            guard let clip = settings.clip(for: config.clipID) else {
                if let phrase = settings.phraseToSpeak(for: trigger),
                   !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    enqueue(.speech(phrase))
                } else {
                    enqueue(.beep)
                }
                return
            }

            enqueue(.clip(clip))
        }
    }

    // =====================================================
    // MARK: - Playback helpers
    // =====================================================

    private func playUserClip(_ clip: UserAudioClip) {
        do {
            let url = try AudioClipStore.fileURL(for: clip.storedFileName)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            if player?.isPlaying != true {
                finishCurrentQueueItem()
            }
        } catch {
            playDefaultBeep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.finishCurrentQueueItem()
            }
        }
    }

    func playAudioFileFromDocuments(storedFileName: String) {
        enqueue(.documentClip(storedFileName))
    }

    private func playDocumentClip(storedFileName: String) {
        do {
            let url = try AudioClipStore.fileURL(for: storedFileName)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()

            if player?.isPlaying != true {
                finishCurrentQueueItem()
            }
        } catch {
            playDefaultBeep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.finishCurrentQueueItem()
            }
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

    // =====================================================
    // MARK: - Queue
    // =====================================================

    private func enqueue(_ item: QueueItem) {
        DispatchQueue.main.async {
            self.queue.append(item)
            self.playNextIfNeeded()
        }
    }

    private func playNextIfNeeded() {
        guard !isPlayingQueueItem else { return }
        guard !queue.isEmpty else { return }

        isPlayingQueueItem = true
        let next = queue.removeFirst()

        switch next {
        case .speech(let text):
            stopCurrentPlaybackIfNeeded()
            speaker.say(text) { [weak self] in
                self?.finishCurrentQueueItem()
            }

        case .clip(let clip):
            stopCurrentPlaybackIfNeeded()
            playUserClip(clip)

        case .documentClip(let storedFileName):
            stopCurrentPlaybackIfNeeded()
            playDocumentClip(storedFileName: storedFileName)

        case .beep:
            stopCurrentPlaybackIfNeeded()
            playDefaultBeep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.finishCurrentQueueItem()
            }
        }
    }

    private func finishCurrentQueueItem() {
        DispatchQueue.main.async {
            self.isPlayingQueueItem = false
            self.playNextIfNeeded()
        }
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishCurrentQueueItem()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finishCurrentQueueItem()
    }
}
