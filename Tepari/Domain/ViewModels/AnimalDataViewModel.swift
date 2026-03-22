import SwiftUI
import Combine

final class AnimalDataViewModel: ObservableObject {

    // MARK: - Sort

    enum SortKey: String, CaseIterable, Identifiable {
        case updatedAt = "Last Scan"
        case eid = "EID"
        case lambs = "Preg / Lambs"
        case fleece = "Fleece Weight"
        case staple = "Staple Length"

        var id: String { rawValue }
    }

    // MARK: - Models

    struct AnimalRowModel: Identifiable, Hashable {
        let id: UUID
        let animal: LocalDataStore.AnimalProfile
        let farmName: String
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

    // MARK: - State

    @Published var selectedFarmID: UUID? = nil
    @Published var filterMobName: String? = nil
    @Published var filterClass: String? = nil
    @Published var searchText: String = ""
    @Published var sortKey: SortKey = .updatedAt
    @Published var sortAscending: Bool = false
    @Published var selectedAnimalIDs: Set<UUID> = []
    @Published var derived: DerivedData = .empty

    private var store: LocalDataStore?
    private var computeTask: Task<Void, Never>? = nil
    private var searchDebounceTask: Task<Void, Never>? = nil

    // MARK: - Init

    init() {}

    func bind(store: LocalDataStore) {
        self.store = store
        recomputeDerivedData()
    }

    // MARK: - Search (Debounced)

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

    // MARK: - Selection (FAST - NO RECOMPUTE)

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

    var selectedCountInFiltered: Int {
        selectedAnimalIDs.intersection(derived.filteredIDs).count
    }

    var allFilteredSelected: Bool {
        !derived.filteredIDs.isEmpty &&
        selectedCountInFiltered == derived.filteredIDs.count
    }

    // MARK: - Main Compute (BACKGROUND)

    func recomputeDerivedData() {
        guard let store else { return }

        computeTask?.cancel()

        let currentSearch = searchText.lowercased()
        let selectedFarm = selectedFarmID
        let selectedClass = filterClass
        let animals = store.animals
        let farms = store.farms
        let mobs = store.mobs

        computeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let farmByID = Dictionary(uniqueKeysWithValues: farms.map { ($0.id, $0) })
            let mobByID = Dictionary(uniqueKeysWithValues: mobs.map { ($0.id, $0) })

            var rows: [AnimalRowModel] = []

            for animal in animals {

                if Task.isCancelled { return }

                if let selectedFarm, animal.farmID != selectedFarm {
                    continue
                }

                let farmName = farmByID[animal.farmID]?.name ?? "Unknown"
                let mobName = animal.mobID.flatMap { mobByID[$0]?.name } ?? "No Mob"
                let className = animal.klass ?? "No Class"

                if let selectedClass,
                   className.caseInsensitiveCompare(selectedClass) != .orderedSame {
                    continue
                }

                let searchBlob = [
                    animal.eidRaw,
                    className,
                    mobName,
                    farmName
                ]
                .joined(separator: " ")
                .lowercased()

                if !currentSearch.isEmpty && !searchBlob.contains(currentSearch) {
                    continue
                }

                let lambs = store.totalLambsCached(
                    farmID: animal.farmID,
                    eidRaw: animal.eidRaw
                )

                let row = AnimalRowModel(
                    id: animal.id,
                    animal: animal,
                    farmName: farmName,
                    className: className,
                    mobName: mobName,
                    mobColorHex: animal.mobID.flatMap { mobByID[$0]?.colorHex },
                    yearText: animal.birthYear.map { "Year \($0)" } ?? "Year —",
                    totalLambsText: "Lambs \(lambs)",
                    lastScanText: "Last scan \(animal.updatedAt.formatted(date: .abbreviated, time: .omitted))",
                    searchBlob: searchBlob,
                    pregValue: store.latestPregnancyEvent(
                        farmID: animal.farmID,
                        eidRaw: animal.eidRaw
                    )?.int1
                )

                rows.append(row)
            }

            let sorted = rows.sorted {
                $0.animal.updatedAt > $1.animal.updatedAt
            }

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

    // MARK: - Filter Helpers

    func reconcileFiltersAfterFarmOrMobChange() {}
    func reconcileClassFilterIfNeeded() {}
}
