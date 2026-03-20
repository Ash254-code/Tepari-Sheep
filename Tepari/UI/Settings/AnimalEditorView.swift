import SwiftUI

struct AnimalEditorView: View {

    @EnvironmentObject private var store: LocalDataStore
    @Environment(\.dismiss) private var dismiss

    let farmID: UUID
    let original: LocalDataStore.AnimalProfile

    // Editable fields
    @State private var mobID: UUID?
    @State private var lambsPerYear: String = ""
    @State private var fleeceWeight: String = ""
    @State private var stapleLength: String = ""
    @State private var klass: String = ""
    @State private var comments: String = ""
    @State private var user1: String = ""
    @State private var user2: String = ""

    // UX
    @State private var showValidationAlert: Bool = false
    @State private var validationMessage: String = ""

    init(farmID: UUID, animal: LocalDataStore.AnimalProfile) {
        self.farmID = farmID
        self.original = animal

        _mobID = State(initialValue: animal.mobID)
        _lambsPerYear = State(initialValue: animal.lambsPerYear.map(String.init) ?? "")
        _fleeceWeight = State(initialValue: animal.fleeceWeightKg.map { String($0) } ?? "")
        _stapleLength = State(initialValue: animal.stapleLengthMm.map { String($0) } ?? "")
        _klass = State(initialValue: animal.klass ?? "")
        _comments = State(initialValue: animal.comments ?? "")
        _user1 = State(initialValue: animal.userField1 ?? "")
        _user2 = State(initialValue: animal.userField2 ?? "")
    }

    var body: some View {
        Form {

            Section("Animal") {
                Text(original.eidRaw)
                    .font(.headline)
            }

            Section("Mob") {
                Picker("Mob", selection: $mobID) {
                    Text("None").tag(UUID?.none)
                    ForEach(store.mobs(for: farmID)) { mob in
                        Text(mob.name).tag(UUID?.some(mob.id))
                    }
                }
            }

            Section("Traits") {

                TextField("Lambs \(Calendar.current.component(.year, from: Date()))", text: $lambsPerYear)
                    .keyboardType(.numberPad)

                TextField("Fleece weight (kg)", text: $fleeceWeight)
                    .keyboardType(.decimalPad)

                TextField("Staple length (mm)", text: $stapleLength)
                    .keyboardType(.decimalPad)

                TextField("Class", text: $klass)
            }

            Section("Lambing History") {
                if lambingHistory.isEmpty {
                    Text("No lamb records yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lambingHistory, id: \.id) { item in
                        HStack {
                            Text("\(item.year)")
                            Spacer()
                            Text("\(item.born)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Notes") {
                TextField("Comments", text: $comments, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("User Fields") {
                TextField("User field 1", text: $user1)
                TextField("User field 2", text: $user2)
            }
        }
        .navigationTitle("Edit Animal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
            }
        }
        .alert("Fix these fields", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(validationMessage)
        }
        .onAppear {
            let year = Calendar.current.component(.year, from: Date())
            if let v = store.lambCountForYear(
                farmID: farmID,
                eidRaw: original.eidRaw,
                year: year
            ) {
                lambsPerYear = String(v)
            }
        }
    }
}

//
// MARK: - History
//

private extension AnimalEditorView {

    struct LambingHistoryRow: Identifiable {
        let id: UUID
        let year: Int
        let born: Int
    }

    var lambingHistory: [LambingHistoryRow] {
        store.animalEvents
            .filter { event in
                event.kind == .lambing &&
                event.farmID == farmID &&
                normalizedEID(event.eidRaw) == normalizedEID(original.eidRaw)
            }
            .compactMap { event in
                let year = event.int1 ?? Calendar.current.component(.year, from: event.date)

                guard
                    let bornString = event.json?["born"],
                    let born = Int(bornString)
                else {
                    return nil
                }

                return LambingHistoryRow(
                    id: event.id,
                    year: year,
                    born: born
                )
            }
            .sorted { $0.year > $1.year }
    }

    func normalizedEID(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }
}

//
// MARK: - Save
//

private extension AnimalEditorView {

    func save() {
        guard validateInputs() else { return }

        let year = Calendar.current.component(.year, from: Date())
        let lambValue = intOrNil(lambsPerYear)

        if let n = lambValue {
            store.addLambingEvent(
                farmID: farmID,
                eidRaw: original.eidRaw,
                year: year,
                born: n,
                weaned: nil,
                notes: "Manual edit"
            )
        }

        let updated = LocalDataStore.AnimalProfile(
            id: original.id,
            farmID: farmID,
            eidRaw: original.eidRaw,
            mobID: mobID,
            sex: original.sex,
            animalClass: original.animalClass,
            breed: original.breed,
            birthYear: original.birthYear,
            birthMonth: original.birthMonth,
            status: original.status,
            lambsPerYear: lambValue ?? original.lambsPerYear,
            fleeceWeightKg: doubleOrNil(fleeceWeight),
            stapleLengthMm: doubleOrNil(stapleLength),
            klass: emptyNil(klass),
            comments: emptyNil(comments),
            userField1: emptyNil(user1),
            userField2: emptyNil(user2)
        )

        store.upsertAnimal(updated)
        dismiss()
    }

    func validateInputs() -> Bool {
        if let v = intOrNil(lambsPerYear), v < 0 {
            return fail("Lambs per year must be 0 or greater.")
        }

        if let v = doubleOrNil(fleeceWeight), v < 0 {
            return fail("Fleece weight must be 0 or greater.")
        }

        if let v = doubleOrNil(stapleLength), v < 0 {
            return fail("Staple length must be 0 or greater.")
        }

        return true
    }

    func fail(_ msg: String) -> Bool {
        validationMessage = msg
        showValidationAlert = true
        return false
    }

    func emptyNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    func intOrNil(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return Int(t)
    }

    func doubleOrNil(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let normalized = t.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
