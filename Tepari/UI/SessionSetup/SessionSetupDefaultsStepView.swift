import SwiftUI

// MARK: - Breed options for Defaults screen
enum BreedOption: String, CaseIterable, Identifiable, Codable, Hashable {
    case merino = "Merino"
    case british = "British"
    case other = "Other"

    var id: String { rawValue }
}

// MARK: - Month helpers (1...12)
private let monthSymbols: [String] = {
    let df = DateFormatter()
    df.locale = .current
    return df.monthSymbols
}()

private func monthLabel(_ m: Int) -> String {
    guard (1...12).contains(m) else { return "—" }
    return monthSymbols[m - 1]
}

/// Defaults step (no treatments)
struct SessionSetupDefaultsStepView: View {

    let selectedFarmID: UUID?
    let availableMobsForSelectedFarm: [LocalDataStore.Mob]

    // Defaults
    @Binding var selectedSex: LocalDataStore.Sex
    @Binding var selectedBreed: String
    @Binding var selectedMobName: String
    @Binding var selectedClass: LocalDataStore.AnimalClass
    @Binding var selectedBirthYear: Int?
    @Binding var selectedBirthMonth: Int?
    @Binding var selectedStatus: AnimalStatus?

    // Overwrite toggles
    @Binding var overwriteSex: Bool
    @Binding var overwriteBreed: Bool
    @Binding var overwriteMob: Bool
    @Binding var overwriteClass: Bool
    @Binding var overwriteBirthYear: Bool
    @Binding var overwriteBirthMonth: Bool
    @Binding var overwriteStatus: Bool

    // Confirm callbacks
    let onRequestOverwriteConfirmSex: () -> Void
    let onRequestOverwriteConfirmClass: () -> Void
    let onRequestOverwriteConfirmMob: () -> Void

    // Add mob prompt
    let addMobSentinel: String
    @Binding var showAddMobPrompt: Bool
    @Binding var newMobName: String

    private var birthYearOptions: [Int] {
        let year = Calendar.current.component(.year, from: Date())
        return (0...9).map { year - $0 }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)]
    }

    private var isMixedMobSelection: Bool {
        selectedMobName.isMobMixed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SessionSetupSimpleCardSteps.stepCard(
                    title: "Defaults for New Animals",
                    subtitle: "Used when a scanned tag is not already in Animal Data."
                ) {
                    VStack(alignment: .leading, spacing: 12) {

                        infoBlock

                        Divider().opacity(0.18)

                        LazyVGrid(columns: gridColumns, spacing: 12) {

                            defaultsRow(
                                title: "Sex",
                                overwrite: $overwriteSex,
                                onToggleOn: onRequestOverwriteConfirmSex
                            ) {
                                Picker("", selection: $selectedSex) {
                                    ForEach(LocalDataStore.Sex.allCases) { sex in
                                        Text(sex.label).tag(sex)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            defaultsRowSimple(
                                title: "Breed",
                                overwrite: $overwriteBreed
                            ) {
                                Picker("", selection: $selectedBreed) {
                                    ForEach(BreedOption.allCases, id: \.self) { breed in
                                        Text(breed.rawValue).tag(breed.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            defaultsRow(
                                title: "Mob",
                                overwrite: $overwriteMob,
                                overwriteDisabled: isMixedMobSelection,
                                overwriteDisabledReason: "Mixed preserves existing mobs.",
                                onToggleOn: onRequestOverwriteConfirmMob
                            ) {
                                mobPicker
                            }

                            defaultsRow(
                                title: "Class",
                                overwrite: $overwriteClass,
                                onToggleOn: onRequestOverwriteConfirmClass
                            ) {
                                Picker("", selection: $selectedClass) {
                                    ForEach(LocalDataStore.AnimalClass.allCases) { animalClass in
                                        Text(animalClass.label).tag(animalClass)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            defaultsRowSimple(
                                title: "Birth Year",
                                overwrite: $overwriteBirthYear
                            ) {
                                Picker("", selection: Binding(
                                    get: { selectedBirthYear ?? 0 },
                                    set: { selectedBirthYear = ($0 == 0 ? nil : $0) }
                                )) {
                                    Text("—").tag(0)
                                    ForEach(birthYearOptions, id: \.self) { year in
                                        Text(String(year)).tag(year)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            defaultsRowSimple(
                                title: "Birth Month",
                                overwrite: $overwriteBirthMonth
                            ) {
                                Picker("", selection: Binding(
                                    get: { selectedBirthMonth ?? 0 },
                                    set: { selectedBirthMonth = ($0 == 0 ? nil : $0) }
                                )) {
                                    Text("—").tag(0)
                                    ForEach(1...12, id: \.self) { month in
                                        Text(monthLabel(month)).tag(month)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            defaultsRowSimple(
                                title: "Current Status",
                                overwrite: $overwriteStatus
                            ) {
                                Picker("", selection: $selectedStatus) {
                                    Text("-").tag(Optional<AnimalStatus>.none)

                                    ForEach(AnimalStatus.allCases) { status in
                                        Text(status.label).tag(Optional(status))
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            if selectedBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedBreed = BreedOption.merino.rawValue
            }

            if selectedBirthMonth == nil {
                selectedBirthMonth = 5
            }

            if isMixedMobSelection {
                overwriteMob = false
            }
        }
        .onChange(of: selectedMobName) { _, newValue in
            if newValue.isMobMixed {
                overwriteMob = false
            }
        }
    }

    // MARK: - Info

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("• New animal: defaults are applied on create.")
            Text("• Existing animal: fields are not changed unless Overwrite is enabled.")
            Text("• If an existing animal has a blank field, the default can fill it.")
            if isMixedMobSelection {
                Text("• Mixed mob: existing animals keep their current mob. New animals are not assigned a mob from this setting.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Rows

    private func defaultsRow(
        title: String,
        overwrite: Binding<Bool>,
        overwriteDisabled: Bool = false,
        overwriteDisabledReason: String? = nil,
        onToggleOn: @escaping () -> Void,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                control()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { overwrite.wrappedValue },
                        set: { newValue in
                            if overwriteDisabled {
                                overwrite.wrappedValue = false
                                return
                            }

                            if newValue {
                                onToggleOn()
                            } else {
                                overwrite.wrappedValue = false
                            }
                        }
                    )
                )
                .labelsHidden()
                .disabled(overwriteDisabled)
                .opacity(overwriteDisabled ? 0.45 : 1)
            }

            HStack {
                Text("Overwrite")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if overwriteDisabled, let reason = overwriteDisabledReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func defaultsRowSimple(
        title: String,
        overwrite: Binding<Bool>,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                control()

                Toggle("", isOn: overwrite)
                    .labelsHidden()
            }

            Text("Overwrite")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Mob Picker

    private var mobPicker: some View {
        Picker(
            "",
            selection: Binding(
                get: { selectedMobName },
                set: { newValue in
                    if newValue == addMobSentinel {
                        showAddMobPrompt = true
                    } else {
                        selectedMobName = newValue
                    }
                }
            )
        ) {
            Text("None").tag(SessionSetupMobStepView.noneSentinel)
            Text("Mixed").tag(SessionSetupMobStepView.mixedSentinel)

            ForEach(availableMobsForSelectedFarm) { mob in
                Text(mob.name).tag(mob.name)
            }

            Text("Add New Mob…").tag(addMobSentinel)
        }
        .pickerStyle(.menu)
    }
}
