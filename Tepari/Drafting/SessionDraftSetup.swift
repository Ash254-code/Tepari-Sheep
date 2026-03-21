import Foundation

enum DraftSetupMode: String, Codable, Hashable {
    case off
    case byWeight
    case byMob
    case byClass
}

enum DraftFallbackChoice: String, Codable, Hashable {
    case keepCurrent
    case left
    case right
}

struct SessionWeightDraftRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var minWeight: Double?
    var maxWeight: Double?
    var draftPositionRaw: String

    init(
        id: UUID = UUID(),
        name: String,
        minWeight: Double? = nil,
        maxWeight: Double? = nil,
        draftPositionRaw: String
    ) {
        self.id = id
        self.name = name
        self.minWeight = minWeight
        self.maxWeight = maxWeight
        self.draftPositionRaw = draftPositionRaw
    }
}

struct SessionMobDraftRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var mobID: UUID
    var mobName: String
    var draftPositionRaw: String

    init(
        id: UUID = UUID(),
        mobID: UUID,
        mobName: String,
        draftPositionRaw: String
    ) {
        self.id = id
        self.mobID = mobID
        self.mobName = mobName
        self.draftPositionRaw = draftPositionRaw
    }
}

struct SessionClassDraftRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var animalClassRaw: String
    var draftPositionRaw: String

    init(
        id: UUID = UUID(),
        animalClassRaw: String,
        draftPositionRaw: String
    ) {
        self.id = id
        self.animalClassRaw = animalClassRaw
        self.draftPositionRaw = draftPositionRaw
    }
}

struct SessionDraftSetup: Codable, Hashable {
    var mode: DraftSetupMode
    var weightRules: [SessionWeightDraftRule]
    var mobRules: [SessionMobDraftRule]
    var classRules: [SessionClassDraftRule]
    var fallback: DraftFallbackChoice
    var isEnabled: Bool

    init(
        mode: DraftSetupMode = .off,
        weightRules: [SessionWeightDraftRule] = [],
        mobRules: [SessionMobDraftRule] = [],
        classRules: [SessionClassDraftRule] = [],
        fallback: DraftFallbackChoice = .keepCurrent,
        isEnabled: Bool = false
    ) {
        self.mode = mode
        self.weightRules = weightRules
        self.mobRules = mobRules
        self.classRules = classRules
        self.fallback = fallback
        self.isEnabled = isEnabled
    }
}
