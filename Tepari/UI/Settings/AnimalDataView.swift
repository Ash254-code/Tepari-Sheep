import SwiftUI

struct AnimalDataView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var vm = AnimalDataViewModel()
    @State private var didBindStore = false

    @State private var showSearchField: Bool = false
    @State private var showSortSheet: Bool = false
    @State private var showFilterSheet: Bool = false
    @State private var isSelecting: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    @State private var showBulkEditSheet: Bool = false
    @State private var showBulkEditConfirmation: Bool = false

    @State private var selectedBulkField: BulkEditField = .animalClass
    @State private var selectedBulkMode: BulkTextMode = .replace

    @State private var pendingBulkClass: LocalDataStore.AnimalClass = .flock
    @State private var pendingBulkSex: LocalDataStore.Sex = .ewe
    @State private var pendingBulkStatus: AnimalStatus = .dry
    @State private var pendingBulkMobName: String = ""

    @State private var pendingBulkBreed: String = ""
    @State private var pendingBulkBirthYear: String = ""
    @State private var pendingBulkBirthMonth: Int = 1

    @State private var pendingBulkComments: String = ""
    @State private var pendingBulkUserField1: String = ""
    @State private var pendingBulkUserField2: String = ""

    var body: some View {
        ZStack {
            GlassBackground()
            animalListView()
        }
        .navigationTitle("Animal Data")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didBindStore {
                vm.bind(store: store)
                didBindStore = true
            }
        }
        .onChange(of: vm.selectedFarmIDs) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.selectedMobNames) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.selectedClasses) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.selectedSexes) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.sortKey) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.sortAscending) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: store.farms) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: store.mobs) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: store.animals) { _, _ in
            vm.recomputeDerivedData()
        }
        .onChange(of: store.animalEvents) { _, _ in
            vm.recomputeDerivedData()
        }
        .animation(nil, value: vm.derived.rankedRows)
        .animation(nil, value: vm.selectedAnimalIDs)
        .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedAnimals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert(bulkEditConfirmationTitle, isPresented: $showBulkEditConfirmation) {
            Button("Apply", role: .destructive) {
                applyBulkEdit()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bulkEditConfirmationMessage)
        }
        .sheet(isPresented: $coordinator.showIndividualAnimalView) {
            IndividualAnimalView()
                .environmentObject(store)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkEditSheet) {
            bulkEditSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Sort Animals", isPresented: $showSortSheet, titleVisibility: .visible) {
            ForEach(AnimalDataViewModel.SortKey.allCases) { key in
                Button(vm.sortKey == key ? "✓ \(key.rawValue)" : key.rawValue) {
                    vm.sortKey = key
                }
            }

            Divider()

            Button(vm.sortAscending ? "Ascending ✓" : "Ascending") {
                vm.sortAscending = true
            }

            Button(!vm.sortAscending ? "Descending ✓" : "Descending") {
                vm.sortAscending = false
            }

            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Bulk Edit Types

private extension AnimalDataView {

    enum BulkEditField: String, CaseIterable, Identifiable {
        case animalClass
        case sex
        case status
        case mob
        case breed
        case birthYear
        case birthMonth
        case comments
        case userField1
        case userField2

        var id: String { rawValue }

        var label: String {
            switch self {
            case .animalClass: return "Class"
            case .sex: return "Sex"
            case .status: return "Status"
            case .mob: return "Mob"
            case .breed: return "Breed"
            case .birthYear: return "Birth Year"
            case .birthMonth: return "Birth Month"
            case .comments: return "Comments"
            case .userField1: return "User Field 1"
            case .userField2: return "User Field 2"
            }
        }

        var supportsClear: Bool {
            switch self {
            case .animalClass, .sex, .status, .mob, .breed, .birthYear, .birthMonth, .comments, .userField1, .userField2:
                return true
            }
        }

        var isTextField: Bool {
            switch self {
            case .comments, .userField1, .userField2:
                return true
            default:
                return false
            }
        }
    }

    enum BulkTextMode: String, CaseIterable, Identifiable {
        case replace
        case clear

        var id: String { rawValue }

        var label: String {
            switch self {
            case .replace: return "Replace"
            case .clear: return "Clear"
            }
        }
    }
}

// MARK: - List

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
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if vm.derived.rankedRows.isEmpty {
                    emptyStateCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(vm.derived.rankedRows, id: \.id) { row in
                        Button {
                            if isSelecting {
                                vm.toggleSelection(row.id)
                            } else {
                                coordinator.selectedIndividualAnimalEID = row.animal.eidRaw
                                coordinator.selectedIndividualAnimalFarmID = row.animal.farmID
                                coordinator.focusedEID = row.animal.eidRaw
                                coordinator.showIndividualAnimalView = true
                            }
                        } label: {
                            AnimalDataRowCard(
                                row: row,
                                isSelected: isSelecting && vm.selectedAnimalIDs.contains(row.id),
                                isSelectionMode: isSelecting
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                HStack {
                    Text(resultsTitle)
                    Spacer()
                    if vm.derived.visibleCount < vm.derived.totalMatchingCount {
                        Text("\(vm.derived.visibleCount) shown")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    var emptyStateCard: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))

                Image(systemName: "hare")
                    .foregroundColor(.primary)
            }
            .frame(width: 40, height: 40)

            Text("No animals match your filters")
                .font(.headline)

            Text("Try clearing search or adjusting filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(cardBackground)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Header

private extension AnimalDataView {

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange.opacity(0.16))
                        .frame(width: 52, height: 52)

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Animal Data")
                        .font(.headline)

                    Text("\(vm.derived.totalMatchingCount) matching animals")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            statsRow
            topControlsRow

            if showSearchField {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if activeFilterCount > 0 {
                activeSummaryRow
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardStroke)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var statsRow: some View {
        HStack(spacing: 10) {
            statPill(
                icon: "list.bullet.rectangle.portrait",
                tint: .blue,
                title: "Shown",
                value: "\(vm.derived.visibleCount)"
            )

            statPill(
                icon: "line.3.horizontal.decrease.circle.fill",
                tint: .purple,
                title: "Filtered",
                value: "\(activeFilterCount)"
            )

            statPill(
                icon: "checkmark.circle.fill",
                tint: .green,
                title: "Selected",
                value: "\(vm.selectedCountInFiltered)"
            )
        }
    }

    func statPill(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(softFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var topControlsRow: some View {
        HStack(spacing: 10) {
            controlButton(
                title: showSearchField ? "Hide Search" : "Search",
                icon: showSearchField ? "xmark" : "magnifyingglass"
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showSearchField.toggle()
                    if !showSearchField {
                        vm.updateSearchText("")
                    }
                }
            }

            controlButton(
                title: "Filter",
                icon: "line.3.horizontal.decrease.circle"
            ) {
                showFilterSheet = true
            }

            controlButton(
                title: "Sort",
                icon: "arrow.up.arrow.down"
            ) {
                showSortSheet = true
            }

            controlButton(
                title: isSelecting ? "Done" : "Select",
                icon: isSelecting ? "checkmark.circle.fill" : "checkmark.circle",
                isProminent: isSelecting
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isSelecting {
                        vm.selectedAnimalIDs.removeAll()
                    }
                    isSelecting.toggle()
                }
            }
        }
    }

    func controlButton(
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
                    .lineLimit(1)
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(isProminent ? Color.accentColor : softFill)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(
                "Search EID, mob, class, farm",
                text: Binding(
                    get: { vm.searchText },
                    set: { vm.updateSearchText($0) }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !vm.searchText.isEmpty {
                Button {
                    vm.updateSearchText("")
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

    var activeSummaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Filters")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if !vm.selectedFarmIDs.isEmpty {
                            activeMiniPill(text: "\(vm.selectedFarmIDs.count) farm\(vm.selectedFarmIDs.count == 1 ? "" : "s")")
                        }
                        if !vm.selectedSexes.isEmpty {
                            activeMiniPill(text: "\(vm.selectedSexes.count) sex\(vm.selectedSexes.count == 1 ? "" : "es")")
                        }
                        if !vm.selectedMobNames.isEmpty {
                            activeMiniPill(text: "\(vm.selectedMobNames.count) mob\(vm.selectedMobNames.count == 1 ? "" : "s")")
                        }
                        if !vm.selectedClasses.isEmpty {
                            activeMiniPill(text: "\(vm.selectedClasses.count) class\(vm.selectedClasses.count == 1 ? "" : "es")")
                        }
                        if !vm.searchText.isEmpty {
                            activeMiniPill(text: "Search")
                        }
                        if vm.sortKey != .updatedAt || vm.sortAscending {
                            activeMiniPill(text: sortSummaryText)
                        }
                    }
                }

                Button("Clear") {
                    clearFilters()
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
}

// MARK: - Filter Sheet

private extension AnimalDataView {

    var filterSheet: some View {
        NavigationStack {
            List {
                Section("Farm") {
                    ForEach(store.farms) { farm in
                        multiSelectRow(
                            title: farm.name,
                            isSelected: vm.selectedFarmIDs.contains(farm.id)
                        ) {
                            vm.toggleFarm(farm.id)
                        }
                    }
                }

                Section("Sex") {
                    ForEach(sexOptions, id: \.self) { sex in
                        multiSelectRow(
                            title: sex,
                            isSelected: vm.selectedSexes.contains(sex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        ) {
                            vm.toggleSex(sex)
                        }
                    }
                }

                Section("Mob") {
                    ForEach(mobOptions, id: \.self) { mob in
                        multiSelectRow(
                            title: mob,
                            isSelected: vm.selectedMobNames.contains(mob.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        ) {
                            vm.toggleMob(mob)
                        }
                    }
                }

                Section("Class") {
                    ForEach(classOptions, id: \.self) { klass in
                        multiSelectRow(
                            title: klass,
                            isSelected: vm.selectedClasses.contains(klass.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        ) {
                            vm.toggleClass(klass)
                        }
                    }
                }

                if activeFilterCount > 0 {
                    Section {
                        Button("Clear All Filters", role: .destructive) {
                            clearFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filter Animals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showFilterSheet = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    func multiSelectRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Text(title)
                    .foregroundStyle(Color.primary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bulk Edit Sheet

private extension AnimalDataView {

    var bulkEditSheet: some View {
        NavigationStack {
            List {
                Section("Field") {
                    Picker("Field", selection: $selectedBulkField) {
                        ForEach(BulkEditField.allCases) { field in
                            Text(field.label).tag(field)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if selectedBulkField.isTextField || selectedBulkField.supportsClear {
                    Section("Mode") {
                        Picker("Mode", selection: $selectedBulkMode) {
                            ForEach(BulkTextMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if selectedBulkMode == .replace {
                    bulkEditValueSection
                }

                Section {
                    Text("\(vm.selectedCountInFiltered) selected animals will be updated.")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            .navigationTitle("Bulk Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showBulkEditSheet = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") {
                        showBulkEditSheet = false
                        showBulkEditConfirmation = true
                    }
                    .disabled(!isBulkEditReadyToApply)
                }
            }
        }
    }

    @ViewBuilder
    var bulkEditValueSection: some View {
        switch selectedBulkField {
        case .animalClass:
            Section("Value") {
                Picker("Class", selection: $pendingBulkClass) {
                    ForEach(LocalDataStore.AnimalClass.allCases, id: \.id) { animalClass in
                        Text(animalClass.label).tag(animalClass)
                    }
                }
                .pickerStyle(.inline)
            }

        case .sex:
            Section("Value") {
                Picker("Sex", selection: $pendingBulkSex) {
                    ForEach(LocalDataStore.Sex.allCases, id: \.id) { sex in
                        Text(sex.label).tag(sex)
                    }
                }
                .pickerStyle(.inline)
            }

        case .status:
            Section("Value") {
                Picker("Status", selection: $pendingBulkStatus) {
                    ForEach(AnimalStatus.allCases, id: \.id) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.inline)
            }

        case .mob:
            Section("Value") {
                Picker("Mob", selection: $pendingBulkMobName) {
                    ForEach(mobOptions, id: \.self) { mob in
                        Text(mob).tag(mob)
                    }
                }
            }

        case .breed:
            Section("Value") {
                TextField("Breed", text: $pendingBulkBreed)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

        case .birthYear:
            Section("Value") {
                TextField("Birth Year", text: $pendingBulkBirthYear)
                    .keyboardType(.numberPad)
            }

        case .birthMonth:
            Section("Value") {
                Picker("Birth Month", selection: $pendingBulkBirthMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month)").tag(month)
                    }
                }
            }

        case .comments:
            Section("Value") {
                TextField("Comments", text: $pendingBulkComments, axis: .vertical)
                    .lineLimit(3...6)
            }

        case .userField1:
            Section("Value") {
                TextField("User Field 1", text: $pendingBulkUserField1, axis: .vertical)
                    .lineLimit(2...4)
            }

        case .userField2:
            Section("Value") {
                TextField("User Field 2", text: $pendingBulkUserField2, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
}

// MARK: - Bulk

private extension AnimalDataView {

    var bulkActionsCard: some View {
        VStack(spacing: 12) {
            Button {
                if vm.allFilteredSelected {
                    vm.clearFilteredSelection()
                } else {
                    vm.selectAllFiltered()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: vm.allFilteredSelected ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(.blue)
                        .frame(width: 22)

                    Text(vm.allFilteredSelected ? "Clear All Filtered" : "Select All Filtered")
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(vm.derived.totalMatchingCount)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(vm.derived.filteredIDs.isEmpty)

            Divider()

            Button {
                resetBulkEditDraft()
                showBulkEditSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.blue)
                        .frame(width: 22)

                    Text("Bulk Edit")
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(vm.selectedCountInFiltered)")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedCountInFiltered == 0)

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .frame(width: 22)

                    Text("Delete Selected")

                    Spacer()

                    Text("\(vm.selectedCountInFiltered)")
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedCountInFiltered == 0)

            if vm.selectedCountInFiltered > 0 {
                HStack {
                    Text("\(vm.selectedCountInFiltered) selected from \(vm.derived.totalMatchingCount) filtered animals.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.22))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Row Card

private struct AnimalDataRowCard: View, Equatable {
    let row: AnimalDataViewModel.AnimalRowModel
    let isSelected: Bool
    let isSelectionMode: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isSelectionMode == rhs.isSelectionMode
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .padding(.top, 2)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)

                Text("🐑")
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(row.animal.eidRaw)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(eidTextColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(eidPillFill)
                        .clipShape(Capsule())

                    Spacer(minLength: 8)

                    Text(row.farmName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 8) {
                        rowPill(row.sexName)
                        rowPill(row.mobName)
                        rowPill(row.className)
                        rowPill(row.yearText)
                        rowPill(row.totalLambsText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    rowMetaPill(row.lastScanText, icon: "clock.fill")
                }

                if let pregValue = row.pregValue {
                    HStack(spacing: 8) {
                        rowMetaPill("Preg \(pregValue)", icon: "number.circle.fill")
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.18),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var eidPillFill: Color {
        guard let color = colorFromHex(row.mobColorHex) else {
            return Color.primary.opacity(0.08)
        }
        return color
    }

    private var eidTextColor: Color {
        guard let color = colorFromHex(row.mobColorHex) else {
            return .primary
        }
        return idealTextColor(for: color)
    }

    @ViewBuilder
    private func rowPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func rowMetaPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func colorFromHex(_ hex: String?) -> Color? {
        guard var cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else { return nil }

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

    private func idealTextColor(for color: Color) -> Color {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .white
        }

        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.7 ? .black : .white
        #else
        return .white
        #endif
    }
}

// MARK: - Styling + Actions

private extension AnimalDataView {

    var sexOptions: [String] {
        Array(
            Set(
                store.animals.compactMap { animal in
                    let raw = animal.sex?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return raw.isEmpty ? nil : raw
                }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var mobOptions: [String] {
        Array(
            Set(
                store.mobs.map { mob in
                    mob.name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var classOptions: [String] {
        Array(
            Set(
                store.animals.compactMap { animal in
                    let raw = animal.klass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return raw.isEmpty ? nil : raw
                }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var activeFilterCount: Int {
        var count = 0
        if !vm.selectedFarmIDs.isEmpty { count += 1 }
        if !vm.selectedSexes.isEmpty { count += 1 }
        if !vm.selectedMobNames.isEmpty { count += 1 }
        if !vm.selectedClasses.isEmpty { count += 1 }
        if !vm.searchText.isEmpty { count += 1 }
        if vm.sortKey != .updatedAt || vm.sortAscending { count += 1 }
        return count
    }

    var resultsTitle: String {
        if vm.derived.totalMatchingCount > vm.derived.visibleCount {
            return "Animals (\(vm.derived.visibleCount) of \(vm.derived.totalMatchingCount))"
        }
        return "Animals (\(vm.derived.totalMatchingCount))"
    }

    var sortSummaryText: String {
        "\(vm.sortKey.rawValue) · \(vm.sortAscending ? "Ascending" : "Descending")"
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.001))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var cardStroke: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.22))
    }

    var softFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    var isBulkEditReadyToApply: Bool {
        guard vm.selectedCountInFiltered > 0 else { return false }

        if selectedBulkMode == .clear {
            return true
        }

        switch selectedBulkField {
        case .animalClass, .sex, .status:
            return true

        case .mob:
            return !pendingBulkMobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .breed:
            return !pendingBulkBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .birthYear:
            return Int(pendingBulkBirthYear.trimmingCharacters(in: .whitespacesAndNewlines)) != nil

        case .birthMonth:
            return (1...12).contains(pendingBulkBirthMonth)

        case .comments:
            return !pendingBulkComments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .userField1:
            return !pendingBulkUserField1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        case .userField2:
            return !pendingBulkUserField2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func clearFilters() {
        vm.clearAllFilters()
        vm.updateSearchText("")
        vm.sortKey = .updatedAt
        vm.sortAscending = false
        showSearchField = false
    }

    func resetBulkEditDraft() {
        selectedBulkField = .animalClass
        selectedBulkMode = .replace
        pendingBulkClass = .flock
        pendingBulkSex = .ewe
        pendingBulkStatus = .dry
        pendingBulkMobName = mobOptions.first ?? ""
        pendingBulkBreed = ""
        pendingBulkBirthYear = ""
        pendingBulkBirthMonth = 1
        pendingBulkComments = ""
        pendingBulkUserField1 = ""
        pendingBulkUserField2 = ""
    }

    var deleteConfirmationTitle: String {
        "Delete \(vm.selectedAnimalIDs.count) animals?"
    }

    var deleteConfirmationMessage: String {
        "This will permanently delete selected animals."
    }

    var bulkEditConfirmationTitle: String {
        "Apply bulk edit to \(vm.selectedCountInFiltered) animals?"
    }

    var bulkEditConfirmationMessage: String {
        if selectedBulkMode == .clear {
            return "This will clear \(selectedBulkField.label) for the selected animals."
        }

        switch selectedBulkField {
        case .animalClass:
            return "This will change Class to \(pendingBulkClass.label)."
        case .sex:
            return "This will change Sex to \(pendingBulkSex.label)."
        case .status:
            return "This will change Status to \(pendingBulkStatus.label)."
        case .mob:
            return "This will change Mob to \(pendingBulkMobName)."
        case .breed:
            return "This will change Breed to \(pendingBulkBreed)."
        case .birthYear:
            return "This will change Birth Year to \(pendingBulkBirthYear)."
        case .birthMonth:
            return "This will change Birth Month to \(pendingBulkBirthMonth)."
        case .comments:
            return "This will replace Comments for the selected animals."
        case .userField1:
            return "This will replace User Field 1 for the selected animals."
        case .userField2:
            return "This will replace User Field 2 for the selected animals."
        }
    }

    func deleteSelectedAnimals() {
        store.deleteAnimals(ids: Array(vm.selectedAnimalIDs))
        vm.selectedAnimalIDs.removeAll()
        isSelecting = false
    }

    func applyBulkEdit() {
        let ids = Array(vm.selectedAnimalIDs)
        guard !ids.isEmpty else { return }

        switch selectedBulkField {
        case .animalClass:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalClass(ids: ids, to: nil)
            } else {
                store.bulkUpdateAnimalClass(ids: ids, to: pendingBulkClass)
            }

        case .sex:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalSex(ids: ids, to: nil)
            } else {
                store.bulkUpdateAnimalSex(ids: ids, to: pendingBulkSex)
            }

        case .status:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalStatus(ids: ids, to: nil)
            } else {
                store.bulkUpdateAnimalStatus(ids: ids, to: pendingBulkStatus)
            }

        case .mob:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalMob(ids: ids, toMobName: nil)
            } else {
                store.bulkUpdateAnimalMob(ids: ids, toMobName: pendingBulkMobName)
            }

        case .breed:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalBreed(ids: ids, to: nil)
            } else {
                store.bulkUpdateAnimalBreed(ids: ids, to: pendingBulkBreed)
            }

        case .birthYear:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalBirthYear(ids: ids, to: nil)
            } else if let year = Int(pendingBulkBirthYear.trimmingCharacters(in: .whitespacesAndNewlines)) {
                store.bulkUpdateAnimalBirthYear(ids: ids, to: year)
            }

        case .birthMonth:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalBirthMonth(ids: ids, to: nil)
            } else {
                store.bulkUpdateAnimalBirthMonth(ids: ids, to: pendingBulkBirthMonth)
            }

        case .comments:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalNotes(ids: ids, comments: nil, userField1: nil, userField2: nil, target: .comments, clear: true)
            } else {
                store.bulkUpdateAnimalNotes(ids: ids, comments: pendingBulkComments, userField1: nil, userField2: nil, target: .comments, clear: false)
            }

        case .userField1:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalNotes(ids: ids, comments: nil, userField1: nil, userField2: nil, target: .userField1, clear: true)
            } else {
                store.bulkUpdateAnimalNotes(ids: ids, comments: nil, userField1: pendingBulkUserField1, userField2: nil, target: .userField1, clear: false)
            }

        case .userField2:
            if selectedBulkMode == .clear {
                store.bulkUpdateAnimalNotes(ids: ids, comments: nil, userField1: nil, userField2: nil, target: .userField2, clear: true)
            } else {
                store.bulkUpdateAnimalNotes(ids: ids, comments: nil, userField1: nil, userField2: pendingBulkUserField2, target: .userField2, clear: false)
            }
        }

        vm.selectedAnimalIDs.removeAll()
        isSelecting = false
        vm.recomputeDerivedData()
    }
}
