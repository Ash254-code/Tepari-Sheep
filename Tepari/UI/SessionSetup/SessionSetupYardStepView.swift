import SwiftUI

/// Step: Yard selection (same tile style as Farms/Equipment).
struct SessionSetupYardStepView: View {

    @EnvironmentObject private var store: LocalDataStore

    @Binding var selectedFarmID: UUID?
    @Binding var selectedYard: String?

    /// ✅ Wizard container injects this (same thing your Next button does)
    let onAutoNext: () -> Void

    @State private var didAutoAdvance: Bool = false
    @State private var pendingAutoNextWork: DispatchWorkItem? = nil

    // ✅ match Farm feel
    private let selectionPulseDuration: Double = 0.6
    private let autoAdvanceDelay: Double = 0.2

    private var selectedFarm: LocalDataStore.Farm? {
        guard let id = selectedFarmID else { return nil }
        return store.farms.first(where: { $0.id == id })
    }

    private var yardsForSelectedFarm: [String] {
        guard let farmID = selectedFarmID else { return [] }
        // Sorted = predictable + feels cleaner
        return YardLocationStore
            .list(for: farmID)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {

            WizardTileGrid(
                title: "Yard location",
                caption: captionText,
                tiles: yardTiles,
                selection: yardSelectionBinding,
                allowsMultipleSelection: false,
                onSelectionChanged: { sel in
                    guard selectedFarmID != nil else { return }
                    guard let first = sel.first else { return }

                    guard !didAutoAdvance else { return }
                    didAutoAdvance = true

                    pendingAutoNextWork?.cancel()

                    // ✅ animate the selected state so user sees it
                    withAnimation(.spring(response: selectionPulseDuration, dampingFraction: 1.0)) {
                        if first == "__none__" {
                            selectedYard = nil
                        } else {
                            selectedYard = first
                        }
                    }

                    let work = DispatchWorkItem { onAutoNext() }
                    pendingAutoNextWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + autoAdvanceDelay, execute: work)
                }
            )
            .onChange(of: selectedFarmID) { _, _ in
                // ✅ Farm changed → clear yard + allow auto-advance again
                selectedYard = nil
                didAutoAdvance = false
                pendingAutoNextWork?.cancel()
                pendingAutoNextWork = nil
            }
            .onAppear {
                didAutoAdvance = false
                pendingAutoNextWork?.cancel()
                pendingAutoNextWork = nil
            }
            .onDisappear {
                pendingAutoNextWork?.cancel()
                pendingAutoNextWork = nil
            }
        }
    }

    private var captionText: String {
        if selectedFarmID == nil {
            return "Select a farm first."
        }
        if yardsForSelectedFarm.isEmpty {
            return "No saved yards for this farm yet. Add them in Farms → + Add. You can skip for now."
        }
        if let f = selectedFarm {
            return "Farm: \(f.name)"
        }
        return "Choose the yard location for this session."
    }

    private var yardTiles: [WizardTile] {
        var tiles: [WizardTile] = []

        // ✅ Add actual yards FIRST
        tiles += yardsForSelectedFarm.map { yard in
            WizardTile(
                id: yard,
                title: yard,
                systemImage: "mappin.and.ellipse"
            )
        }

        // ✅ Add None/Skip LAST (best UX)
        tiles.append(
            WizardTile(
                id: "__none__",
                title: "None / Skip",
                systemImage: "minus.circle",
            )
        )

        return tiles
    }

    private var yardSelectionBinding: Binding<Set<String>> {
        Binding<Set<String>>(
            get: {
                // If no yard selected, highlight None/Skip
                if let yard = selectedYard, !yard.isEmpty {
                    return [yard]
                }
                return ["__none__"]
            },
            set: { newSet in
                guard let first = newSet.first else {
                    selectedYard = nil
                    return
                }

                if first == "__none__" {
                    selectedYard = nil
                } else {
                    selectedYard = first
                }
            }
        )
    }
}
