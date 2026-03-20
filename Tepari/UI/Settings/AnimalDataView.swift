import SwiftUI

struct AnimalDataView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Filters
    @State private var selectedFarmID: UUID? = nil   // nil = All Farms
    @State private var filterMobID: UUID? = nil
    @State private var filterClass: String? = nil
    @State private var searchText: String = ""
    @State private var showSearchField: Bool = false
    @State private var showSortSheet: Bool = false

    // MARK: - Ranking / sorting
    @State private var sortKey: SortKey = .updatedAt
    @State private var sortAscending: Bool = false

    // MARK: - Bulk selection
    @State private var isSelecting: Bool = false
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var showDeleteConfirmation: Bool = false

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        animalListView()
            .navigationTitle("Animal Data")
            .navigationBarTitleDisplayMode(.inline)
            .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteSelectedAnimals()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(deleteConfirmationMessage)
            }
            .sheet(isPresented: $coordinator.showIndividualAnimalView) {
                IndividualAnimalView()
                    .environmentObject(store)
                    .environmentObject(coordinator)
            }
            .confirmationDialog("Sort Animals", isPresented: $showSortSheet, titleVisibility: .visible) {
                ForEach(SortKey.allCases) { key in
                    Button(sortKey == key ? "✓ \(key.rawValue)" : key.rawValue) {
                        sortKey = key
                    }
                }

                Divider()

                Button(sortAscending ? "Ascending ✓" : "Ascending") {
                    sortAscending = true
                }

                Button(!sortAscending ? "Descending ✓" : "Descending") {
                    sortAscending = false
                }

                if sortKey != .updatedAt || sortAscending {
                    Button("Reset Sort", role: .destructive) {
                        sortKey = .updatedAt
                        sortAscending = false
                    }
                }

                Button("Cancel", role: .cancel) { }
            }
    }
}

// MARK: - Sort / Rank

private extension AnimalDataView {

    enum SortKey: String, CaseIterable, Identifiable {
        case updatedAt = "Last Scan"
        case eid = "EID"
        case lambs = "Preg / Lambs"
        case fleece = "Fleece Weight"
        case staple = "Staple Length"

        var id: String { rawValue }
    }
}

// MARK: - Derived data

private extension AnimalDataView {

    struct PregDisplay {
        let year: Int
        let value: Int?
    }

    struct PregLookupKey: Hashable {
        let farmID: UUID
        let eidRaw: String
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var farmByID: [UUID: LocalDataStore.Farm] {
        Dictionary(uniqueKeysWithValues: store.farms.map { ($0.id, $0) })
    }

    var mobByID: [UUID: LocalDataStore.Mob] {
        Dictionary(uniqueKeysWithValues: store.mobs.map { ($0.id, $0) })
    }

    var selectedFarmName: String? {
        guard let selectedFarmID else { return nil }
        return farmByID[selectedFarmID]?.name
    }

    var mobsScope: [LocalDataStore.Mob] {
        store.mobs
            .filter { mob in
                if let farmID = selectedFarmID { return mob.farmID == farmID }
                return true
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var validMobIDs: Set<UUID> {
        Set(mobsScope.map(\.id))
    }

    var effectiveFilterMobID: UUID? {
        guard let filterMobID else { return nil }
        return validMobIDs.contains(filterMobID) ? filterMobID : nil
    }

    var baseAnimals: [LocalDataStore.AnimalProfile] {
        store.animals.filter { animal in
            if let farmID = selectedFarmID { return animal.farmID == farmID }
            return true
        }
    }

    var animalsAfterFarmAndMob: [LocalDataStore.AnimalProfile] {
        baseAnimals.filter { animal in
            if let mobID = effectiveFilterMobID { return animal.mobID == mobID }
            return true
        }
    }

    var classOptions: [String] {
        Array(
            Set(
                animalsAfterFarmAndMob
                    .compactMap { $0.klass?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var latestPregByFarmAndEID: [PregLookupKey: PregDisplay] {
        [:]
    }

    var effectiveFilteredAnimals: [LocalDataStore.AnimalProfile] {
        animalsAfterFarmAndMob
            .filter { animal in
                if let klass = filterClass, !klass.isEmpty {
                    return (animal.klass ?? "").caseInsensitiveCompare(klass) == .orderedSame
                }
                return true
            }
            .filter { animal in
                guard !normalizedSearchText.isEmpty else { return true }

                let mobName = animal.mobID.flatMap { mobByID[$0]?.name } ?? ""
                let farmName = farmByID[animal.farmID]?.name ?? ""
                let haystack = [
                    animal.eidRaw,
                    animal.comments ?? "",
                    animal.klass ?? "",
                    mobName,
                    farmName
                ]
                .joined(separator: " ")
                .lowercased()

                return haystack.contains(normalizedSearchText)
            }
    }

    var latestPregByAnimalID: [UUID: PregDisplay] {
        Dictionary(
            uniqueKeysWithValues: effectiveFilteredAnimals.compactMap { animal in
                let key = PregLookupKey(farmID: animal.farmID, eidRaw: animal.eidRaw)
                guard let summary = latestPregByFarmAndEID[key] else { return nil }
                return (animal.id, summary)
            }
        )
    }

    var allRankedFilteredAnimals: [LocalDataStore.AnimalProfile] {
        sortAnimals(
            effectiveFilteredAnimals,
            key: sortKey,
            ascending: sortAscending,
            latestPregByAnimalID: latestPregByAnimalID
        )
    }

    var rankedAnimals: [LocalDataStore.AnimalProfile] {
        Array(allRankedFilteredAnimals.prefix(200))
    }

    var filteredIDs: Set<UUID> {
        Set(allRankedFilteredAnimals.map(\.id))
    }

    var selectedCountInFiltered: Int {
        selectedAnimalIDs.intersection(filteredIDs).count
    }

    var allFilteredSelected: Bool {
        !effectiveFilteredAnimals.isEmpty && selectedCountInFiltered == effectiveFilteredAnimals.count
    }

    var activeFilterCount: Int {
        var count = 0
        if selectedFarmID != nil { count += 1 }
        if effectiveFilterMobID != nil { count += 1 }
        if filterClass != nil { count += 1 }
        if !normalizedSearchText.isEmpty { count += 1 }
        if sortKey != .updatedAt || sortAscending { count += 1 }
        return count
    }

    var resultsTitle: String {
        if effectiveFilteredAnimals.count > rankedAnimals.count {
            return "Animals (\(rankedAnimals.count) of \(effectiveFilteredAnimals.count))"
        }
        return "Animals (\(effectiveFilteredAnimals.count))"
    }

    var sortSummaryText: String {
        "\(sortKey.rawValue) · \(sortAscending ? "Ascending" : "Descending")"
    }

    var cardFill: Color {
        Color(uiColor: .tertiarySystemGroupedBackground)
    }

    var softFill: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    var softerFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    var selectedPillFill: Color {
        .accentColor
    }

    var selectedPillText: Color {
        .white
    }

    var unselectedPillFill: Color {
        softFill
    }

    var unselectedPillText: Color {
        .primary
    }
}

// MARK: - List + Header + Filters

private extension AnimalDataView {

    func animalListView() -> some View {
        List {

            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if isSelecting {
                Section {
                    bulkActionsCard
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            Section(resultsTitle) {

                if rankedAnimals.isEmpty {
                    Text(effectiveFilteredAnimals.isEmpty && !baseAnimals.isEmpty
                         ? "No animals match your filters."
                         : "No animals imported yet.")
                        .foregroundStyle(.secondary)
                }

                if effectiveFilteredAnimals.count > rankedAnimals.count {
                    Text("Showing first \(rankedAnimals.count) animals. Select All Filtered still applies to all \(effectiveFilteredAnimals.count) matching animals.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(rankedAnimals) { animal in
                    if isSelecting {
                        Button {
                            toggleSelection(for: animal.id)
                        } label: {
                            selectableAnimalRow(
                                animal,
                                farmByID: farmByID,
                                mobByID: mobByID,
                                isSelected: selectedAnimalIDs.contains(animal.id)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            coordinator.selectedIndividualAnimalEID = animal.eidRaw
                            coordinator.selectedIndividualAnimalFarmID = animal.farmID
                            coordinator.focusedEID = animal.eidRaw
                            coordinator.showIndividualAnimalView = true
                        } label: {
                            animalRow(
                                animal,
                                farmByID: farmByID,
                                mobByID: mobByID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            topControlsRow

            if showSearchField {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            filterSectionCard(
                title: "Farm",
                icon: "building.2.crop.circle",
                currentValue: farmFilterLabel()
            ) {
                filterPillRow {
                    filterCapsulePill(title: "All", isSelected: selectedFarmID == nil) {
                        selectedFarmID = nil
                        filterMobID = nil
                        filterClass = nil
                    }

                    ForEach(store.farms) { farm in
                        filterCapsulePill(
                            title: farm.name,
                            isSelected: selectedFarmID == farm.id
                        ) {
                            selectedFarmID = farm.id

                            if let currentMobID = filterMobID,
                               !store.mobs.contains(where: { $0.id == currentMobID && $0.farmID == farm.id }) {
                                filterMobID = nil
                            }

                            if let currentClass = filterClass,
                               !classOptions.contains(where: { $0.caseInsensitiveCompare(currentClass) == .orderedSame }) {
                                filterClass = nil
                            }
                        }
                    }
                }
            }

            filterSectionCard(
                title: "Mob",
                icon: "person.3.fill",
                currentValue: mobFilterLabel()
            ) {
                filterPillRow {
                    filterCapsulePill(title: "All", isSelected: effectiveFilterMobID == nil) {
                        filterMobID = nil
                        if let currentClass = filterClass,
                           !classOptions.contains(where: { $0.caseInsensitiveCompare(currentClass) == .orderedSame }) {
                            filterClass = nil
                        }
                    }

                    ForEach(mobsScope) { mob in
                        filterCapsulePill(
                            title: mob.name,
                            isSelected: effectiveFilterMobID == mob.id
                        ) {
                            filterMobID = mob.id
                            if let currentClass = filterClass,
                               !classOptions.contains(where: { $0.caseInsensitiveCompare(currentClass) == .orderedSame }) {
                                filterClass = nil
                            }
                        }
                    }
                }
            }

            filterSectionCard(
                title: "Class",
                icon: "tag.fill",
                currentValue: classFilterLabel()
            ) {
                filterPillRow {
                    filterCapsulePill(title: "All", isSelected: filterClass == nil) {
                        filterClass = nil
                    }

                    ForEach(classOptions, id: \.self) { klass in
                        filterCapsulePill(
                            title: klass,
                            isSelected: (filterClass ?? "").caseInsensitiveCompare(klass) == .orderedSame
                        ) {
                            filterClass = klass
                        }
                    }
                }
            }

            if activeFilterCount > 0 {
                activeSummaryRow
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var topControlsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Filter & Sort")
                    .font(.headline)

                Text("\(effectiveFilteredAnimals.count) matching animals")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                compactControlButton(
                    title: showSearchField ? "Hide Search" : "Search",
                    icon: showSearchField ? "xmark" : "magnifyingglass"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSearchField.toggle()
                        if !showSearchField {
                            searchText = ""
                        }
                    }
                }

                compactControlButton(
                    title: "Sort",
                    icon: "arrow.up.arrow.down"
                ) {
                    showSortSheet = true
                }

                compactControlButton(
                    title: isSelecting ? "Done" : "Select",
                    icon: isSelecting ? "checkmark.circle.fill" : "checkmark.circle",
                    isProminent: isSelecting
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isSelecting {
                            isSelecting = false
                            selectedAnimalIDs.removeAll()
                        } else {
                            isSelecting = true
                        }
                    }
                }
            }
        }
    }

    var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search EID, mob, class, farm", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(softFill)
        .clipShape(Capsule())
    }

    func filterSectionCard<Content: View>(
        title: String,
        icon: String,
        currentValue: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Text(currentValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(softFill)
                    .clipShape(Capsule())
            }

            HStack(spacing: 0) {
                content()
            }
            .padding(8)
            .background(softFill)
            .clipShape(Capsule())
        }
        .padding(12)
        .background(softerFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    func filterPillRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 2)
        }
    }

    func filterCapsulePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? selectedPillText : unselectedPillText)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? selectedPillFill : unselectedPillFill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func compactControlButton(
        title: String,
        icon: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isProminent ? Color.accentColor : softFill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var activeSummaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Filters")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if selectedFarmID != nil {
                            activeMiniPill(text: farmFilterLabel())
                        }
                        if effectiveFilterMobID != nil {
                            activeMiniPill(text: mobFilterLabel())
                        }
                        if let filterClass, !filterClass.isEmpty {
                            activeMiniPill(text: filterClass)
                        }
                        if !normalizedSearchText.isEmpty {
                            activeMiniPill(text: "Search")
                        }
                        if sortKey != .updatedAt || sortAscending {
                            activeMiniPill(text: sortSummaryText)
                        }
                    }
                }

                Button("Clear") {
                    clearSecondaryFilters()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
            }
        }
    }

    func activeMiniPill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(softFill)
            .clipShape(Capsule())
    }

    var bulkActionsCard: some View {
        VStack(spacing: 12) {
            Button {
                if allFilteredSelected {
                    selectedAnimalIDs.subtract(filteredIDs)
                } else {
                    selectedAnimalIDs.formUnion(filteredIDs)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: allFilteredSelected ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(.blue)
                        .frame(width: 22)

                    Text(allFilteredSelected ? "Clear All Filtered" : "Select All Filtered")
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(effectiveFilteredAnimals.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(effectiveFilteredAnimals.isEmpty)

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .frame(width: 22)

                    Text("Delete Selected")

                    Spacer()

                    Text("\(selectedCountInFiltered)")
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(selectedCountInFiltered == 0)

            if selectedCountInFiltered > 0 {
                HStack {
                    Text("\(selectedCountInFiltered) selected from \(effectiveFilteredAnimals.count) filtered animals.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    func farmFilterLabel() -> String {
        selectedFarmName ?? "All Farms"
    }

    func mobFilterLabel() -> String {
        guard let mobID = effectiveFilterMobID else { return "All Mobs" }
        return mobsScope.first(where: { $0.id == mobID })?.name ?? "Unknown Mob"
    }

    func classFilterLabel() -> String {
        guard let klass = filterClass, !klass.isEmpty else { return "All Classes" }
        return klass
    }

    func clearSecondaryFilters() {
        selectedFarmID = nil
        filterMobID = nil
        filterClass = nil
        searchText = ""
        showSearchField = false
        sortKey = .updatedAt
        sortAscending = false
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
        "This will permanently delete \(selectedAnimalIDs.count) animals from Animal Data."
    }

    func deleteSelectedAnimals() {
        let idsToDelete = selectedAnimalIDs
        guard !idsToDelete.isEmpty else { return }

        store.deleteAnimals(ids: Array(idsToDelete))

        selectedAnimalIDs.removeAll()
        isSelecting = false
    }
}

// MARK: - Animal row

private extension AnimalDataView {
    
    func selectableAnimalRow(
        _ animal: LocalDataStore.AnimalProfile,
        farmByID: [UUID: LocalDataStore.Farm],
        mobByID: [UUID: LocalDataStore.Mob],
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .blue : .secondary)
            
            animalRow(
                animal,
                farmByID: farmByID,
                mobByID: mobByID
            )
        }
        .padding(.vertical, 2)
    }
    
    func animalRow(
        _ animal: LocalDataStore.AnimalProfile,
        farmByID: [UUID: LocalDataStore.Farm],
        mobByID: [UUID: LocalDataStore.Mob]
    ) -> some View {
        
        let farmName = farmByID[animal.farmID]?.name ?? "Unknown Farm"
        
        let className: String = {
            let trimmed = animal.klass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "No Class" : trimmed
        }()
        
        let yearText = "Year —"
        
        let totalLambsText: String = {
            let total = store.totalLambsForAnimal(
                farmID: animal.farmID,
                eidRaw: animal.eidRaw
            )
            return "Lambs \(total)"
        }()
        
        return VStack(alignment: .leading, spacing: 8) {
            
            HStack(alignment: .center, spacing: 10) {
                Text(animal.eidRaw)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(eidPillTextColor(for: animal, mobByID: mobByID))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(eidPillColor(for: animal, mobByID: mobByID))
                    .clipShape(Capsule())
                
                Spacer(minLength: 8)
                
                Text(farmName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    detailMiniPill(yearText)
                    detailMiniPill(className)
                    detailMiniPill(totalLambsText)
                }
                .padding(8)
                .background(softFill)
                .clipShape(Capsule())
                
                Spacer(minLength: 8)
                
                Text(lastScanText(for: animal))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, isWideLayout ? 4 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    func detailMiniPill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(softerFill)
            .clipShape(Capsule())
    }
    
    func eidPillColor(
        for animal: LocalDataStore.AnimalProfile,
        mobByID: [UUID: LocalDataStore.Mob]
    ) -> Color {
        guard let mobID = animal.mobID,
              let mob = mobByID[mobID] else {
            return softFill
        }
        
        let hex = mob.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty, let color = colorFromHex(hex) else {
            return softFill
        }
        
        return color
    }
    
    func eidPillTextColor(
        for animal: LocalDataStore.AnimalProfile,
        mobByID: [UUID: LocalDataStore.Mob]
    ) -> Color {
        guard let mobID = animal.mobID,
              let mob = mobByID[mobID] else {
            return .primary
        }
        
        let hex = mob.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return hex.isEmpty ? .primary : .white
    }
    
    func colorFromHex(_ hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        
        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        
        let r, g, b, a: Double
        
        if cleaned.count == 8 {
            a = Double((value & 0xFF000000) >> 24) / 255.0
            r = Double((value & 0x00FF0000) >> 16) / 255.0
            g = Double((value & 0x0000FF00) >> 8) / 255.0
            b = Double(value & 0x000000FF) / 255.0
        } else {
            a = 1.0
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
        }
        
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
    
    func lastScanText(for animal: LocalDataStore.AnimalProfile) -> String {
        "Last scan \(animal.updatedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

