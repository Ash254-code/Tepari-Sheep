import SwiftUI
import UIKit

private let kEnableStapleMeasureKey = "enable_staple_measure"

/// ✅ Legacy Settings screen.
/// Routes to the new Settings hub screen.
struct LegacySettingsView: View {
    var body: some View {
        SettingsMenuView()
    }
}

struct SettingsMenuView: View {

    // ✅ For connectivity pills in the NAV BAR (keeps Back button correct)
    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var racewell: RacewellManager
    @EnvironmentObject private var stickReader: StickReaderManager

    // ✅ iPad needs a NavigationStack or NavigationLinks won’t navigate (often appear “dead”)
    private var needsOwnNavigationStack: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // MARK: - Connection states for pills

    private var handlerState: ConnectionState {
        transport.method == .demo ? .connected : transport.state
    }

    private var draftState: ConnectionState { racewell.state }
    private var stickState: ConnectionState { stickReader.state }

    var body: some View {
        Group {
            if needsOwnNavigationStack {
                NavigationStack {
                    content
                        .applyNavBarPills(
                            handlerState: handlerState,
                            draftState: draftState,
                            stickState: stickState
                        )
                }
            } else {
                // iPhone: usually already inside a NavigationStack from the tab/root
                content
                    .applyNavBarPills(
                        handlerState: handlerState,
                        draftState: draftState,
                        stickState: stickState
                    )
            }
        }
    }

    private var content: some View {
        ZStack {
            GlassBackground()
                .allowsHitTesting(false)

            List {

                // =====================================================
                // CONNECTIVITY (TOP CARD)
                // =====================================================
                Section("Connectivity") {
                    NavigationLink {
                        ConnectivityView()
                    } label: {
                        SettingsRow(
                            title: "⚡ Connectivity",
                            subtitle: "T1, Racewell and stick reader setup"
                        )
                    }
                }

                // =====================================================
                // Data
                // =====================================================
                Section("Data") {

                    NavigationLink {
                        CSVToolsView()
                    } label: {
                        SettingsRow(
                            title: "🧾 CSV Import / Export",
                            subtitle: "Import and export animal lists"
                        )
                    }

                    NavigationLink {
                        AnimalDataView()
                    } label: {
                        SettingsRow(
                            title: "📄 Animal Data",
                            subtitle: "Traits, profiles and drafting fields"
                        )
                    }

                    NavigationLink {
                        TraitsQuickPicksSettingsView()
                    } label: {
                        SettingsRow(
                            title: "📈 Traits",
                            subtitle: "Edit quick add chips (micron + staple)"
                        )
                    }

                    NavigationLink {
                        SessionListView()
                    } label: {
                        SettingsRow(
                            title: "🕒 History",
                            subtitle: "Past sessions and saved weights"
                        )
                    }
                }

                // =====================================================
                // Operations
                // =====================================================
                Section("Operations") {

                    NavigationLink {
                        FarmSetupView()
                    } label: {
                        SettingsRow(
                            title: "🚜 Farms",
                            subtitle: "Add and manage farms and yards (PIC)"
                        )
                    }

                    NavigationLink {
                        MobSetupViewEntry()
                    } label: {
                        SettingsRow(
                            title: "🐑 Mobs",
                            subtitle: "Manage mobs and import CSV animals"
                        )
                    }

                    NavigationLink {
                        ProgrammedTagsEntry()
                    } label: {
                        SettingsRow(
                            title: "🏷️ Programmed Tags",
                            subtitle: "Assign a tag a default sex (Ewe/Wether/Ram)"
                        )
                    }

                    NavigationLink {
                        TreatmentPresetsView()
                    } label: {
                        SettingsRow(
                            title: "💉 Treatment Presets",
                            subtitle: "Create reusable treatments for session setup"
                        )
                    }

                    NavigationLink {
                        AnimalClassesView()
                    } label: {
                        SettingsRow(
                            title: "🏷️ Animal Classes",
                            subtitle: "Create reusable animal classes for session setup"
                        )
                    }
                }

                // =====================================================
                // Settings
                // =====================================================
                Section("Settings") {

                    NavigationLink {
                        AppSettingsView()
                    } label: {
                        SettingsRow(
                            title: "⚙️ Settings",
                            subtitle: "Haptics, audio and app behaviour"
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// =====================================================
// MARK: - Nav bar pills helper (keeps code DRY)
// =====================================================

private extension View {
    func applyNavBarPills(
        handlerState: ConnectionState,
        draftState: ConnectionState,
        stickState: ConnectionState
    ) -> some View {

        self.modifier(
            NavBarConnectivityPillsModifier(
                handlerState: handlerState,
                draftState: draftState,
                stickState: stickState
            )
        )
    }
}

private struct NavBarConnectivityPillsModifier: ViewModifier {
    let handlerState: ConnectionState
    let draftState: ConnectionState
    let stickState: ConnectionState

    @State private var showConnectivity = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConnectivity = true
                    } label: {
                        GlobalConnectionOverlay(
                            handlerState: handlerState,
                            draftState: draftState,
                            stickState: stickState,
                            xrp2iState: .disconnected,
                            gunState: .disconnected,
                            useHandler: true,
                            useDraft: true,
                            useStick: true,
                            useXrp2i: true,
                            useGun: true
                        )
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Connectivity")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.thinMaterial, for: .navigationBar)
            .sheet(isPresented: $showConnectivity) {
                NavigationStack {
                    ConnectivityView()
                }
            }
    }
}

//
// MARK: - Treatment Presets (REAL)
//

private struct TreatmentPresetsView: View {

    @EnvironmentObject private var presetStore: TreatmentPresetStore

    @State private var showAdd = false
    @State private var editing: TreatmentPresetStore.TreatmentPreset?

    var body: some View {
        List {
            if presetStore.presets.isEmpty {
                ContentUnavailableView(
                    "No Treatment Presets",
                    systemImage: "cross.case.fill",
                    description: Text("Add presets here so they appear during New Session setup.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(presetStore.presets) { p in
                    Button {
                        editing = p
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name)
                                .font(.headline)

                            HStack(spacing: 10) {
                                if let amt = p.doseAmount?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !amt.isEmpty {

                                    let unit = p.doseUnit ?? .mL
                                    let basis = p.doseBasis ?? .perAnimal

                                    switch basis {
                                    case .perAnimal:
                                        Text("Dose: \(amt) \(unit.rawValue)")
                                    case .perBodyWeight:
                                        let per = (p.dosePerKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
                                        let perClean = per.isEmpty ? "10" : per
                                        Text("Dose: \(amt) \(unit.rawValue) / \(perClean)kg")
                                    }
                                }

                                if let days = p.defaultWithholdingDays {
                                    Text("Withholding: \(days)d")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let items = indexSet.map { presetStore.presets[$0] }
                    items.forEach { presetStore.delete($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Treatment Presets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showAdd) {
            TreatmentPresetEditor()
        }
        .sheet(item: $editing) { preset in
            TreatmentPresetEditor(existing: preset)
        }
    }
}

private struct TreatmentPresetEditor: View {

    @EnvironmentObject private var presetStore: TreatmentPresetStore
    @Environment(\.dismiss) private var dismiss

    private let existing: TreatmentPresetStore.TreatmentPreset?

    @State private var name: String
    @State private var doseAmount: String
    @State private var doseUnit: DoseUnit
    @State private var doseBasis: DoseBasis
    @State private var dosePerKg: String
    @State private var withholdingDaysText: String

    init(existing: TreatmentPresetStore.TreatmentPreset? = nil) {
        self.existing = existing

        _name = State(initialValue: existing?.name ?? "")
        _doseAmount = State(initialValue: existing?.doseAmount ?? "")
        _doseUnit = State(initialValue: existing?.doseUnit ?? .mL)
        _doseBasis = State(initialValue: existing?.doseBasis ?? .perAnimal)
        _dosePerKg = State(initialValue: existing?.dosePerKg ?? "10")

        if let d = existing?.defaultWithholdingDays {
            _withholdingDaysText = State(initialValue: String(d))
        } else {
            _withholdingDaysText = State(initialValue: "")
        }
    }

    private var parsedWithholdingDays: Int? {
        let t = withholdingDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return Int(t)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let amt = doseAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAmt = !amt.isEmpty

        let basis = doseBasis
        let perKgClean = dosePerKg.trimmingCharacters(in: .whitespacesAndNewlines)

        let preset = TreatmentPresetStore.TreatmentPreset(
            id: existing?.id ?? UUID(),
            name: cleanName,
            doseAmount: hasAmt ? amt : nil,
            doseUnit: hasAmt ? doseUnit : nil,
            doseBasis: hasAmt ? basis : nil,
            dosePerKg: (hasAmt && basis == .perBodyWeight) ? (perKgClean.isEmpty ? "10" : perKgClean) : nil,
            defaultWithholdingDays: parsedWithholdingDays
        )

        if existing == nil {
            presetStore.add(preset)
        } else {
            presetStore.update(preset)
        }

        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Treatment") {
                    TextField("Name", text: $name)

                    HStack {
                        TextField("Dose amount", text: $doseAmount)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif

                        Picker("Unit", selection: $doseUnit) {
                            ForEach(DoseUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 110)
                    }

                    Picker("Dose applies", selection: $doseBasis) {
                        Text("Per animal").tag(DoseBasis.perAnimal)
                        Text("Per body weight").tag(DoseBasis.perBodyWeight)
                    }
                    .pickerStyle(.segmented)
                    .disabled(doseAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if doseBasis == .perBodyWeight,
                       !doseAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                        HStack {
                            Text("Per")
                            TextField("10", text: $dosePerKg)
#if os(iOS)
                                .keyboardType(.numberPad)
#endif
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                            Text("kg")
                        }
                    }
                }

                Section("Withholding") {
                    TextField("Withholding Days (optional)", text: $withholdingDaysText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            if let ex = existing {
                                presetStore.delete(ex)
                            }
                            dismiss()
                        } label: {
                            Text("Delete Preset")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Preset" : "Edit Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }
}

//
// MARK: - Animal Classes (REAL)
//

private struct AnimalClassesView: View {

    @EnvironmentObject private var classStore: AnimalClassStore

    @State private var showAdd = false
    @State private var editing: AnimalClassStore.AnimalClass?

    var body: some View {
        List {
            if classStore.classes.isEmpty {
                ContentUnavailableView(
                    "No Animal Classes",
                    systemImage: "tag.fill",
                    description: Text("Add classes here so they appear during New Session setup.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(classStore.classes) { c in
                    Button {
                        editing = c
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.name)
                                .font(.headline)

                            if let sex = c.defaultSex, !sex.isEmpty {
                                Text("Default: \(sex)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let notes = c.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    let items = indexSet.map { classStore.classes[$0] }
                    items.forEach { classStore.delete($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Animal Classes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showAdd) {
            AnimalClassEditor()
        }
        .sheet(item: $editing) { item in
            AnimalClassEditor(existing: item)
        }
    }
}

private struct AnimalClassEditor: View {

    @EnvironmentObject private var classStore: AnimalClassStore
    @Environment(\.dismiss) private var dismiss

    private let existing: AnimalClassStore.AnimalClass?

    @State private var name: String
    @State private var defaultSex: String
    @State private var notes: String

    init(existing: AnimalClassStore.AnimalClass? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _defaultSex = State(initialValue: existing?.defaultSex ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private let sexOptions: [String] = ["Ewe", "Wether", "Ram", "Unknown"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Default Sex", selection: $defaultSex) {
                        Text("—").tag("")
                        ForEach(sexOptions, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(existing == nil ? "New Class" : "Edit Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty else { return }

                        let cleanSex = defaultSex.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalSex: String? = cleanSex.isEmpty ? nil : cleanSex

                        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalNotes: String? = cleanNotes.isEmpty ? nil : cleanNotes

                        let item = AnimalClassStore.AnimalClass(
                            id: existing?.id ?? UUID(),
                            name: cleanName,
                            defaultSex: finalSex,
                            notes: finalNotes
                        )

                        if existing == nil {
                            classStore.add(item)
                        } else {
                            classStore.update(item)
                        }

                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

//
// MARK: - App Settings screen
//

private struct AppSettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @AppStorage(kEnableStapleMeasureKey) private var enableStapleMeasure = false

    var body: some View {
        List {
            Section("Haptics") {

                Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)

                Picker("Strength", selection: $settings.hapticStrength) {
                    ForEach(AppSettings.HapticStrength.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .disabled(!settings.hapticsEnabled)

                Text("Tip: set to Heavy if you’re using gloves at the yards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Audio") {
                NavigationLink {
                    AudioSetupView()
                } label: {
                    SettingsRow(
                        title: "🔊 Audio Setup",
                        subtitle: "Sounds, alerts and volume"
                    )
                }
            }

            Section("Experimental") {
                Toggle("Staple Length Tool", isOn: $enableStapleMeasure)

                Text("Shows the temporary ruler button on the Session screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("⚙️ Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

//
// MARK: - Row UI
//

private struct SettingsRow: View {

    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

//
// MARK: - Programmed Tags entry (farm picker)
//

private struct ProgrammedTagsEntry: View {

    @EnvironmentObject private var store: LocalDataStore
    @State private var selectedFarmID: UUID?

    var body: some View {
        Group {
            if store.farms.isEmpty {
                ContentUnavailableView(
                    "No Farms",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Add a farm before programming tags.")
                )
            } else if store.farms.count == 1 {
                ProgrammedTagsView(farmID: store.farms[0].id)
            } else if let farmID = selectedFarmID {
                ProgrammedTagsView(farmID: farmID)
            } else {
                FarmPickerSimple(
                    farms: store.farms,
                    onPick: { selectedFarmID = $0 }
                )
            }
        }
        .navigationTitle("Programmed Tags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

//
// MARK: - Mob setup entry
//

private struct MobSetupViewEntry: View {
    var body: some View {
        MobsOverviewView()
            .navigationTitle("Mobs")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FarmPickerSimple: View {

    let farms: [LocalDataStore.Farm]
    let onPick: (UUID) -> Void

    var body: some View {
        List(farms) { farm in
            Button {
                onPick(farm.id)
            } label: {
                VStack(alignment: .leading) {
                    Text(farm.name)
                    Text("PIC: \(farm.pic)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .scrollContentBackground(.hidden)
        .navigationBarTitleDisplayMode(.inline)
    }
}
