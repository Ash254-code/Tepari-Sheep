import Foundation
import Combine
import UIKit

// =========================================================
// MARK: - Speech / Audio Triggers
// =========================================================

enum SpeechTrigger: String, CaseIterable, Identifiable, Codable {
    case sessionStart
    case newAnimal
    case scanSuccessful
    case rescanInSession
    case weightRecorded
    case notInDraft
    case gate1
    case gate2
    case gate3
    case gate4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessionStart:     return "Session Start"
        case .newAnimal:        return "New Animal"
        case .scanSuccessful:   return "Scan Successful"
        case .rescanInSession:  return "Re-Scan in Session"
        case .weightRecorded:   return "Weight Recorded"
        case .notInDraft:       return "Not in Draft"
        case .gate1:            return "Gate 1"
        case .gate2:            return "Gate 2"
        case .gate3:            return "Gate 3"
        case .gate4:            return "Gate 4"
        }
    }

    static func defaultPhrase(for t: SpeechTrigger) -> String {
        switch t {
        case .sessionStart:     return "Session started"
        case .newAnimal:        return "New animal"
        case .scanSuccessful:   return "Read OK"
        case .rescanInSession:  return "Re-scan"
        case .weightRecorded:   return "Weight recorded"
        case .notInDraft:       return "Not in draft"
        case .gate1:            return "Gate one"
        case .gate2:            return "Gate two"
        case .gate3:            return "Gate three"
        case .gate4:            return "Gate four"
        }
    }
}

struct SpeechTriggerSetting: Codable, Hashable {
    var enabled: Bool
    var phrase: String
}

// =========================================================
// MARK: - App Settings (persisted)
// =========================================================

@MainActor
final class AppSettings: ObservableObject {

    // =========================================================
    // MARK: - Persistence
    // =========================================================

    private enum Keys {
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let hapticStrength = "settings.hapticStrength"

        static let stabilitySource = "settings.stabilitySource"
        static let inferredStableWindowMs = "settings.inferredStableWindowMs"
        static let inferredStableMaxDeltaKg = "settings.inferredStableMaxDeltaKg"
        static let stableHoldMilliseconds = "settings.stableHoldMilliseconds"
        static let displaySmoothingAlpha = "settings.displaySmoothingAlpha"
        static let displaySnapJumpKg = "settings.displaySnapJumpKg"
        static let minRelockChangeKg = "settings.minRelockChangeKg"
        static let forceStable = "settings.forceStable"

        static let demoMode = "settings.demoMode"
        static let audioEnabled = "settings.audioEnabled"
        static let autoZeroOnSessionStart = "settings.autoZeroOnSessionStart"

        static let weightOKSpeakDelayMs = "settings.weightOKSpeakDelayMs"
        static let minSpeechGapMs = "settings.minSpeechGapMs"

        static let tcpHost = "settings.tcpHost"
        static let tcpPort = "settings.tcpPort"

        static let autoDraftEnabled = "settings.autoDraftEnabled"

        static let speechTriggersJSON = "settings.speechTriggersJSON"

        // User audio
        static let audioClipsJSON = "settings.audioClipsJSON"
        static let triggerAudioJSON = "settings.triggerAudioJSON"
        static let scopedOverridesJSON = "settings.scopedOverridesJSON"

        // ✅ Treatments library (global)
        static let treatmentLibraryJSON = "settings.treatmentLibraryJSON"
    }

    enum Defaults {
        static let hapticsEnabled: Bool = true
        static let hapticStrength: HapticStrength = .medium

        static let stabilitySource: StabilitySource = .scaleOrInferred
        static let inferredStableWindowMs: Int = 1200
        static let inferredStableMaxDeltaKg: Double = 0.40
        static let stableHoldMilliseconds: Int = 300
        static let displaySmoothingAlpha: Double = 0.75
        static let displaySnapJumpKg: Double = 2.0
        static let minRelockChangeKg: Double = 0.5
        static let forceStable: Bool = false

        static let demoMode: Bool = false
        static let audioEnabled: Bool = true
        static let autoZeroOnSessionStart: Bool = false

        static let weightOKSpeakDelayMs: Int = 650
        static let minSpeechGapMs: Int = 350

        static let tcpHost: String = "tepari.local"
        static let tcpPort: UInt16 = 2000

        static let autoDraftEnabled: Bool = true

        // ✅ Global treatments library defaults
        // NOTE: This requires TreatmentTemplate to be Codable (yours is in the step file).
        static let treatmentLibrary: [TreatmentTemplate] = []
    }

    private let ud = UserDefaults.standard
    private var isLoading = true

    init() {
        defer { isLoading = false }

        // Haptics
        hapticsEnabled = ud.object(forKey: Keys.hapticsEnabled) != nil
            ? ud.bool(forKey: Keys.hapticsEnabled)
            : Defaults.hapticsEnabled

        if let raw = ud.string(forKey: Keys.hapticStrength),
           let v = HapticStrength(rawValue: raw) {
            hapticStrength = v
        } else {
            hapticStrength = Defaults.hapticStrength
        }

        // Stability
        if let raw = ud.string(forKey: Keys.stabilitySource),
           let v = StabilitySource(rawValue: raw) {
            stabilitySource = v
        } else {
            stabilitySource = Defaults.stabilitySource
        }

        inferredStableWindowMs = ud.object(forKey: Keys.inferredStableWindowMs) != nil
            ? ud.integer(forKey: Keys.inferredStableWindowMs)
            : Defaults.inferredStableWindowMs

        inferredStableMaxDeltaKg = ud.object(forKey: Keys.inferredStableMaxDeltaKg) != nil
            ? ud.double(forKey: Keys.inferredStableMaxDeltaKg)
            : Defaults.inferredStableMaxDeltaKg

        stableHoldMilliseconds = ud.object(forKey: Keys.stableHoldMilliseconds) != nil
            ? ud.integer(forKey: Keys.stableHoldMilliseconds)
            : Defaults.stableHoldMilliseconds

        displaySmoothingAlpha = ud.object(forKey: Keys.displaySmoothingAlpha) != nil
            ? ud.double(forKey: Keys.displaySmoothingAlpha)
            : Defaults.displaySmoothingAlpha

        displaySnapJumpKg = ud.object(forKey: Keys.displaySnapJumpKg) != nil
            ? ud.double(forKey: Keys.displaySnapJumpKg)
            : Defaults.displaySnapJumpKg

        minRelockChangeKg = ud.object(forKey: Keys.minRelockChangeKg) != nil
            ? ud.double(forKey: Keys.minRelockChangeKg)
            : Defaults.minRelockChangeKg

        forceStable = ud.object(forKey: Keys.forceStable) != nil
            ? ud.bool(forKey: Keys.forceStable)
            : Defaults.forceStable

        // Demo / Audio / Weighing
        demoMode = ud.object(forKey: Keys.demoMode) != nil
            ? ud.bool(forKey: Keys.demoMode)
            : Defaults.demoMode

        audioEnabled = ud.object(forKey: Keys.audioEnabled) != nil
            ? ud.bool(forKey: Keys.audioEnabled)
            : Defaults.audioEnabled

        autoZeroOnSessionStart = ud.object(forKey: Keys.autoZeroOnSessionStart) != nil
            ? ud.bool(forKey: Keys.autoZeroOnSessionStart)
            : Defaults.autoZeroOnSessionStart

        // Speech timing
        weightOKSpeakDelayMs = ud.object(forKey: Keys.weightOKSpeakDelayMs) != nil
            ? ud.integer(forKey: Keys.weightOKSpeakDelayMs)
            : Defaults.weightOKSpeakDelayMs

        minSpeechGapMs = ud.object(forKey: Keys.minSpeechGapMs) != nil
            ? ud.integer(forKey: Keys.minSpeechGapMs)
            : Defaults.minSpeechGapMs

        // Connection
        tcpHost = ud.string(forKey: Keys.tcpHost) ?? Defaults.tcpHost

        if ud.object(forKey: Keys.tcpPort) != nil {
            tcpPort = UInt16(clamping: ud.integer(forKey: Keys.tcpPort))
        } else {
            tcpPort = Defaults.tcpPort
        }

        // Drafting
        autoDraftEnabled = ud.object(forKey: Keys.autoDraftEnabled) != nil
            ? ud.bool(forKey: Keys.autoDraftEnabled)
            : Defaults.autoDraftEnabled

        // Speech triggers
        if let data = ud.data(forKey: Keys.speechTriggersJSON),
           let decoded = decodeSpeechTriggers(from: data) {
            speechTriggers = decoded
        } else {
            speechTriggers = Self.defaultSpeechTriggers()
        }

        // ✅ User audio (explicit types to avoid Swift ambiguity)
        if let data = ud.data(forKey: Keys.audioClipsJSON) {
            audioClips = (try? JSONDecoder().decode([UserAudioClip].self, from: data)) ?? []
        } else {
            audioClips = []
        }

        if let data = ud.data(forKey: Keys.triggerAudioJSON) {
            // Supports both "raw map" and older "payload { map: ... }"
            triggerAudio =
                (try? JSONDecoder().decode([String: TriggerAudioConfig].self, from: data))
                ?? (try? JSONDecoder().decode(TriggerAudioPayload.self, from: data).map)
                ?? [:]
        } else {
            triggerAudio = [:]
        }

        if let data = ud.data(forKey: Keys.scopedOverridesJSON) {
            scopedOverrides = (try? JSONDecoder().decode([ScopedAudioOverride].self, from: data)) ?? []
        } else {
            scopedOverrides = []
        }

        // ✅ Treatments library (global)
        if let data = ud.data(forKey: Keys.treatmentLibraryJSON) {
            treatmentLibrary =
                (try? JSONDecoder().decode([TreatmentTemplate].self, from: data))
                ?? Defaults.treatmentLibrary
        } else {
            treatmentLibrary = Defaults.treatmentLibrary
        }

        sanitizeAudioAssignments()
    }

    // =========================================================
    // MARK: - Haptics
    // =========================================================

    enum HapticStrength: String, CaseIterable, Codable {
        case light, medium, heavy

        var label: String {
            switch self {
            case .light:  return "Light"
            case .medium: return "Medium"
            case .heavy:  return "Heavy"
            }
        }

        var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light:  return .light
            case .medium: return .medium
            case .heavy:  return .heavy
            }
        }
    }

    @Published var hapticsEnabled: Bool = Defaults.hapticsEnabled {
        didSet { guard !isLoading else { return }; ud.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    @Published var hapticStrength: HapticStrength = Defaults.hapticStrength {
        didSet { guard !isLoading else { return }; ud.set(hapticStrength.rawValue, forKey: Keys.hapticStrength) }
    }

    func impactTap() {
        guard hapticsEnabled else { return }
        let gen = UIImpactFeedbackGenerator(style: hapticStrength.uiStyle)
        gen.prepare()
        gen.impactOccurred()
    }

    // =========================================================
    // MARK: - Stability
    // =========================================================

    enum StabilitySource: String, CaseIterable, Codable, Identifiable {
        case scaleOnly, inferredOnly, scaleOrInferred
        var id: String { rawValue }
        var label: String {
            switch self {
            case .scaleOnly:       return "Scale only"
            case .inferredOnly:    return "Inferred only"
            case .scaleOrInferred: return "Scale OR inferred"
            }
        }
    }

    @Published var stabilitySource: StabilitySource = Defaults.stabilitySource {
        didSet { guard !isLoading else { return }; ud.set(stabilitySource.rawValue, forKey: Keys.stabilitySource) }
    }

    @Published var inferredStableWindowMs: Int = Defaults.inferredStableWindowMs {
        didSet { guard !isLoading else { return }; ud.set(inferredStableWindowMs, forKey: Keys.inferredStableWindowMs) }
    }

    @Published var inferredStableMaxDeltaKg: Double = Defaults.inferredStableMaxDeltaKg {
        didSet { guard !isLoading else { return }; ud.set(inferredStableMaxDeltaKg, forKey: Keys.inferredStableMaxDeltaKg) }
    }

    @Published var stableHoldMilliseconds: Int = Defaults.stableHoldMilliseconds {
        didSet { guard !isLoading else { return }; ud.set(stableHoldMilliseconds, forKey: Keys.stableHoldMilliseconds) }
    }

    @Published var displaySmoothingAlpha: Double = Defaults.displaySmoothingAlpha {
        didSet { guard !isLoading else { return }; ud.set(displaySmoothingAlpha, forKey: Keys.displaySmoothingAlpha) }
    }

    @Published var displaySnapJumpKg: Double = Defaults.displaySnapJumpKg {
        didSet { guard !isLoading else { return }; ud.set(displaySnapJumpKg, forKey: Keys.displaySnapJumpKg) }
    }

    @Published var minRelockChangeKg: Double = Defaults.minRelockChangeKg {
        didSet { guard !isLoading else { return }; ud.set(minRelockChangeKg, forKey: Keys.minRelockChangeKg) }
    }

    @Published var forceStable: Bool = Defaults.forceStable {
        didSet { guard !isLoading else { return }; ud.set(forceStable, forKey: Keys.forceStable) }
    }

    // =========================================================
    // MARK: - Demo / Audio / Weighing
    // =========================================================

    @Published var demoMode: Bool = Defaults.demoMode {
        didSet { guard !isLoading else { return }; ud.set(demoMode, forKey: Keys.demoMode) }
    }

    @Published var audioEnabled: Bool = Defaults.audioEnabled {
        didSet { guard !isLoading else { return }; ud.set(audioEnabled, forKey: Keys.audioEnabled) }
    }

    @Published var autoZeroOnSessionStart: Bool = Defaults.autoZeroOnSessionStart {
        didSet { guard !isLoading else { return }; ud.set(autoZeroOnSessionStart, forKey: Keys.autoZeroOnSessionStart) }
    }

    // =========================================================
    // MARK: - Speech timing
    // =========================================================

    @Published var weightOKSpeakDelayMs: Int = Defaults.weightOKSpeakDelayMs {
        didSet { guard !isLoading else { return }; ud.set(weightOKSpeakDelayMs, forKey: Keys.weightOKSpeakDelayMs) }
    }

    @Published var minSpeechGapMs: Int = Defaults.minSpeechGapMs {
        didSet { guard !isLoading else { return }; ud.set(minSpeechGapMs, forKey: Keys.minSpeechGapMs) }
    }

    // =========================================================
    // MARK: - Connection
    // =========================================================

    @Published var tcpHost: String = Defaults.tcpHost {
        didSet { guard !isLoading else { return }; ud.set(tcpHost, forKey: Keys.tcpHost) }
    }

    @Published var tcpPort: UInt16 = Defaults.tcpPort {
        didSet { guard !isLoading else { return }; ud.set(Int(tcpPort), forKey: Keys.tcpPort) }
    }

    // =========================================================
    // MARK: - Drafting
    // =========================================================

    @Published var autoDraftEnabled: Bool = Defaults.autoDraftEnabled {
        didSet { guard !isLoading else { return }; ud.set(autoDraftEnabled, forKey: Keys.autoDraftEnabled) }
    }

    // =========================================================
    // MARK: - Treatments library (Settings)
    // =========================================================

    @Published var treatmentLibrary: [TreatmentTemplate] = [] {
        didSet {
            guard !isLoading else { return }
            if let data = try? JSONEncoder().encode(treatmentLibrary) {
                ud.set(data, forKey: Keys.treatmentLibraryJSON)
            }
        }
    }

    // =========================================================
    // MARK: - Speech triggers
    // =========================================================

    @Published var speechTriggers: [SpeechTrigger: SpeechTriggerSetting] = [:] {
        didSet {
            guard !isLoading else { return }
            if let data = encodeSpeechTriggers(speechTriggers) {
                ud.set(data, forKey: Keys.speechTriggersJSON)
            }
        }
    }

    func speechSetting(for trigger: SpeechTrigger) -> SpeechTriggerSetting {
        speechTriggers[trigger] ?? SpeechTriggerSetting(
            enabled: true,
            phrase: SpeechTrigger.defaultPhrase(for: trigger)
        )
    }

    func setSpeech(_ trigger: SpeechTrigger, enabled: Bool? = nil, phrase: String? = nil) {
        var cur = speechSetting(for: trigger)
        if let enabled { cur.enabled = enabled }
        if let phrase { cur.phrase = phrase }
        speechTriggers[trigger] = cur
    }

    func resetSpeechTriggersToDefaults() {
        speechTriggers = Self.defaultSpeechTriggers()
    }

    func phraseToSpeak(for trigger: SpeechTrigger) -> String? {
        guard audioEnabled else { return nil }
        let s = speechSetting(for: trigger)
        guard s.enabled else { return nil }
        let text = s.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func defaultSpeechTriggers() -> [SpeechTrigger: SpeechTriggerSetting] {
        var out: [SpeechTrigger: SpeechTriggerSetting] = [:]
        for t in SpeechTrigger.allCases {
            out[t] = SpeechTriggerSetting(enabled: true, phrase: SpeechTrigger.defaultPhrase(for: t))
        }
        return out
    }

    // =========================================================
    // MARK: - User audio library + per-trigger output
    // =========================================================

    @Published var audioClips: [UserAudioClip] = [] {
        didSet {
            guard !isLoading else { return }
            if let data = try? JSONEncoder().encode(audioClips) {
                ud.set(data, forKey: Keys.audioClipsJSON)
            }
            sanitizeAudioAssignments()
        }
    }

    /// Key = SpeechTrigger.rawValue
    @Published var triggerAudio: [String: TriggerAudioConfig] = [:] {
        didSet {
            guard !isLoading else { return }
            // store as payload for forward compatibility
            let payload = TriggerAudioPayload(map: triggerAudio)
            if let data = try? JSONEncoder().encode(payload) {
                ud.set(data, forKey: Keys.triggerAudioJSON)
            }
            sanitizeAudioAssignments()
        }
    }

    @Published var scopedOverrides: [ScopedAudioOverride] = [] {
        didSet {
            guard !isLoading else { return }
            if let data = try? JSONEncoder().encode(scopedOverrides) {
                ud.set(data, forKey: Keys.scopedOverridesJSON)
            }
            sanitizeAudioAssignments()
        }
    }

    func config(for trigger: SpeechTrigger) -> TriggerAudioConfig {
        triggerAudio[trigger.rawValue] ?? .default
    }

    func setConfig(_ trigger: SpeechTrigger, _ config: TriggerAudioConfig) {
        triggerAudio[trigger.rawValue] = config
    }

    func clip(for id: UUID?) -> UserAudioClip? {
        guard let id else { return nil }
        return audioClips.first { $0.id == id }
    }

    func resolvedConfig(
        for trigger: SpeechTrigger,
        mobName: String? = nil,
        className: String? = nil
    ) -> TriggerAudioConfig {
        if let mobName = mobName?.trimmingCharacters(in: .whitespacesAndNewlines), !mobName.isEmpty {
            if let ov = scopedOverrides.first(where: {
                $0.scope == .mob &&
                $0.key.caseInsensitiveCompare(mobName) == .orderedSame &&
                $0.triggerRaw == trigger.rawValue
            }) { return ov.config }
        }

        if let className = className?.trimmingCharacters(in: .whitespacesAndNewlines), !className.isEmpty {
            if let ov = scopedOverrides.first(where: {
                $0.scope == .animalClass &&
                $0.key.caseInsensitiveCompare(className) == .orderedSame &&
                $0.triggerRaw == trigger.rawValue
            }) { return ov.config }
        }

        return config(for: trigger)
    }

    private func sanitizeAudioAssignments() {
        let validIDs = Set(audioClips.map { $0.id })

        // triggerAudio
        var newTriggerAudio = triggerAudio
        var didChange = false

        for (k, cfg) in triggerAudio where cfg.mode == .clip {
            // ✅ Allow nil clipID (user hasn’t chosen a clip yet)
            if let id = cfg.clipID {
                if !validIDs.contains(id) {
                    newTriggerAudio[k] = .default
                    didChange = true
                }
            }
        }

        // scopedOverrides
        var newOverrides: [ScopedAudioOverride] = []
        newOverrides.reserveCapacity(scopedOverrides.count)

        for ov in scopedOverrides {
            var fixed = ov
            if fixed.config.mode == .clip {
                // ✅ Allow nil clipID here too
                if let id = fixed.config.clipID {
                    if !validIDs.contains(id) {
                        fixed.config = .default
                        didChange = true
                    }
                }
            }
            newOverrides.append(fixed)
        }

        if didChange {
            let wasLoading = isLoading
            isLoading = true
            triggerAudio = newTriggerAudio
            scopedOverrides = newOverrides
            isLoading = wasLoading

            if !isLoading {
                if let d = try? JSONEncoder().encode(triggerAudio) {
                    ud.set(d, forKey: Keys.triggerAudioJSON)
                }
                if let d = try? JSONEncoder().encode(scopedOverrides) {
                    ud.set(d, forKey: Keys.scopedOverridesJSON)
                }
            }
        }
    }

    // =========================================================
    // MARK: - Speech trigger persistence helpers
    // =========================================================

    private struct SpeechTriggersPayload: Codable {
        var map: [String: SpeechTriggerSetting]
    }

    private func encodeSpeechTriggers(_ triggers: [SpeechTrigger: SpeechTriggerSetting]) -> Data? {
        var m: [String: SpeechTriggerSetting] = [:]
        for (k, v) in triggers { m[k.rawValue] = v }
        return try? JSONEncoder().encode(SpeechTriggersPayload(map: m))
    }

    private func decodeSpeechTriggers(from data: Data) -> [SpeechTrigger: SpeechTriggerSetting]? {
        guard let payload = try? JSONDecoder().decode(SpeechTriggersPayload.self, from: data) else {
            return nil
        }
        var out: [SpeechTrigger: SpeechTriggerSetting] = [:]
        for (raw, setting) in payload.map {
            if let t = SpeechTrigger(rawValue: raw) { out[t] = setting }
        }
        // Fill gaps with defaults
        let defaults = Self.defaultSpeechTriggers()
        for (k, v) in defaults where out[k] == nil { out[k] = v }
        return out
    }

    // =========================================================
    // MARK: - Payload for trigger audio (forward/back compat)
    // =========================================================

    private struct TriggerAudioPayload: Codable {
        var map: [String: TriggerAudioConfig]
    }
}

// =========================================================
// MARK: - UInt16 clamping helper
// =========================================================

private extension UInt16 {
    init(clamping value: Int) {
        if value < 0 { self = 0; return }
        if value > Int(UInt16.max) { self = UInt16.max; return }
        self = UInt16(value)
    }
}
