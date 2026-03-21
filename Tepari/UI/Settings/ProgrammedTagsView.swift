import SwiftUI

struct ProgrammedTagsView: View {

    @EnvironmentObject private var store: LocalDataStore

    // Sex tag entry
    @State private var newSexTag: String = ""
    @State private var selectedSex: LocalDataStore.Sex = .wether

    // Class tag entry
    @State private var newClassTag: String = ""
    @State private var selectedClass: LocalDataStore.AnimalClass = .flock

    /// Backing farm used internally until programmed tags are made truly global in LocalDataStore.
    private var backingFarmID: UUID? {
        store.farms.first?.id
    }

    // Unified programmed list (sex + class live together now)
    private var programmed: [(eid: String, assignment: LocalDataStore.ProgrammedTagAssignment)] {
        guard let farmID = backingFarmID else { return [] }
        return store.allProgrammedTags(for: farmID)
    }

    var body: some View {
        ZStack {
            GlassBackground()

            List {
                Section {
                    ProgrammedTagsHeaderCard(
                        title: "Programmed Tags",
                        subtitle: "Save tag-based sex and class assignments without needing to choose a farm first.",
                        systemImage: "tag.fill",
                        tint: .orange
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if backingFarmID == nil {
                    Section("No Farm Available") {
                        Text("Add a farm first before using programmed tags.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // =========================================
                    // Program new Sex tag
                    // =========================================
                    Section("Program New Tag • Sex") {

                        TextField("Scan or enter EID tag", text: $newSexTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))

                        Picker("Sex", selection: $selectedSex) {
                            ForEach(LocalDataStore.Sex.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            saveSexTag()
                        } label: {
                            Label("Save programmed sex", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newSexTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // =========================================
                    // Program new Class tag
                    // =========================================
                    Section("Program New Tag • Class") {

                        TextField("Scan or enter EID tag", text: $newClassTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))

                        Picker("Class", selection: $selectedClass) {
                            ForEach(LocalDataStore.AnimalClass.allCases) { c in
                                Text(c.label).tag(c)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            saveClassTag()
                        } label: {
                            Label("Save programmed class", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newClassTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // =========================================
                    // Existing programmed tags (combined)
                    // =========================================
                    Section("Programmed Tags") {

                        if programmed.isEmpty {
                            Text("No programmed tags yet.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(programmed, id: \.eid) { item in
                            ProgrammedTagRow(
                                eid: item.eid,
                                sexText: item.assignment.sex?.label ?? "—",
                                classText: item.assignment.animalClass?.label ?? "—"
                            )
                        }
                        .onDelete(perform: deleteProgrammed)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Programmed Tags")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    private func saveSexTag() {
        guard let farmID = backingFarmID else { return }

        // Preserve any existing class assignment for this tag
        let existing = store.programmedAssignment(for: farmID, eidRaw: newSexTag)

        store.setProgrammedTag(
            farmID: farmID,
            eidRaw: newSexTag,
            sex: selectedSex,
            animalClass: existing?.animalClass
        )

        newSexTag = ""
    }

    private func saveClassTag() {
        guard let farmID = backingFarmID else { return }

        // Preserve any existing sex assignment for this tag
        let existing = store.programmedAssignment(for: farmID, eidRaw: newClassTag)

        store.setProgrammedTag(
            farmID: farmID,
            eidRaw: newClassTag,
            sex: existing?.sex,
            animalClass: selectedClass
        )

        newClassTag = ""
    }

    private func deleteProgrammed(at offsets: IndexSet) {
        guard let farmID = backingFarmID else { return }

        for index in offsets {
            let tag = programmed[index]
            store.removeProgrammedTag(
                farmID: farmID,
                eidRaw: tag.eid
            )
        }
    }
}

// =====================================================
// MARK: - Styling
// =====================================================

private struct ProgrammedTagsHeaderCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 50, height: 50)

                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }
}

private struct ProgrammedTagRow: View {
    let eid: String
    let sexText: String
    let classText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eid)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 8) {
                SmallInfoPill(text: sexText, tint: .blue)
                SmallInfoPill(text: classText, tint: .green)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SmallInfoPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
    }
}
