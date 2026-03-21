import AVFoundation

final class SpeechAnnouncer: NSObject {

    private let synth = AVSpeechSynthesizer()
    private var didConfigureSession = false
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, completion: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?()
            return
        }

        configureAudioSessionIfNeeded()
        self.completion = completion

        // 🔧 FIX: Ensure correct speaking order
        let formatted = formatDraftPhrase(trimmed)

        let u = AVSpeechUtterance(string: formatted)
        u.rate = 0.50
        u.voice = AVSpeechSynthesisVoice(language: "en-AU")

        synth.speak(u)
    }

    // MARK: - Phrase formatting fix
    private func formatDraftPhrase(_ text: String) -> String {
        let lower = text.lowercased()

        // If phrase contains both "gate" and "weight", enforce correct order
        if lower.contains("gate"), lower.contains("weight") {

            // Extract gate number if present
            let gateNumber = extractGateNumber(from: text)

            if lower.contains("ok") || lower.contains("good") {
                if let gate = gateNumber {
                    return "Weight OK. Gate \(gate)"
                } else {
                    return "Weight OK"
                }
            }

            // Fallback generic reorder
            if let gate = gateNumber {
                return "Weight recorded. Gate \(gate)"
            } else {
                return text
            }
        }

        return text
    }

    private func extractGateNumber(from text: String) -> Int? {
        let pattern = #"gate\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsText = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)),
               match.numberOfRanges > 1 {
                let numberString = nsText.substring(with: match.range(at: 1))
                return Int(numberString)
            }
        }
        return nil
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Optional debug
        }
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let callback = completion
        completion = nil
        callback?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let callback = completion
        completion = nil
        callback?()
    }
}
