import Foundation

@MainActor
extension LocalDataStore {

    // =========================================================
    // MARK: - Session Name Generation
    // =========================================================

    private func orderedSessionTypeText(from raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var parts: [String] = []
        if text.contains("draft") { parts.append("Draft") }
        if text.contains("weigh") { parts.append("Weigh") }
        if text.contains("treat") { parts.append("Treat") }

        return parts.isEmpty ? "General" : parts.joined(separator: "/")
    }

    private func orderedSessionTypeText(from sessionTypes: Set<SetupSessionType>) -> String {
        var parts: [String] = []
        if sessionTypes.contains(.draft) { parts.append("Draft") }
        if sessionTypes.contains(.weigh) { parts.append("Weigh") }
        if sessionTypes.contains(.treatment) { parts.append("Treat") }
        return parts.isEmpty ? "General" : parts.joined(separator: "/")
    }

    func canonicalSessionName(
        farmName: String,
        sessionTypes: Set<SetupSessionType>,
        mobName: String?,
        animalCount: Int
    ) -> String {
        let farm = farmName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFarm = farm.isEmpty ? "Untitled" : farm

        let typeText = orderedSessionTypeText(from: sessionTypes)

        let mob = (mobName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMob = mob.isEmpty ? "—" : mob

        let count = max(0, animalCount)

        return "\(safeFarm) - \(typeText) - \(safeMob) - \(count)"
    }

    /// Backwards-compatible helper.
    /// New format:
    /// Farm - Session Type - Mob - Total Animals
    func makeUniqueSessionName(
        farmName: String,
        kind: Session.Kind,
        at: Date = Date()
    ) -> String {
        let farm = farmName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFarm = farm.isEmpty ? "Untitled" : farm

        let typeText: String = {
            switch kind {
            case .transfer:
                return "Transfer"
            case .sale:
                return "Sale"
            case .general:
                return "General"
            }
        }()

        let mobText = "—"
        let animalCount = 0

        let base = "\(safeFarm) - \(typeText) - \(mobText) - \(animalCount)"
        return uniqueSessionName(base)
    }

    /// Preferred helper for final display rule:
    /// Farm - Draft/Weigh/Treat - Mob - Total Animals Scanned
    ///
    /// Notes:
    /// - yardName is intentionally ignored now
    /// - Scan is excluded
    /// - count is always included, including 0
    func makeUniqueSessionName(
        typeLabel: String,
        farmName: String,
        yardName: String?,
        mobName: String?,
        animalCount: Int?,
        at: Date = Date()
    ) -> String {
        let farm = farmName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFarm = farm.isEmpty ? "Untitled" : farm

        let typeText = orderedSessionTypeText(from: typeLabel)

        let mob = (mobName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMob = mob.isEmpty ? "—" : mob

        let count = max(0, animalCount ?? 0)

        let base = "\(safeFarm) - \(typeText) - \(safeMob) - \(count)"
        return uniqueSessionName(base)
    }

    // =========================================================
    // MARK: - Persist
    // =========================================================

    /// SessionSetupView expects this helper.
    /// This creates/updates the Session row in History using the wizard’s sessionID.
    func setSessionName(sessionID: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "Untitled" : trimmed

        let farmID = sessionFarmID[sessionID]
        let mobID = sessionMobID[sessionID]

        _ = ensureSession(
            id: sessionID,
            name: safe,
            farmID: farmID,
            mobID: mobID
        )
    }
}
