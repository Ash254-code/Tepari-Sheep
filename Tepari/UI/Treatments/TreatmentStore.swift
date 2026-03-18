import Foundation
import Combine

@MainActor
final class TreatmentStore: ObservableObject {

    @Published var treatments: [Treatment] = [] {
        didSet {
            save()
        }
    }

    private let storageKey = "tepari.treatments.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    // MARK: - Persistence

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            treatments = Self.defaultTreatments
            return
        }

        do {
            treatments = try decoder.decode([Treatment].self, from: data)
            sortTreatments()
        } catch {
            print("TreatmentStore load failed: \(error)")
            treatments = Self.defaultTreatments
        }
    }

    func save() {
        do {
            let data = try encoder.encode(treatments)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("TreatmentStore save failed: \(error)")
        }
    }

    func resetToDefaults() {
        treatments = Self.defaultTreatments
        sortTreatments()
    }

    // MARK: - CRUD

    func add(_ treatment: Treatment) {
        treatments.append(treatment)
        sortTreatments()
    }

    func update(_ treatment: Treatment) {
        guard let index = treatments.firstIndex(where: { $0.id == treatment.id }) else { return }
        treatments[index] = treatment
        sortTreatments()
    }

    func upsert(_ treatment: Treatment) {
        if treatments.contains(where: { $0.id == treatment.id }) {
            update(treatment)
        } else {
            add(treatment)
        }
    }

    func delete(_ treatment: Treatment) {
        treatments.removeAll { $0.id == treatment.id }
    }

    func delete(at offsets: IndexSet, from source: [Treatment]) {
        let ids = offsets.map { source[$0].id }
        treatments.removeAll { ids.contains($0.id) }
    }

    func setEnabled(_ isEnabled: Bool, for treatment: Treatment) {
        guard let index = treatments.firstIndex(where: { $0.id == treatment.id }) else { return }
        treatments[index].isEnabled = isEnabled
        sortTreatments()
    }

    func toggleEnabled(for treatment: Treatment) {
        guard let index = treatments.firstIndex(where: { $0.id == treatment.id }) else { return }
        treatments[index].isEnabled.toggle()
        sortTreatments()
    }

    // MARK: - Queries

    var enabledTreatments: [Treatment] {
        treatments.filter(\.isEnabled)
    }

    var disabledTreatments: [Treatment] {
        treatments.filter { !$0.isEnabled }
    }

    func treatment(id: UUID) -> Treatment? {
        treatments.first { $0.id == id }
    }

    // MARK: - Sorting

    private func sortTreatments() {
        treatments.sort {
            if $0.isEnabled != $1.isEnabled {
                return $0.isEnabled && !$1.isEnabled
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Defaults

extension TreatmentStore {
    static let defaultTreatments: [Treatment] = [
        Treatment(
            name: "Wormer A",
            unit: "mL",
            doseAmount: 2,
            doseWeightKg: 10,
            minimumDose: nil,
            maximumDose: nil,
            doseStep: 0.1,
            requiresStableWeight: true,
            isEnabled: true
        ),
        Treatment(
            name: "Drench B",
            unit: "mL",
            doseAmount: 1,
            doseWeightKg: 5,
            minimumDose: nil,
            maximumDose: nil,
            doseStep: 0.1,
            requiresStableWeight: true,
            isEnabled: true
        )
    ]
}
