import SwiftUI

struct ProgrammedTagsView: View {

    @EnvironmentObject private var store: LocalDataStore
    let farmID: UUID

    // Sex tag entry
    @State private var newSexTag: String = ""
    @State private var selectedSex: LocalDataStore.Sex = .wether

    // Class tag entry
    @State private var newClassTag: String = ""
    @State private var selectedClass: LocalDataStore.AnimalClass = .flock

    // Unified programmed list (sex + class live together now)
    private var programmed: [(eid: String, assignment: LocalDataStore.ProgrammedTagAssignment)] {
        store.allProgrammedTags(for: farmID)
    }

    var body: some View {
        List {

            // =========================================
            // Program new Sex tag
            // =========================================
            Section("Program new tag (Sex)") {

                TextField("Scan or enter EID tag", text: $newSexTag)
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))

                Picker("Sex", selection: $selectedSex) {
                    ForEach(LocalDataStore.Sex.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                Button("Save programmed sex") {
                    saveSexTag()
                }
                .disabled(newSexTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // =========================================
            // Program new Class tag
            // =========================================
            Section("Program new tag (Class)") {

                TextField("Scan or enter EID tag", text: $newClassTag)
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))

                Picker("Class", selection: $selectedClass) {
                    ForEach(LocalDataStore.AnimalClass.allCases) { c in
                        Text(c.label).tag(c)
                    }
                }
                .pickerStyle(.segmented)

                Button("Save programmed class") {
                    saveClassTag()
                }
                .disabled(newClassTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // =========================================
            // Existing programmed tags (combined)
            // =========================================
            Section("Programmed tags") {

                if programmed.isEmpty {
                    Text("No programmed tags yet")
                        .foregroundStyle(.secondary)
                }

                ForEach(programmed, id: \.eid) { item in
                    VStack(alignment: .leading, spacing: 4) {

                        Text(item.eid)
                            .font(.system(.body, design: .monospaced))

                        HStack(spacing: 10) {
                            Text(item.assignment.sex?.label ?? "—")
                                .foregroundStyle(.secondary)

                            Text("•")
                                .foregroundStyle(.secondary)

                            Text(item.assignment.animalClass?.label ?? "—")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .onDelete(perform: deleteProgrammed)
            }
        }
        .navigationTitle("Programmed Tags")
    }

    // MARK: - Actions

    private func saveSexTag() {
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
        for index in offsets {
            let tag = programmed[index]
            store.removeProgrammedTag(
                farmID: farmID,
                eidRaw: tag.eid
            )
        }
    }
}
