import SwiftUI

// =========================================================
// MARK: - Traits Quick Picks Editor (0–10, reorder, delete)
// Includes Micron + Staple + 2 User Defined (custom1/custom2)
// =========================================================

struct TraitsQuickPicksSettingsView: View {

    @EnvironmentObject private var store: LocalDataStore

    private let maxCount = 10

    // Draft editing state
    @State private var micron: [Double] = []
    @State private var stapleMm: [Int] = []

    // Add row state
    @State private var newMicronText: String = ""
    @State private var newStapleText: String = ""

    // Custom fields (exactly 2: custom1/custom2)
    @State private var customFields: [LocalDataStore.CustomTraitDefinition] = []

    // Per-field add text
    @State private var newCustomPickText: [String: String] = [:] // id -> text

    var body: some View {
        Form {

            // ----------------------------
            // Micron
            // ----------------------------
            Section {
                HStack(spacing: 10) {
                    TextField("Add micron…", text: $newMicronText)
                        .keyboardType(.decimalPad)

                    Button("Add") { addMicron() }
                        .disabled(!canAddMicron)
                }

                if micron.isEmpty {
                    Text("No micron quick picks.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(micron, id: \.self) { v in
                        Text(formatMicron(v))
                    }
                    .onDelete { idx in
                        micron.remove(atOffsets: idx)
                        persist()
                    }
                    .onMove { from, to in
                        micron.move(fromOffsets: from, toOffset: to)
                        persist()
                    }
                }

                Text("\(micron.count)/\(maxCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } header: {
                Text("Micron quick picks")
            } footer: {
                Text("Shown as one-tap chips in Trait Input sessions.")
            }

            // ----------------------------
            // Staple length (mm)
            // ----------------------------
            Section {
                HStack(spacing: 10) {
                    TextField("Add staple (mm)…", text: $newStapleText)
                        .keyboardType(.numberPad)

                    Button("Add") { addStaple() }
                        .disabled(!canAddStaple)
                }

                if stapleMm.isEmpty {
                    Text("No staple length quick picks.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stapleMm, id: \.self) { v in
                        Text("\(v) mm")
                    }
                    .onDelete { idx in
                        stapleMm.remove(atOffsets: idx)
                        persist()
                    }
                    .onMove { from, to in
                        stapleMm.move(fromOffsets: from, toOffset: to)
                        persist()
                    }
                }

                Text("\(stapleMm.count)/\(maxCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } header: {
                Text("Staple length quick picks (mm)")
            } footer: {
                Text("Up to 10. Use Edit to reorder.")
            }

            // ----------------------------
            // User Defined fields (2)
            // ----------------------------
            ForEach(Array(customFields.enumerated()), id: \.element.id) { index, def in
                customFieldSection(index: index, def: def)
            }
        }
        .navigationTitle("Traits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onAppear {
            seedFromStore()
        }
        // Keep in sync if store updates externally
        .onReceive(NotificationCenter.default.publisher(for: LocalDataStore.traitsConfigChangedNotification)) { _ in
            seedFromStore()
        }
    }

    // =====================================================
    // MARK: - Sections
    // =====================================================

    @ViewBuilder
    private func customFieldSection(index: Int, def: LocalDataStore.CustomTraitDefinition) -> some View {
        let title = "User Defined \(index + 1)"

        Section {
            // Label
            TextField("Field label (leave blank to hide)", text: bindingForCustomLabel(id: def.id))
                .textInputAutocapitalization(.words)

            // Add quick pick row
            HStack(spacing: 10) {
                TextField("Add quick pick…", text: bindingForNewCustomPickText(id: def.id))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                Button("Add") { addCustomPick(fieldID: def.id) }
                    .disabled(!canAddCustomPick(fieldID: def.id))
            }

            // List of quick picks
            if def.quickPicks.isEmpty {
                Text("No quick picks.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(def.quickPicks, id: \.self) { p in
                    Text(p)
                }
                .onDelete { idx in
                    deleteCustomPicks(fieldID: def.id, at: idx)
                }
                .onMove { from, to in
                    moveCustomPicks(fieldID: def.id, from: from, to: to)
                }
            }

            Text("\(def.quickPicks.count)/\(maxCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

        } header: {
            Text(title)
        } footer: {
            Text("These are shown as one-tap chips in Trait Input sessions. If the label is blank, the field can be treated as hidden.")
        }
    }

    // =====================================================
    // MARK: - Seed / Persist
    // =====================================================

    private func seedFromStore() {
        micron = store.traitsConfig.micronQuickPicks
        stapleMm = store.traitsConfig.stapleLengthQuickPicksMm

        // Ensure exactly 2 custom fields with stable ids custom1/custom2
        var fields = store.traitsConfig.customFields
        if fields.count > 2 { fields = Array(fields.prefix(2)) }

        // Build lookup by id if user has edited ids (we normalize to custom1/custom2)
        let existingByID: [String: LocalDataStore.CustomTraitDefinition] = Dictionary(
            uniqueKeysWithValues: fields.map { ($0.id, $0) }
        )

        // NOTE: CustomTraitDefinition init order is:
        // (id, label, kind, quickPicks)

        let c1 = existingByID["custom1"] ?? fields.first ?? .init(
            id: "custom1",
            label: "",
            kind: .number,
            quickPicks: []
        )

        let c2 = existingByID["custom2"]
            ?? (fields.count > 1
                ? fields[1]
                : .init(
                    id: "custom2",
                    label: "",
                    kind: .number,
                    quickPicks: []
                )
            )

        // Force stable ids
        customFields = [
            .init(
                id: "custom1",
                label: c1.label,
                kind: c1.kind,
                quickPicks: c1.quickPicks
            ),
            .init(
                id: "custom2",
                label: c2.label,
                kind: c2.kind,
                quickPicks: c2.quickPicks
            )
        ]

        // Seed per-field add text map
        if newCustomPickText["custom1"] == nil { newCustomPickText["custom1"] = "" }
        if newCustomPickText["custom2"] == nil { newCustomPickText["custom2"] = "" }
    }

    private func persist() {
        // Persist all together so sanitize runs once and notifications fire once.
        var cfg = store.traitsConfig
        cfg.micronQuickPicks = micron
        cfg.stapleLengthQuickPicksMm = stapleMm
        cfg.customFields = customFields
        store.setTraitsConfig(cfg)
    }

    // =====================================================
    // MARK: - Micron helpers
    // =====================================================

    private var canAddMicron: Bool {
        guard micron.count < maxCount else { return false }
        return parseMicron(newMicronText) != nil
    }

    private func addMicron() {
        guard micron.count < maxCount else { return }
        guard let v = parseMicron(newMicronText) else { return }

        micron.append(v)
        micron = normalizeDoublesLocal(micron, maxCount: maxCount)
        newMicronText = ""
        persist()
    }

    // =====================================================
    // MARK: - Staple helpers
    // =====================================================

    private var canAddStaple: Bool {
        guard stapleMm.count < maxCount else { return false }
        return parseStaple(newStapleText) != nil
    }

    private func addStaple() {
        guard stapleMm.count < maxCount else { return }
        guard let v = parseStaple(newStapleText) else { return }

        stapleMm.append(v)
        stapleMm = normalizeIntsLocal(stapleMm, maxCount: maxCount)
        newStapleText = ""
        persist()
    }

    // =====================================================
    // MARK: - Custom field bindings + actions
    // =====================================================

    private func bindingForCustomLabel(id: String) -> Binding<String> {
        Binding(
            get: {
                customFields.first(where: { $0.id == id })?.label ?? ""
            },
            set: { newValue in
                updateCustomField(id: id) { $0.label = newValue }
                persist()
            }
        )
    }

    private func bindingForNewCustomPickText(id: String) -> Binding<String> {
        Binding(
            get: { newCustomPickText[id] ?? "" },
            set: { newCustomPickText[id] = $0 }
        )
    }

    private func canAddCustomPick(fieldID: String) -> Bool {
        guard let def = customFields.first(where: { $0.id == fieldID }) else { return false }
        guard def.quickPicks.count < maxCount else { return false }

        let t = (newCustomPickText[fieldID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty
    }

    private func addCustomPick(fieldID: String) {
        guard canAddCustomPick(fieldID: fieldID) else { return }

        let t = (newCustomPickText[fieldID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        updateCustomField(id: fieldID) { def in
            def.quickPicks.append(t)
            def.quickPicks = normalizeStringsLocal(def.quickPicks, maxCount: maxCount)
        }

        newCustomPickText[fieldID] = ""
        persist()
    }

    private func deleteCustomPicks(fieldID: String, at offsets: IndexSet) {
        updateCustomField(id: fieldID) { def in
            def.quickPicks.remove(atOffsets: offsets)
        }
        persist()
    }

    private func moveCustomPicks(fieldID: String, from: IndexSet, to: Int) {
        updateCustomField(id: fieldID) { def in
            def.quickPicks.move(fromOffsets: from, toOffset: to)
        }
        persist()
    }

    private func updateCustomField(id: String, mutate: (inout LocalDataStore.CustomTraitDefinition) -> Void) {
        guard let idx = customFields.firstIndex(where: { $0.id == id }) else { return }
        var def = customFields[idx]
        mutate(&def)
        // keep ids stable
        def.id = id
        customFields[idx] = def
    }

    // =====================================================
    // MARK: - Parsing / formatting
    // =====================================================

    private func parseMicron(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let normalized = t.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(normalized) else { return nil }
        return v > 0 ? v : nil
    }

    private func parseStaple(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard let v = Int(t) else { return nil }
        return v > 0 ? v : nil
    }

    private func formatMicron(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.0001 { return "\(Int(v.rounded()))" }
        return String(format: "%.1f", v)
    }

    // =====================================================
    // MARK: - Local normalize (UI-level; store will sanitize too)
    // =====================================================

    private func normalizeDoublesLocal(_ vals: [Double], maxCount: Int) -> [Double] {
        var out: [Double] = []
        var seen = Set<String>()
        for v in vals {
            guard v > 0 else { continue }
            let key = String(format: "%.1f", v)
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(v)
            if out.count >= maxCount { break }
        }
        return out
    }

    private func normalizeIntsLocal(_ vals: [Int], maxCount: Int) -> [Int] {
        var out: [Int] = []
        var seen = Set<Int>()
        for v in vals {
            guard v > 0 else { continue }
            if seen.contains(v) { continue }
            seen.insert(v)
            out.append(v)
            if out.count >= maxCount { break }
        }
        return out
    }

    private func normalizeStringsLocal(_ vals: [String], maxCount: Int) -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        for raw in vals {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }

            let k = t.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)

            out.append(t)
            if out.count >= maxCount { break }
        }

        return out
    }
}
