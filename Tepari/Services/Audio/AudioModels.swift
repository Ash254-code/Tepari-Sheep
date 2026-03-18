import Foundation

// =====================================================
// MARK: - User audio models
// =====================================================

struct UserAudioClip: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String            // display name in UI
    var storedFileName: String  // file name in Documents/AudioClips/

    init(id: UUID = UUID(), name: String, storedFileName: String) {
        self.id = id
        self.name = name
        self.storedFileName = storedFileName
    }
}

enum AudioOutputMode: String, Codable, CaseIterable, Identifiable {
    case speech
    case clip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speech: return "Speech"
        case .clip:   return "Clip"
        }
    }
}

struct TriggerAudioConfig: Codable, Hashable {
    var mode: AudioOutputMode
    var clipID: UUID? // used when mode == .clip

    static let `default` = TriggerAudioConfig(mode: .speech, clipID: nil)
}

struct ScopedAudioOverride: Codable, Hashable, Identifiable {
    let id: UUID
    var scope: Scope
    var key: String           // mob name OR class name
    var triggerRaw: String    // SpeechTrigger.rawValue
    var config: TriggerAudioConfig

    enum Scope: String, Codable, CaseIterable, Identifiable {
        case mob
        case animalClass

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mob:         return "Mob"
            case .animalClass: return "Class"
            }
        }
    }

    init(
        id: UUID = UUID(),
        scope: Scope,
        key: String,
        triggerRaw: String,
        config: TriggerAudioConfig
    ) {
        self.id = id
        self.scope = scope
        self.key = key
        self.triggerRaw = triggerRaw
        self.config = config
    }
}
