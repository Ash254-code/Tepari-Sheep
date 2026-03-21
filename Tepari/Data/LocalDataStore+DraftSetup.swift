import Foundation

extension LocalDataStore {

    func draftSetup(for sessionID: UUID) -> SessionDraftSetup {
        sessionDraftSetup[sessionID] ?? SessionDraftSetup()
    }

    func setDraftSetup(_ setup: SessionDraftSetup, for sessionID: UUID) {
        sessionDraftSetup[sessionID] = normalizedDraftSetup(setup)
        scheduleSave()
    }

    func clearDraftSetup(for sessionID: UUID) {
        sessionDraftSetup.removeValue(forKey: sessionID)
        scheduleSave()
    }

    private func normalizedDraftSetup(_ setup: SessionDraftSetup) -> SessionDraftSetup {
        var copy = setup

        copy.weightRules = copy.weightRules.map {
            SessionWeightDraftRule(
                id: $0.id,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                minWeight: $0.minWeight,
                maxWeight: $0.maxWeight,
                draftPositionRaw: $0.draftPositionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        copy.mobRules = copy.mobRules.map {
            SessionMobDraftRule(
                id: $0.id,
                mobID: $0.mobID,
                mobName: $0.mobName.trimmingCharacters(in: .whitespacesAndNewlines),
                draftPositionRaw: $0.draftPositionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        copy.classRules = copy.classRules.map {
            SessionClassDraftRule(
                id: $0.id,
                animalClassRaw: $0.animalClassRaw.trimmingCharacters(in: .whitespacesAndNewlines),
                draftPositionRaw: $0.draftPositionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return copy
    }
}
