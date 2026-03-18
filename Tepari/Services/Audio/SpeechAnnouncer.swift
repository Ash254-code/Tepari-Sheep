import AVFoundation

/// Central speech helper.
/// ✅ Ensures AVAudioSession is configured + activated so speech works in silent mode / yards.
final class SpeechAnnouncer {

    private let synth = AVSpeechSynthesizer()
    private var didConfigureSession = false

    // MARK: - Public

    func say(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        configureAudioSessionIfNeeded()

        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }

        let u = AVSpeechUtterance(string: trimmed)
        u.rate = 0.50
        u.voice = AVSpeechSynthesisVoice(language: "en-AU")

        synth.speak(u)
    }

    // MARK: - Private

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true

        let session = AVAudioSession.sharedInstance()

        do {
            // ✅ Works on iPhone, iPad, Watch, all targets
            // Plays in silent mode and ducks other audio.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Optional debug
            // print("AudioSession configure failed:", error)
        }
    }
}
