import SwiftUI
import Combine

final class AnimalDataViewModel: ObservableObject {

    enum SortKey: String, CaseIterable, Identifiable {
        case updatedAt = "Last Scan"
        case eid = "EID"
        case lambs = "Preg / Lambs"
        case fleece = "Fleece Weight"
        case staple = "Staple Length"

        var id: String { rawValue }
    }

    struct AnimalRowModel: Identifiable, Hashable {
        let id: UUID
        let animal: LocalDataStore.AnimalProfile
        let farmName: String
        let sexName: String
        let className: String
        let mobName: String
        let mobColorHex: String?
        let yearText: String
        let totalLambsText: String
        let lastScanText: String
        let searchBlob: String
        let pregValue: Int?
    }

    struct DerivedData {
        var rankedRows: [AnimalRowModel]
        var filteredIDs: Set<UUID>
        var totalMatchingCount: Int
        var visibleCount: Int

        static let empty = DerivedData(
            rankedRows: [],
            filteredIDs: [],
            totalMatchingCount: 0,
            visibleCount: 0
        )
    }

    @Published var selectedFarmIDs: Set<UUID> = []
    @Published var selectedSexes: Set<String> = []
    @Published var selectedMobNames: Set<String> = []
    @Published var selectedClasses: Set<String> = []
    @Published var searchText: String = ""
    @Published var sortKey: SortKey = .updatedAt
    @Published var sortAscending: Bool = false
    @Published var selectedAnimalIDs: Set<UUID> = []
    @Published var derived: DerivedData = .empty

    private var store: LocalDataStore?
    private var computeTask: Task<Void, Never>? = nil
    private var searchDebounceTask: Task<Void, Never>? = nil

    init() {}

    func bind(store: LocalDataStore) {
        self.store = store
        recomputeDerivedData()
    }

    func toggleSex(_ sex: String) {
        let key = Self.normalized(sex)
        if selectedSexes.contains(key) {
            selectedSexes.remove(key)
        } else {
            selectedSexes.insert(key)
        }
        recomputeDerivedData()
    }

    func updateSearchText(_ newValue: String) {
        searchDebounceTask?.cancel()

        let captured = newValue

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            self.searchText = captured
            self.recomputeDerivedData()
        }
    }

    func toggleSelection(_ id: UUID) {
        if selectedAnimalIDs.contains(id) {
            selectedAnimalIDs.remove(id)
        } else {
            selectedAnimalIDs.insert(id)
        }
    }

    func selectAllFiltered() {
        selectedAnimalIDs.formUnion(derived.filteredIDs)
    }

    func clearFilteredSelection() {
        selectedAnimalIDs.subtract(derived.filteredIDs)
    }

    func toggleFarm(_ id: UUID) {
        if selectedFarmIDs.contains(id) {
            selectedFarmIDs.remove(id)
        } else {
            selectedFarmIDs.insert(id)
        }
    }

    func toggleMob(_ name: String) {
        let key = Self.normalized(name)
        if selectedMobNames.contains(key) {
            selectedMobNames.remove(key)
        } else {
            selectedMobNames.insert(key)
        }
        recomputeDerivedData()
    }

    func toggleClass(_ name: String) {
        let key = Self.normalized(name)
        if selectedClasses.contains(key) {
            selectedClasses.remove(key)
        } else {
            selectedClasses.insert(key)
        }
        recomputeDerivedData()
    }

    func clearAllFilters() {
        selectedFarmIDs.removeAll()
        selectedSexes.removeAll()
        selectedMobNames.removeAll()
        selectedClasses.removeAll()
    }

    var selectedCountInFiltered: Int {
        selectedAnimalIDs.intersection(derived.filteredIDs).count
    }

    var allFilteredSelected: Bool {
        !derived.filteredIDs.isEmpty &&
        selectedCountInFiltered == derived.filteredIDs.count
    }

    func recomputeDerivedData() {
        guard let store else { return }

        computeTask?.cancel()

        let currentSearch = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let selectedFarmsSnapshot = selectedFarmIDs
        let selectedSexesSnapshot = selectedSexes
        let selectedMobsSnapshot = selectedMobNames
        let selectedClassesSnapshot = selectedClasses
        let sortKeySnapshot = sortKey
        let sortAscendingSnapshot = sortAscending

        let animals = store.animals
        let farms = store.farms
        let mobs = store.mobs

        let farmByID = Dictionary(uniqueKeysWithValues: farms.map { ($0.id, $0) })
        let mobByID = Dictionary(uniqueKeysWithValues: mobs.map { ($0.id, $0) })

        let lambsByAnimal: [String: Int] = Dictionary(
            uniqueKeysWithValues: animals.map { animal in
                (
                    Self.animalKey(farmID: animal.farmID, eidRaw: animal.eidRaw),
                    store.totalLambsCached(farmID: animal.farmID, eidRaw: animal.eidRaw)
                )
            }
        )

        let pregByAnimal: [String: Int?] = Dictionary(
            uniqueKeysWithValues: animals.map { animal in
                (
                    Self.animalKey(farmID: animal.farmID, eidRaw: animal.eidRaw),
                    store.latestPregnancyEvent(
                        farmID: animal.farmID,
                        eidRaw: animal.eidRaw
                    )?.int1
                )
            }
        )

        computeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            var rows: [AnimalRowModel] = []
            rows.reserveCapacity(animals.count)

            for animal in animals {
                if Task.isCancelled { return }

                if !selectedFarmsSnapshot.isEmpty,
                   !selectedFarmsSnapshot.contains(animal.farmID) {
                    continue
                }

                let farmName = farmByID[animal.farmID]?.name ?? "Unknown Farm"

                let sexName: String = {
                    let raw = animal.sex?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return raw.isEmpty ? "Sex —" : raw
                }()

                let mobName: String = {
                    let raw = animal.mobID.flatMap { mobByID[$0]?.name } ?? ""
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "No Mob" : trimmed
                }()

                let className: String = {
                    let raw = animal.klass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return raw.isEmpty ? "No Class" : raw
                }()

                if !selectedSexesSnapshot.isEmpty,
                   !selectedSexesSnapshot.contains(Self.normalized(sexName)) {
                    continue
                }

                if !selectedMobsSnapshot.isEmpty,
                   !selectedMobsSnapshot.contains(Self.normalized(mobName)) {
                    continue
                }

                if !selectedClassesSnapshot.isEmpty,
                   !selectedClassesSnapshot.contains(Self.normalized(className)) {
                    continue
                }

                let searchBlob = [
                    animal.eidRaw,
                    animal.comments ?? "",
                    sexName,
                    className,
                    mobName,
                    farmName
                ]
                .joined(separator: " ")
                .lowercased()

                if !currentSearch.isEmpty && !searchBlob.contains(currentSearch) {
                    continue
                }

                let key = Self.animalKey(farmID: animal.farmID, eidRaw: animal.eidRaw)
                let lambs = lambsByAnimal[key] ?? 0
                let pregValue = pregByAnimal[key] ?? nil

                rows.append(
                    AnimalRowModel(
                        id: animal.id,
                        animal: animal,
                        farmName: farmName,
                        sexName: sexName,
                        className: className,
                        mobName: mobName,
                        mobColorHex: animal.mobID.flatMap { mobByID[$0]?.colorHex },
                        yearText: animal.birthYear.map { "Year \($0)" } ?? "Year —",
                        totalLambsText: "Lambs \(lambs)",
                        lastScanText: "Last scan \(animal.updatedAt.formatted(date: .abbreviated, time: .omitted))",
                        searchBlob: searchBlob,
                        pregValue: pregValue
                    )
                )
            }

            let sorted = Self.sortRows(
                rows,
                key: sortKeySnapshot,
                ascending: sortAscendingSnapshot
            )

            let visible = Array(sorted.prefix(200))
            let ids = Set(sorted.map(\.id))

            await MainActor.run {
                self.selectedAnimalIDs = self.selectedAnimalIDs.intersection(ids)
                self.derived = DerivedData(
                    rankedRows: visible,
                    filteredIDs: ids,
                    totalMatchingCount: sorted.count,
                    visibleCount: visible.count
                )
            }
        }
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func animalKey(farmID: UUID, eidRaw: String) -> String {
        "\(farmID.uuidString)|\(eidRaw.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    nonisolated private static func sortRows(
        _ rows: [AnimalRowModel],
        key: SortKey,
        ascending: Bool
    ) -> [AnimalRowModel] {
        func cmpD(_ a: Double?, _ b: Double?) -> ComparisonResult {
            switch (a, b) {
            case let (x?, y?):
                if x == y { return .orderedSame }
                return x < y ? .orderedAscending : .orderedDescending
            case (nil, nil):
                return .orderedSame
            case (nil, _?):
                return .orderedAscending
            case (_?, nil):
                return .orderedDescending
            }
        }

        func cmpI(_ a: Int?, _ b: Int?) -> ComparisonResult {
            switch (a, b) {
            case let (x?, y?):
                if x == y { return .orderedSame }
                return x < y ? .orderedAscending : .orderedDescending
            case (nil, nil):
                return .orderedSame
            case (nil, _?):
                return .orderedAscending
            case (_?, nil):
                return .orderedDescending
            }
        }

        return rows.sorted { a, b in
            let result: ComparisonResult

            switch key {
            case .updatedAt:
                let lhs = a.animal.updatedAt
                let rhs = b.animal.updatedAt
                result = lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)

            case .eid:
                result = a.animal.eidRaw.localizedStandardCompare(b.animal.eidRaw)

            case .lambs:
                result = cmpI(a.pregValue, b.pregValue)

            case .fleece:
                result = cmpD(a.animal.fleeceWeightKg, b.animal.fleeceWeightKg)

            case .staple:
                result = cmpD(a.animal.stapleLengthMm, b.animal.stapleLengthMm)
            }

            if result == .orderedSame {
                return a.animal.eidRaw < b.animal.eidRaw
            }

            return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }
}
