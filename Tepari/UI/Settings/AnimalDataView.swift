import SwiftUI

struct AnimalDataView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var vm = AnimalDataViewModel()
    @State private var didBindStore = false

    @State private var showSearchField: Bool = false
    @State private var showSortSheet: Bool = false
    @State private var isSelecting: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

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

        .onChange(of: vm.searchText) { _, _ in vm.recomputeDerivedData() }
        .onChange(of: vm.selectedFarmID) { _, _ in
            vm.reconcileFiltersAfterFarmOrMobChange()
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.filterMobName) { _, _ in
            vm.reconcileClassFilterIfNeeded()
            vm.recomputeDerivedData()
        }
        .onChange(of: vm.filterClass) { _, _ in vm.recomputeDerivedData() }
        .onChange(of: vm.sortKey) { _, _ in vm.recomputeDerivedData() }
        .onChange(of: vm.sortAscending) { _, _ in vm.recomputeDerivedData() }

        .onChange(of: store.farms) { _, _ in vm.recomputeDerivedData() }
        .onChange(of: store.mobs) { _, _ in vm.recomputeDerivedData() }
        .onChange(of: store.animals) { _, _ in vm.recomputeDerivedData() }
        .onChange(of: store.animalEvents) { _, _ in vm.recomputeDerivedData() }

        // 🚀 kill list animations (BIG WIN)
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

        .sheet(isPresented: $coordinator.showIndividualAnimalView) {
            IndividualAnimalView()
                .environmentObject(store)
                .environmentObject(coordinator)
        }

        .confirmationDialog("Sort Animals", isPresented: $showSortSheet) {
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

// MARK: - LIST

private extension AnimalDataView {

    func animalListView() -> some View {
        List {

            Section {
                headerCard
            }

            if isSelecting {
                Section {
                    bulkActionsCard
                }
            }

            Section(resultsTitle) {

                if vm.derived.rankedRows.isEmpty {
                    Text("No animals match your filters.")
                        .foregroundStyle(.secondary)
                }

                // 🚀 stable identity (IMPORTANT)
                ForEach(vm.derived.rankedRows, id: \.id) { row in

                    if isSelecting {
                        Button {
                            toggleSelection(for: row.id)
                        } label: {
                            AnimalRowView(
                                row: row,
                                isSelected: vm.selectedAnimalIDs.contains(row.id)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            coordinator.selectedIndividualAnimalEID = row.animal.eidRaw
                            coordinator.selectedIndividualAnimalFarmID = row.animal.farmID
                            coordinator.focusedEID = row.animal.eidRaw
                            coordinator.showIndividualAnimalView = true
                        } label: {
                            AnimalRowView(
                                row: row,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - HEADER

private extension AnimalDataView {

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Animal Data")
                .font(.headline)

            Text("\(vm.derived.totalMatchingCount) matching animals")
                .foregroundStyle(.secondary)

            HStack {
                Button(showSearchField ? "Hide Search" : "Search") {
                    showSearchField.toggle()
                    if !showSearchField {
                        vm.searchText = ""
                    }
                }

                Button("Sort") {
                    showSortSheet = true
                }

                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting {
                        vm.selectedAnimalIDs.removeAll()
                    }
                    isSelecting.toggle()
                }
            }

            if showSearchField {
                TextField(
                    "Search",
                    text: Binding(
                        get: { vm.searchText },
                        set: { vm.updateSearchText($0) }
                    )
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
    }
}

// MARK: - BULK

private extension AnimalDataView {

    var bulkActionsCard: some View {
        VStack {

            Button {
                if vm.allFilteredSelected {
                    vm.clearFilteredSelection()
                } else {
                    vm.selectAllFiltered()
                }
            } label: {
                Text(vm.allFilteredSelected ? "Clear All" : "Select All")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete Selected (\(vm.selectedCountInFiltered))")
            }
        }
    }
}


// MARK: - ACTIONS

private extension AnimalDataView {

    func toggleSelection(for id: UUID) {
        vm.toggleSelection(id)
    }

    var resultsTitle: String {
        "Animals (\(vm.derived.totalMatchingCount))"
    }

    var deleteConfirmationTitle: String {
        "Delete \(vm.selectedAnimalIDs.count) animals?"
    }

    var deleteConfirmationMessage: String {
        "This will permanently delete selected animals."
    }

    func deleteSelectedAnimals() {
        store.deleteAnimals(ids: Array(vm.selectedAnimalIDs))
        vm.selectedAnimalIDs.removeAll()
        isSelecting = false
    }
}
