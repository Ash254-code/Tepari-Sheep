import SwiftUI
import UniformTypeIdentifiers

struct AnimalDataView: View {

    @EnvironmentObject private var store: LocalDataStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // ✅ Filters
    @State private var selectedFarmID: UUID? = nil   // nil = All Farms
    @State private var filterMobID: UUID? = nil
    @State private var filterClass: String? = nil

    // ✅ Ranking / sorting
    @State private var sortKey: SortKey = .updatedAt
    @State private var sortAscending: Bool = false

    // ✅ Bulk selection
    @State private var isSelecting: Bool = false
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var showDeleteConfirmation: Bool = false

    // Import
    @State private var showingImporter = false
    @State private var importResultMessage: String? = nil

    // Editing
    @State private var selectedAnimal: LocalDataStore.AnimalProfile? = nil

    private var dataStore: LocalDataStore { store }
    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {

        Group {
            if store.farms.isEmpty {
                ContentUnavailableView(
                    "No Farms",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Add a farm before importing animal data.")
                )
            } else {
                animalListView()
            }
        }
        .navigationTitle("📄 Animal Data")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {

                if isSelecting {
                    Button("Cancel") {
                        isSelecting = false
                        selectedAnimalIDs.removeAll()
                    }
                } else {
                    Button("Select") {
                        isSelecting = true
                    }
                }

                Button("Import CSV") {
                    showingImporter = true
                }
            }
        }
        .onChange(of: selectedFarmID) { _, _ in
            filterMobID = nil
            filterClass = nil
            selectedAnimalIDs.removeAll()
            isSelecting = false
        }
        .onChange(of: filterMobID) { _, _ in
            selectedAnimalIDs.removeAll()
        }
        .onChange(of: filterClass) { _, _ in
            selectedAnimalIDs.removeAll()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleFileImport(result)
        }
        .alert("Import Result", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedAnimalIDs.count) Animals", role: .destructive) {
                deleteSelectedAnimals()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(item: $selectedAnimal) { animal in
            NavigationStack {
                AnimalEditorView(
                    farmID: farmIDForAnimalSheet(animal),
                    animal: animal
                )
            }
        }
    }
}

//
// MARK: - Sort / Rank
//

private extension AnimalDataView {

    enum SortKey: String, CaseIterable, Identifiable {
        case updatedAt = "Recently Updated"
        case eid = "EID"
        case lambs = "Preg / Lambs"
        case fleece = "Fleece Weight (kg)"
        case staple = "Staple Length (mm)"

        var id: String { rawValue }
    }
}

//
// MARK: - List + Filters + Rank
//

private extension AnimalDataView {

    func animalListView() -> some View {

        let farmByID: [UUID: LocalDataStore.Farm] = Dictionary(
            uniqueKeysWithValues: store.farms.map { ($0.id, $0) }
        )

        let mobByID: [UUID: LocalDataStore.Mob] = Dictionary(
            uniqueKeysWithValues: store.mobs.map { ($0.id, $0) }
        )

        let baseAnimals: [LocalDataStore.AnimalProfile] = store.animals
            .filter { animal in
                if let farmID = selectedFarmID { return animal.farmID == farmID }
                return true
            }

        let mobsScope: [LocalDataStore.Mob] = store.mobs
            .filter { mob in
                if let farmID = selectedFarmID { return mob.farmID == farmID }
                return true
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let classOptions: [String] = Array(
            Set(
                baseAnimals
                    .compactMap { $0.klass?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let validMobIDs = Set(mobsScope.map(\.id))
        let effectiveFilterMobID: UUID? = {
            guard let filterMobID else { return nil }
            return validMobIDs.contains(filterMobID) ? filterMobID : nil
        }()

        let effectiveFilteredAnimals: [LocalDataStore.AnimalProfile] = baseAnimals
            .filter { animal in
                if let mobID = effectiveFilterMobID { return animal.mobID == mobID }
                return true
            }
            .filter { animal in
                if let klass = filterClass, !klass.isEmpty {
                    return (animal.klass ?? "").caseInsensitiveCompare(klass) == .orderedSame
                }
                return true
            }

        let latestPregByAnimalID: [UUID: PregDisplay] = Dictionary(
            uniqueKeysWithValues: effectiveFilteredAnimals.compactMap { animal in
                guard let summary = latestPregDisplay(for: animal) else { return nil }
                return (animal.id, summary)
            }
        )

        let rankedAnimals = sortAnimals(
            effectiveFilteredAnimals,
            key: sortKey,
            ascending: sortAscending,
            latestPregByAnimalID: latestPregByAnimalID
        )

        let filteredIDs = Set(rankedAnimals.map(\.id))
        let selectedCountInFiltered = selectedAnimalIDs.intersection(filteredIDs).count
        let allFilteredSelected = !rankedAnimals.isEmpty && selectedCountInFiltered == rankedAnimals.count

        return List {

            Section("Filters") {

                filterRow(
                    title: "Farm",
                    value: farmFilterLabel(),
                    menuItems: {
                        Button {
                            selectedFarmID = nil
                        } label: {
                            if selectedFarmID == nil {
                                Label("All Farms", systemImage: "checkmark")
                            } else {
                                Text("All Farms")
                            }
                        }

                        ForEach(store.farms) { farm in
                            Button {
                                selectedFarmID = farm.id
                            } label: {
                                if selectedFarmID == farm.id {
                                    Label(farm.name, systemImage: "checkmark")
                                } else {
                                    Text(farm.name)
                                }
                            }
                        }
                    }
                )

                filterRow(
                    title: "Mob",
                    value: mobFilterLabel(mobsScope: mobsScope),
                    menuItems: {
                        Button {
                            filterMobID = nil
                        } label: {
                            if filterMobID == nil {
                                Label("All Mobs", systemImage: "checkmark")
                            } else {
                                Text("All Mobs")
                            }
                        }

                        if mobsScope.isEmpty {
                            Text("No mobs available")
                        } else {
                            ForEach(mobsScope) { mob in
                                Button {
                                    filterMobID = mob.id
                                } label: {
                                    if filterMobID == mob.id {
                                        Label(mobLabel(mob), systemImage: "checkmark")
                                    } else {
                                        Text(mobLabel(mob))
                                    }
                                }
                            }
                        }
                    }
                )

                filterRow(
                    title: "Class",
                    value: classFilterLabel(),
                    menuItems: {
                        Button {
                            filterClass = nil
                        } label: {
                            if filterClass == nil {
                                Label("All Classes", systemImage: "checkmark")
                            } else {
                                Text("All Classes")
                            }
                        }

                        if classOptions.isEmpty {
                            Text("No class values yet")
                        } else {
                            ForEach(classOptions, id: \.self) { klass in
                                Button {
                                    filterClass = klass
                                } label: {
                                    if filterClass == klass {
                                        Label(klass, systemImage: "checkmark")
                                    } else {
                                        Text(klass)
                                    }
                                }
                            }
                        }
                    }
                )
            }

            Section("Rank") {
                HStack {
                    Text("Sort")
                        .foregroundStyle(.secondary)
                    Spacer()

                    Menu {
                        ForEach(SortKey.allCases) { key in
                            Button {
                                sortKey = key
                            } label: {
                                if sortKey == key {
                                    Label(key.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(key.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(sortKey.rawValue)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }

                Button {
                    sortAscending.toggle()
                } label: {
                    HStack {
                        Text("Order")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(sortAscending ? "Min → Max" : "Max → Min")
                            .font(.subheadline)
                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isSelecting {
                Section("Bulk Actions") {
                    Button {
                        if allFilteredSelected {
                            selectedAnimalIDs.subtract(filteredIDs)
                        } else {
                            selectedAnimalIDs.formUnion(filteredIDs)
                        }
                    } label: {
                        HStack {
                            Label(
                                allFilteredSelected ? "Clear All Filtered" : "Select All Filtered",
                                systemImage: allFilteredSelected ? "checkmark.circle.fill" : "checkmark.circle"
                            )
                            Spacer()
                            Text("\(rankedAnimals.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(rankedAnimals.isEmpty)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Label("Delete Selected", systemImage: "trash")
                            Spacer()
                            Text("\(selectedCountInFiltered)")
                        }
                    }
                    .disabled(selectedCountInFiltered == 0)

                    if selectedCountInFiltered > 0 {
                        Text("\(selectedCountInFiltered) selected from current filtered results.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Animals (\(rankedAnimals.count))") {

                if rankedAnimals.isEmpty {
                    Text(effectiveFilteredAnimals.isEmpty && !baseAnimals.isEmpty
                         ? "No animals match your filters."
                         : "No animals imported yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(rankedAnimals) { animal in
                    if isSelecting {
                        Button {
                            toggleSelection(for: animal.id)
                        } label: {
                            selectableAnimalRow(
                                animal,
                                showFarm: selectedFarmID == nil,
                                latestPregByAnimalID: latestPregByAnimalID,
                                farmByID: farmByID,
                                mobByID: mobByID,
                                isSelected: selectedAnimalIDs.contains(animal.id)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            selectedAnimal = animal
                        } label: {
                            animalRow(
                                animal,
                                showFarm: selectedFarmID == nil,
                                latestPregByAnimalID: latestPregByAnimalID,
                                farmByID: farmByID,
                                mobByID: mobByID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    func sortAnimals(
        _ animals: [LocalDataStore.AnimalProfile],
        key: SortKey,
        ascending: Bool,
        latestPregByAnimalID: [UUID: PregDisplay]
    ) -> [LocalDataStore.AnimalProfile] {

        func cmpD(_ a: Double?, _ b: Double?) -> ComparisonResult {
            switch (a, b) {
            case let (x?, y?):
                if x == y { return .orderedSame }
                return x < y ? .orderedAscending : .orderedDescending
            case (nil, nil): return .orderedSame
            case (nil, _?):  return .orderedAscending
            case (_?, nil):  return .orderedDescending
            }
        }

        func cmpI(_ a: Int?, _ b: Int?) -> ComparisonResult {
            switch (a, b) {
            case let (x?, y?):
                if x == y { return .orderedSame }
                return x < y ? .orderedAscending : .orderedDescending
            case (nil, nil): return .orderedSame
            case (nil, _?):  return .orderedAscending
            case (_?, nil):  return .orderedDescending
            }
        }

        return animals.sorted { a, b in
            let result: ComparisonResult

            switch key {
            case .updatedAt:
                result = a.updatedAt == b.updatedAt
                    ? .orderedSame
                    : (a.updatedAt < b.updatedAt ? .orderedAscending : .orderedDescending)

            case .eid:
                result = a.eidRaw.localizedStandardCompare(b.eidRaw)

            case .lambs:
                result = cmpI(latestPregByAnimalID[a.id]?.value, latestPregByAnimalID[b.id]?.value)

            case .fleece:
                result = cmpD(a.fleeceWeightKg, b.fleeceWeightKg)

            case .staple:
                result = cmpD(a.stapleLengthMm, b.stapleLengthMm)
            }

            if result == .orderedSame {
                return a.eidRaw < b.eidRaw
            }

            return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    func latestPregDisplay(for animal: LocalDataStore.AnimalProfile) -> PregDisplay? {
        let events = store.animalEvents
            .filter { ev in
                ev.kind == .lambing &&
                ev.farmID == animal.farmID &&
                ev.eidRaw == animal.eidRaw
            }

        guard !events.isEmpty else { return nil }

        let latest = events.max { lhs, rhs in
            let leftYear = lhs.int1 ?? Calendar.current.component(.year, from: lhs.date)
            let rightYear = rhs.int1 ?? Calendar.current.component(.year, from: rhs.date)

            if leftYear != rightYear {
                return leftYear < rightYear
            }
            return lhs.date < rhs.date
        }

        guard let latest else { return nil }

        let year = latest.int1 ?? Calendar.current.component(.year, from: latest.date)
        let value = latest.json?["born"].flatMap(Int.init)

        return PregDisplay(year: year, value: value)
    }

    func filterRow(
        title: String,
        value: String,
        @ViewBuilder menuItems: @escaping () -> some View
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                menuItems()
            } label: {
                HStack(spacing: 6) {
                    Text(value).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    func farmFilterLabel() -> String {
        guard let farmID = selectedFarmID else { return "All Farms" }
        return store.farms.first(where: { $0.id == farmID })?.name ?? "Unknown Farm"
    }

    func mobFilterLabel(mobsScope: [LocalDataStore.Mob]) -> String {
        guard let mobID = filterMobID else { return "All Mobs" }
        return mobsScope.first(where: { $0.id == mobID }).map { mobLabel($0) } ?? "Unknown Mob"
    }

    func classFilterLabel() -> String {
        guard let klass = filterClass, !klass.isEmpty else { return "All Classes" }
        return klass
    }

    func mobLabel(_ mob: LocalDataStore.Mob) -> String {
        if selectedFarmID == nil,
           let farmName = store.farms.first(where: { $0.id == mob.farmID })?.name {
            return "\(mob.name) • \(farmName)"
        }
        return mob.name
    }

    func toggleSelection(for animalID: UUID) {
        if selectedAnimalIDs.contains(animalID) {
            selectedAnimalIDs.remove(animalID)
        } else {
            selectedAnimalIDs.insert(animalID)
        }
    }

    var deleteConfirmationTitle: String {
        "Delete \(selectedAnimalIDs.count) Selected Animals?"
    }

    var deleteConfirmationMessage: String {
        "This will permanently delete the selected animals from Animal Data."
    }

    func deleteSelectedAnimals() {
        let idsToDelete = selectedAnimalIDs
        guard !idsToDelete.isEmpty else { return }

        store.deleteAnimals(ids: Array(idsToDelete))

        selectedAnimalIDs.removeAll()
        isSelecting = false
    }
}

//
// MARK: - Animal row
//

private extension AnimalDataView {

    struct PregDisplay {
        let year: Int
        let value: Int?
    }

    func selectableAnimalRow(
        _ animal: LocalDataStore.AnimalProfile,
        showFarm: Bool,
        latestPregByAnimalID: [UUID: PregDisplay],
        farmByID: [UUID: LocalDataStore.Farm],
        mobByID: [UUID: LocalDataStore.Mob],
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .padding(.top, 6)

            animalRow(
                animal,
                showFarm: showFarm,
                latestPregByAnimalID: latestPregByAnimalID,
                farmByID: farmByID,
                mobByID: mobByID
            )
        }
    }

    func animalRow(
        _ animal: LocalDataStore.AnimalProfile,
        showFarm: Bool,
        latestPregByAnimalID: [UUID: PregDisplay],
        farmByID: [UUID: LocalDataStore.Farm],
        mobByID: [UUID: LocalDataStore.Mob]
    ) -> some View {

        let farmName = farmByID[animal.farmID]?.name
        let mobName = animal.mobID.flatMap { mobByID[$0]?.name }
        let latestPreg = latestPregByAnimalID[animal.id]

        return VStack(alignment: .leading, spacing: 8) {

            if isWideLayout {
                HStack(alignment: .top, spacing: 16) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text(animal.eidRaw)
                            .font(.headline)

                        if showFarm, let farmName {
                            infoLine("Farm", farmName)
                        }

                        if let mobName {
                            infoLine("Mob", mobName)
                        }

                        if let comments = animal.comments, !comments.isEmpty {
                            Text(comments)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        if let latestPreg {
                            pregBadge(latestPreg)
                        }

                        if let klass = animal.klass, !klass.isEmpty {
                            valueBadge("Class: \(klass)")
                        }

                        if let fleece = animal.fleeceWeightKg {
                            valueBadge("Fleece: \(String(format: "%.1f", fleece))kg")
                        }

                        if let staple = animal.stapleLengthMm {
                            valueBadge("Staple: \(Int(staple))mm")
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {

                    Text(animal.eidRaw)
                        .font(.headline)

                    if showFarm, let farmName {
                        infoLine("Farm", farmName)
                    }

                    if let mobName {
                        infoLine("Mob", mobName)
                    }

                    FlowTagStack {
                        if let latestPreg {
                            pregBadge(latestPreg)
                        }

                        if let klass = animal.klass, !klass.isEmpty {
                            valueBadge("Class: \(klass)")
                        }

                        if let fleece = animal.fleeceWeightKg {
                            valueBadge("Fleece: \(String(format: "%.1f", fleece))kg")
                        }

                        if let staple = animal.stapleLengthMm {
                            valueBadge("Staple: \(Int(staple))mm")
                        }
                    }

                    if let comments = animal.comments, !comments.isEmpty {
                        Text(comments)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if !isSelecting {
                Text("Tap to edit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func infoLine(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value)
        }
        .font(.subheadline)
    }

    func valueBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    func pregBadge(_ preg: PregDisplay) -> some View {
        if let value = preg.value {
            return AnyView(valueBadge("Preg \(preg.year): \(value)"))
        } else {
            return AnyView(valueBadge("Preg \(preg.year)"))
        }
    }
}

//
// MARK: - File import
//

private extension AnimalDataView {

    func handleFileImport(_ result: Result<URL, Error>) {

        switch result {

        case .success(let url):

            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    importResultMessage = "Could not read file."
                    return
                }

                let outcome = dataStore.importAnimalsCSV(csvText: text)

                importResultMessage =
                    "Imported \(outcome.imported)\nSkipped \(outcome.skipped)"

            } catch {
                importResultMessage = error.localizedDescription
            }

        case .failure(let error):
            importResultMessage = error.localizedDescription
        }
    }

    func farmIDForAnimalSheet(_ animal: LocalDataStore.AnimalProfile) -> UUID {
        selectedFarmID ?? animal.farmID
    }
}

//
// MARK: - Simple flow tag stack
//

private struct FlowTagStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
    }
}
