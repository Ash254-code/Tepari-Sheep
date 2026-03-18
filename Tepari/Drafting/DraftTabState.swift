import Foundation

enum DraftModeType: String, CaseIterable, Codable {
    case weight = "Weight"
    case mob = "Mob"
    case animalClass = "Class"
    case file = "File"
    case pregHistory = "Preg history"
}

struct DraftDashboardGateSummary: Identifiable, Codable, Hashable {
    var id: Int { gate }
    let gate: Int
    let count: Int
    let averageWeightKg: Double?
    let minWeightKg: Double?
    let maxWeightKg: Double?
}

struct DraftSetupState: Codable, Hashable {
    let selectedMode: DraftModeType?
    let isConfigured: Bool
    let isActive: Bool
    let summaryText: String
    let isExpanded: Bool
}

struct DraftDashboardState: Codable, Hashable {
    let activeModeTitle: String
    let totalDrafted: Int
    let gateSummaries: [DraftDashboardGateSummary]
    let hasLiveData: Bool
}

struct DraftAdvancedState: Codable, Hashable {
    let isAvailable: Bool
    let gateMappingSummary: [String]
    let ruleSummary: [String]
}

struct DraftTabState: Codable, Hashable {
    let setup: DraftSetupState
    let dashboard: DraftDashboardState
    let advanced: DraftAdvancedState
}
