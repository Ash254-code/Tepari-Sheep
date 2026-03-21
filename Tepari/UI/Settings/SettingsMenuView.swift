import SwiftUI
import UIKit

private let kEnableStapleMeasureKey = "enable_staple_measure"

// =====================================================
// MARK: - Legacy Settings screen
// =====================================================

struct LegacySettingsView: View {
    var body: some View {
        SettingsMenuView()
    }
}

struct SettingsMenuView: View {

    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var racewell: RacewellManager
    @EnvironmentObject private var stickReader: StickReaderManager

    private var needsOwnNavigationStack: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

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
                }
            } else {
                content
            }
        }
    }
    private var content: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    settingsSection(
                        title: "Connectivity",
                        subtitle: "Connections and device setup"
                    ) {
                        NavigationLink {
                            ConnectivityView()
                        } label: {
                            ModernSettingsRow(
                                icon: "bolt.horizontal.circle.fill",
                                iconTint: .blue,
                                title: "Connectivity",
                                subtitle: "T1, Racewell and stick reader setup"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(
                        title: "Data",
                        subtitle: "Animal records, imports and history"
                    ) {
                        NavigationLink {
                            CSVToolsView()
                        } label: {
                            ModernSettingsRow(
                                icon: "square.and.arrow.down.on.square.fill",
                                iconTint: .green,
                                title: "CSV Import / Export",
                                subtitle: "Import and export animal lists"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            AnimalDataView()
                        } label: {
                            ModernSettingsRow(
                                icon: "doc.text.fill",
                                iconTint: .orange,
                                title: "Animal Data",
                                subtitle: "Traits, profiles and drafting fields"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            TraitsQuickPicksSettingsView()
                        } label: {
                            ModernSettingsRow(
                                icon: "slider.horizontal.3",
                                iconTint: .purple,
                                title: "Traits",
                                subtitle: "Edit micron, staple and custom quick picks"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SessionListView()
                        } label: {
                            ModernSettingsRow(
                                icon: "clock.arrow.circlepath",
                                iconTint: .cyan,
                                title: "History",
                                subtitle: "Past sessions and saved weights"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(
                        title: "Operations",
                        subtitle: "Reusable setup data and livestock workflow"
                    ) {
                        NavigationLink {
                            FarmSetupView()
                        } label: {
                            ModernSettingsRow(
                                icon: "building.2.crop.circle.fill",
                                iconTint: .green,
                                title: "Farms",
                                subtitle: "Add and manage farms and yards (PIC)"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            MobSetupViewEntry()
                        } label: {
                            ModernSettingsRow(
                                icon: "hare.fill",
                                iconTint: .teal,
                                title: "Mobs",
                                subtitle: "Manage mobs and import CSV animals"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ProgrammedTagsEntry()
                        } label: {
                            ModernSettingsRow(
                                icon: "tag.fill",
                                iconTint: .pink,
                                title: "Programmed Tags",
                                subtitle: "Assign a tag a default sex"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            TreatmentPresetsView()
                        } label: {
                            ModernSettingsRow(
                                icon: "cross.case.fill",
                                iconTint: .red,
                                title: "Treatment Presets",
                                subtitle: "Create reusable treatments for session setup"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            AnimalClassesView()
                        } label: {
                            ModernSettingsRow(
                                icon: "square.text.square.fill",
                                iconTint: .indigo,
                                title: "Animal Classes",
                                subtitle: "Create reusable classes for session setup"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(
                        title: "App",
                        subtitle: "Behaviour, haptics, audio and tools"
                    ) {
                        NavigationLink {
                            AppSettingsView()
                        } label: {
                            ModernSettingsRow(
                                icon: "gearshape.fill",
                                iconTint: .gray,
                                title: "Settings",
                                subtitle: "Haptics, audio and app behaviour"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .safeAreaPadding(.bottom, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            GlassCard {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    private func settingsBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

// =====================================================
// MARK: - Nav bar pills helper
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

// =====================================================
// MARK: - Modern Settings Row
// =====================================================

private struct ModernSettingsRow: View {

    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconTint.opacity(0.14))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// =====================================================
// MARK: - Treatment Presets
// =====================================================

private struct TreatmentPresetsView: View {

    @EnvironmentObject private var presetStore: TreatmentPresetStore

    @State private var showAdd = false
    @State private var editing: TreatmentPresetStore.TreatmentPreset?

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Treatment Presets")
                                        .font(.title3.weight(.bold))

                                    Text("Reusable treatments for session setup.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    showAdd = true
                                } label: {
                                    Label("Add Preset", systemImage: "plus")
                                }
                                .glassButton(.compact, tint: .blue)
                            }
                        }
                    }
                    .padding(.top, 6)

                    if presetStore.presets.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No Treatment Presets")
                                    .font(.headline)

                                Text("Add presets here so they appear during New Session setup.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(presetStore.presets) { p in
                                presetRow(p)
                            }
                        }
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .safeAreaPadding(.bottom, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Treatment Presets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            TreatmentPresetEditor()
        }
        .sheet(item: $editing) { preset in
            TreatmentPresetEditor(existing: preset)
        }
    }

    private func presetRow(_ p: TreatmentPresetStore.TreatmentPreset) -> some View {
        Button {
            editing = p
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.14))
                            .frame(width: 42, height: 42)

                        Image(systemName: "cross.case.fill")
                            .foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(p.name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            if let amt = p.doseAmount?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !amt.isEmpty {

                                let unit = p.doseUnit ?? .mL
                                let basis = p.doseBasis ?? .perAnimal

                                switch basis {
                                case .perAnimal:
                                    metaPill("Dose: \(amt) \(unit.rawValue)")
                                case .perBodyWeight:
                                    let per = (p.dosePerKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let perClean = per.isEmpty ? "10" : per
                                    metaPill("Dose: \(amt) \(unit.rawValue) / \(perClean)kg")
                                }
                            }

                            if let days = p.defaultWithholdingDays {
                                metaPill("Withholding: \(days)d")
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                presetStore.delete(p)
            } label: {
                Label("Delete Preset", systemImage: "trash")
            }
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

// =====================================================
// MARK: - Animal Classes
// =====================================================

private struct AnimalClassesView: View {

    @EnvironmentObject private var classStore: AnimalClassStore

    @State private var showAdd = false
    @State private var editing: AnimalClassStore.AnimalClass?

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Animal Classes")
                                        .font(.title3.weight(.bold))

                                    Text("Reusable classes that appear during New Session setup.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    showAdd = true
                                } label: {
                                    Label("Add Class", systemImage: "plus")
                                }
                                .glassButton(.compact, tint: .blue)
                            }
                        }
                    }
                    .padding(.top, 6)

                    if classStore.classes.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No Animal Classes")
                                    .font(.headline)

                                Text("Add classes here so they appear during New Session setup.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(classStore.classes) { c in
                                classRow(c)
                            }
                        }
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .safeAreaPadding(.bottom, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Animal Classes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AnimalClassEditor()
        }
        .sheet(item: $editing) { item in
            AnimalClassEditor(existing: item)
        }
    }

    private func classRow(_ c: AnimalClassStore.AnimalClass) -> some View {
        Button {
            editing = c
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.indigo.opacity(0.14))
                            .frame(width: 42, height: 42)

                        Image(systemName: "square.text.square.fill")
                            .foregroundStyle(.indigo)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(c.name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            if let sex = c.defaultSex, !sex.isEmpty {
                                metaPill("Default: \(sex)")
                            }

                            if let notes = c.notes, !notes.isEmpty {
                                metaPill(notes)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                classStore.delete(c)
            } label: {
                Label("Delete Class", systemImage: "trash")
            }
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

// =====================================================
// MARK: - App Settings
// =====================================================

private struct AppSettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @AppStorage(kEnableStapleMeasureKey) private var enableStapleMeasure = false

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("App Settings")
                                .font(.title3.weight(.bold))

                            Text("Control feedback, audio and experimental tools.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Haptics")
                                .font(.headline)

                            Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Strength")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Picker("Strength", selection: $settings.hapticStrength) {
                                    ForEach(AppSettings.HapticStrength.allCases, id: \.self) { s in
                                        Text(s.label).tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .disabled(!settings.hapticsEnabled)
                                .opacity(settings.hapticsEnabled ? 1 : 0.45)
                            }

                            Text("Tip: set to Heavy if you’re using gloves at the yards.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Audio")
                                .font(.headline)

                            NavigationLink {
                                AudioSetupView()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.green.opacity(0.14))
                                            .frame(width: 42, height: 42)

                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundStyle(.green)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Audio Setup")
                                            .font(.headline)

                                        Text("Sounds, alerts and volume")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Experimental")
                                .font(.headline)

                            Toggle("Staple Length Tool", isOn: $enableStapleMeasure)

                            Text("Shows the temporary ruler button on the Session screen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .safeAreaPadding(.bottom, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// =====================================================
// MARK: - Shared pill
// =====================================================

private func metaPill(_ text: String) -> some View {
    Text(text)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
}

// =====================================================
// MARK: - Programmed Tags entry
// =====================================================

private struct ProgrammedTagsEntry: View {
    @EnvironmentObject private var store: LocalDataStore

    var body: some View {
        Group {
            if store.farms.isEmpty {
                ContentUnavailableView(
                    "No Farms",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Add a farm before programming tags.")
                )
            } else {
                ProgrammedTagsView()
            }
        }
        .navigationTitle("Programmed Tags")
    }
}
// =====================================================
// MARK: - Mob setup entry
// =====================================================

private struct MobSetupViewEntry: View {
    var body: some View {
        MobsOverviewView()
            .navigationTitle("Mobs")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// =====================================================
// MARK: - Farm Picker
// =====================================================

private struct FarmPickerSimple: View {

    let farms: [LocalDataStore.Farm]
    let onPick: (UUID) -> Void

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(farms) { farm in
                        Button {
                            onPick(farm.id)
                        } label: {
                            GlassCard {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.green.opacity(0.14))
                                            .frame(width: 42, height: 42)

                                        Image(systemName: "building.2.crop.circle.fill")
                                            .foregroundStyle(.green)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(farm.name)
                                            .font(.headline)

                                        Text("PIC: \(farm.pic)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
