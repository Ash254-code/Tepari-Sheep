import SwiftUI

/// Step 1: Farm selection ONLY.
/// (Yards + Session name moved to later steps)
struct SessionSetupFarmStepView: View {

    // =========================================================
    // MARK: Environment
    // =========================================================

    @EnvironmentObject private var store: LocalDataStore

    // =========================================================
    // MARK: Bindings (owned by SessionSetupView)
    // =========================================================

    @Binding var selectedFarmID: UUID?
    @Binding var manualFarmName: String

    // =========================================================
    // MARK: Actions
    // =========================================================

    /// ✅ Wizard container injects this (same thing your Next button does)
    let onAutoNext: () -> Void

    // =========================================================
    // MARK: Local State
    // =========================================================

    @State private var showManualEntry: Bool = false
    @State private var didAutoAdvance: Bool = false

    /// ✅ used to give a little “selected” pulse + delay before advancing
    @State private var pendingAutoNextWork: DispatchWorkItem? = nil

    // =========================================================
    // MARK: Tuning
    // =========================================================

    private let selectionPulseDuration: Double = 0.6
    private let autoAdvanceDelay: Double = 0.2   // “split second” so you see the highlight

    // =========================================================
    // MARK: Derived
    // =========================================================

    private var hasFarmsConfigured: Bool { !store.farms.isEmpty }

    // =========================================================
    // MARK: Body
    // =========================================================

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 0) {

                if hasFarmsConfigured && !showManualEntry {

                    WizardTileGrid(
                        title: "Which Farm?",
                        caption: "Select where today’s session belongs.",
                        tiles: farmTiles,
                        selection: farmSelectionBinding,
                        allowsMultipleSelection: false,
                        onSelectionChanged: { sel in
                            // ✅ Only auto-advance on a real farm selection
                            guard let first = sel.first,
                                  first != "__add_farm__",
                                  let uuid = UUID(uuidString: first) else { return }

                            guard !didAutoAdvance else { return }
                            didAutoAdvance = true

                            // ✅ cancel any previous pending auto-next
                            pendingAutoNextWork?.cancel()

                            // ✅ Ensure the selection animates in before we move on
                            withAnimation(.spring(response: selectionPulseDuration, dampingFraction: 1.0)) {
                                selectedFarmID = uuid
                                manualFarmName = ""
                            }

                            let work = DispatchWorkItem {
                                onAutoNext()
                            }
                            pendingAutoNextWork = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + autoAdvanceDelay, execute: work)
                        }
                    )

                } else {
                    noFarmsManualEntryCard
                        .padding(16)
                }
            }
        }
        .onAppear {
            didAutoAdvance = false
            pendingAutoNextWork?.cancel()
            pendingAutoNextWork = nil
        }
        .onDisappear {
            // ✅ if user navigates back quickly, don’t fire auto-next later
            pendingAutoNextWork?.cancel()
            pendingAutoNextWork = nil
        }
        .onChange(of: manualFarmName) { _, newValue in
            // If they start typing, make sure we’re in manual entry mode.
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showManualEntry = true
                selectedFarmID = nil
            }
        }
        .onChange(of: selectedFarmID) { _, _ in
            // if they come back and change selection, allow auto-advance again
            if !showManualEntry {
                didAutoAdvance = false
            }
        }
    }

    // =========================================================
    // MARK: No farms / manual entry
    // =========================================================

    private var noFarmsManualEntryCard: some View {
        stepCard(
            title: "Which Farm?",
            subtitle: hasFarmsConfigured ? "Enter a new farm name." : "No farms exist yet — enter one now."
        ) {
            VStack(alignment: .leading, spacing: 12) {

                Text("You can manage farms later in Setup → Farms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Farm name", text: $manualFarmName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                if hasFarmsConfigured {
                    Button {
                        // go back to tile selection
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showManualEntry = false
                            manualFarmName = ""
                            didAutoAdvance = false
                        }
                    } label: {
                        Label("Back to farm list", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // =========================================================
    // MARK: Tiles + Binding
    // =========================================================

    private var farmTiles: [WizardTile] {
        let farms = Array(store.farms.prefix(8))

        return farms.map { f in
            WizardTile(
                id: f.id.uuidString,
                title: f.name,
                systemImage: "leaf.fill",
                subtitle: f.pic.isEmpty ? "No PIC saved" : "PIC \(f.pic)"
            )
        }
    }

    private var farmSelectionBinding: Binding<Set<String>> {
        Binding<Set<String>>(
            get: {
                guard let id = selectedFarmID else { return [] }
                return [id.uuidString]
            },
            set: { newSet in
                guard let first = newSet.first else {
                    selectedFarmID = nil
                    return
                }

                if first == "__add_farm__" {
                    // Switch to manual entry
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showManualEntry = true
                        selectedFarmID = nil
                        manualFarmName = ""
                        didAutoAdvance = false
                    }
                    return
                }

                // Normal selection (no auto-advance here anymore; handled in onSelectionChanged)
                if let uuid = UUID(uuidString: first) {
                    selectedFarmID = uuid
                    manualFarmName = ""
                } else {
                    selectedFarmID = nil
                }
            }
        )
    }

    // =========================================================
    // MARK: Small shared helper (local copy)
    // =========================================================

    private func stepCard(title: String, subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Divider().opacity(0.18)

                content()
            }
        }
    }
}
