import SwiftUI

// =========================================================
// MARK: - Traits Quick Picks Editor
// Modern glass-style version
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
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {
                    headerCard

                    quickPickCard(
                        title: "Micron",
                        subtitle: "Shown as one-tap chips in Trait Input sessions.",
                        placeholder: "Add micron…",
                        helperText: "\(micron.count)/\(maxCount)",
                        text: $newMicronText,
                        addAction: addMicron,
                        canAdd: canAddMicron
                    ) {
                        if micron.isEmpty {
                            emptyInlineState("No micron quick picks.")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(micron.enumerated()), id: \.offset) { index, value in
                                    quickPickRow(
                                        title: formatMicron(value),
                                        canMoveUp: index > 0,
                                        canMoveDown: index < micron.count - 1,
                                        onMoveUp: { moveMicronUp(at: index) },
                                        onMoveDown: { moveMicronDown(at: index) },
                                        onDelete: { deleteMicron(at: index) }
                                    )
                                }
                            }
                        }
                    }

                    quickPickCard(
                        title: "Staple Length",
                        subtitle: "Up to 10 quick picks. Shown in Trait Input sessions.",
                        placeholder: "Add staple (mm)…",
                        helperText: "\(stapleMm.count)/\(maxCount)",
                        text: $newStapleText,
                        addAction: addStaple,
                        canAdd: canAddStaple
                    ) {
                        if stapleMm.isEmpty {
                            emptyInlineState("No staple length quick picks.")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(stapleMm.enumerated()), id: \.offset) { index, value in
                                    quickPickRow(
                                        title: "\(value) mm",
                                        canMoveUp: index > 0,
                                        canMoveDown: index < stapleMm.count - 1,
                                        onMoveUp: { moveStapleUp(at: index) },
                                        onMoveDown: { moveStapleDown(at: index) },
                                        onDelete: { deleteStaple(at: index) }
                                    )
                                }
                            }
                        }
                    }

                    ForEach(Array(customFields.enumerated()), id: \.element.id) { index, def in
                        customFieldCard(index: index, def: def)
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .safeAreaPadding(.bottom, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Traits")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: LocalDataStore.traitsConfigChangedNotification)) { _ in
            seedFromStore()
        }
    }

    // =====================================================
    // MARK: - Header
    // =====================================================

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Traits")
                    .font(.title3.weight(.bold))

                Text("Manage quick picks for Micron, Staple Length, and your two custom trait fields.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    miniPill("Micron")
                    miniPill("Staple")
                    miniPill("Custom 1")
                    miniPill("Custom 2")
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // =====================================================
    // MARK: - Cards
    // =====================================================

    private func quickPickCard<Content: View>(
        title: String,
        subtitle: String,
        placeholder: String,
        helperText: String,
        text: Binding<String>,
        addAction: @escaping () -> Void,
        canAdd: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: title, subtitle: subtitle)

                HStack(spacing: 10) {
                    TextField(placeholder, text: text)
#if os(iOS)
                        .keyboardType(title == "Micron" ? .decimalPad : .numberPad)
#endif
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )

                    Button {
                        addAction()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .glassButton(.compact, tint: .blue)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.45)
                }

                content()

                HStack {
                    Spacer()
                    Text(helperText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func customFieldCard(index: Int, def: LocalDataStore.CustomTraitDefinition) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "User Defined \(index + 1)",
                    subtitle: "If the label is blank, this field can be treated as hidden."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Field Label")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("Field label (leave blank to hide)", text: bindingForCustomLabel(id: def.id))
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }

                HStack(spacing: 10) {
                    TextField("Add quick pick…", text: bindingForNewCustomPickText(id: def.id))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )

                    Button {
                        addCustomPick(fieldID: def.id)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .glassButton(.compact, tint: .blue)
                    .disabled(!canAddCustomPick(fieldID: def.id))
                    .opacity(canAddCustomPick(fieldID: def.id) ? 1 : 0.45)
                }

                if def.quickPicks.isEmpty {
                    emptyInlineState("No quick picks.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(def.quickPicks.enumerated()), id: \.offset) { idx, pick in
                            quickPickRow(
                                title: pick,
                                canMoveUp: idx > 0,
                                canMoveDown: idx < def.quickPicks.count - 1,
                                onMoveUp: { moveCustomPickUp(fieldID: def.id, at: idx) },
                                onMoveDown: { moveCustomPickDown(fieldID: def.id, at: idx) },
                                onDelete: { deleteCustomPick(fieldID: def.id, at: idx) }
                            )
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("\(def.quickPicks.count)/\(maxCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func quickPickRow(
        title: String,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                rowIconButton(systemName: "arrow.up", enabled: canMoveUp, action: onMoveUp)
                rowIconButton(systemName: "arrow.down", enabled: canMoveDown, action: onMoveDown)
                rowIconButton(systemName: "trash", enabled: true, tint: .red, action: onDelete)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func rowIconButton(
        systemName: String,
        enabled: Bool,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.45))
                .background(
                    Circle().fill(Color.white.opacity(0.06))
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyInlineState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func miniPill(_ text: String) -> some View {
        Text(text)
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

    // =====================================================
    // MARK: - Seed / Persist
    // =====================================================

    private func seedFromStore() {
        micron = store.traitsConfig.micronQuickPicks
        stapleMm = store.traitsConfig.stapleLengthQuickPicksMm

        var fields = store.traitsConfig.customFields
        if fields.count > 2 { fields = Array(fields.prefix(2)) }

        let existingByID: [String: LocalDataStore.CustomTraitDefinition] = Dictionary(
            uniqueKeysWithValues: fields.map { ($0.id, $0) }
        )

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

        if newCustomPickText["custom1"] == nil { newCustomPickText["custom1"] = "" }
        if newCustomPickText["custom2"] == nil { newCustomPickText["custom2"] = "" }
    }

    private func persist() {
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

    private func moveMicronUp(at index: Int) {
        guard index > 0 else { return }
        micron.swapAt(index, index - 1)
        persist()
    }

    private func moveMicronDown(at index: Int) {
        guard index < micron.count - 1 else { return }
        micron.swapAt(index, index + 1)
        persist()
    }

    private func deleteMicron(at index: Int) {
        guard micron.indices.contains(index) else { return }
        micron.remove(at: index)
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

    private func moveStapleUp(at index: Int) {
        guard index > 0 else { return }
        stapleMm.swapAt(index, index - 1)
        persist()
    }

    private func moveStapleDown(at index: Int) {
        guard index < stapleMm.count - 1 else { return }
        stapleMm.swapAt(index, index + 1)
        persist()
    }

    private func deleteStaple(at index: Int) {
        guard stapleMm.indices.contains(index) else { return }
        stapleMm.remove(at: index)
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

    private func deleteCustomPick(fieldID: String, at index: Int) {
        updateCustomField(id: fieldID) { def in
            guard def.quickPicks.indices.contains(index) else { return }
            def.quickPicks.remove(at: index)
        }
        persist()
    }

    private func moveCustomPickUp(fieldID: String, at index: Int) {
        updateCustomField(id: fieldID) { def in
            guard index > 0, def.quickPicks.indices.contains(index) else { return }
            def.quickPicks.swapAt(index, index - 1)
        }
        persist()
    }

    private func moveCustomPickDown(fieldID: String, at index: Int) {
        updateCustomField(id: fieldID) { def in
            guard index < def.quickPicks.count - 1, def.quickPicks.indices.contains(index) else { return }
            def.quickPicks.swapAt(index, index + 1)
        }
        persist()
    }

    private func updateCustomField(id: String, mutate: (inout LocalDataStore.CustomTraitDefinition) -> Void) {
        guard let idx = customFields.firstIndex(where: { $0.id == id }) else { return }
        var def = customFields[idx]
        mutate(&def)
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
    // MARK: - Local normalize
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
