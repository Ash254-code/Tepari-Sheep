import SwiftUI

struct FarmSetupView: View {

    @EnvironmentObject private var store: LocalDataStore

    // ✅ For connectivity pills in the NAV BAR (keeps Back button correct)
    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var racewell: RacewellManager
    @EnvironmentObject private var stickReader: StickReaderManager

    // =====================================================
    // MARK: - Farm form
    // =====================================================

    @State private var farmName: String = ""
    @State private var farmPIC: String = ""
    @State private var editingFarm: LocalDataStore.Farm? = nil

    // =====================================================
    // MARK: - Yard locations (per farm)
    // =====================================================

    @State private var yardsDraft: String = ""
    @State private var yardPickFarmID: UUID? = nil

    // ✅ Manage yards sheet
    @State private var manageFarmID: UUID? = nil
    @State private var showManageYards: Bool = false

    // MARK: - Connection states for pills

    private var handlerState: ConnectionState {
        transport.method == .demo ? .connected : transport.state
    }

    private var draftState: ConnectionState { racewell.state }
    private var stickState: ConnectionState { stickReader.state }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    // =====================================================
                    // Add / Edit farm (Glass style)
                    // =====================================================
                    farmFormCard

                    // ✅ Heading OUTSIDE cards
                    HStack {
                        Text("Your farms")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(store.farms.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .padding(.top, 2)
                    .padding(.horizontal, 2)

                    // ✅ Each farm gets its own card
                    if store.farms.isEmpty {
                        GlassCard {
                            Text("No farms yet. Add one above.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.farms) { farm in
                                farmCard(farm)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Farms")
        .navigationBarTitleDisplayMode(.inline)

        // ✅ Pills inside nav bar
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.thinMaterial, for: .navigationBar)

        // ✅ Manage yards sheet (kept simple for compile stability)
        .sheet(isPresented: $showManageYards) {
            if let farmID = manageFarmID {
                ManageYardsSheet(
                    farmName: store.farms.first(where: { $0.id == farmID })?.name ?? "Farm",
                    initialYards: yardsFor(farmID),
                    onSave: { updated in
                        setYards(for: farmID, yards: updated)
                    }
                )
            }
        }
    }

    // =====================================================
    // MARK: - Cards
    // =====================================================

    private var farmFormCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {

                // ✅ Fresher “glass” header
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(editingFarm == nil ? "Add farm" : "Edit farm")
                            .font(.headline)

                        Text("Farm name + PIC")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if editingFarm != nil {
                        Button { clearForm() } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                        }
                        .glassButton(.compact)
                    }
                }

                glassField(icon: "textformat", placeholder: "Farm name", text: $farmName, autocaps: .words)

                glassField(icon: "number", placeholder: "PIC (Property ID Code)", text: $farmPIC, autocaps: .characters)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                HStack(spacing: 10) {
                    Button {
                        saveFarm()
                    } label: {
                        Label(editingFarm == nil ? "Add farm" : "Save changes", systemImage: "checkmark.circle.fill")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!formValid)

                    if editingFarm != nil {
                        Button {
                            clearForm()
                        } label: {
                            Text("Clear")
                                .font(.headline.weight(.semibold))
                                .frame(width: 110)
                                .padding(.vertical, 12)
                        }
                        .glassButton(.fullWidth)
                    }
                }
            }
        }
    }

    private func farmCard(_ farm: LocalDataStore.Farm) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                // Farm header
                HStack(alignment: .top, spacing: 10) {

                    // ✅ Leaf badge (matches Add Farm card)
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )

                        Image(systemName: "leaf.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(farm.name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            Image(systemName: "number")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(farm.pic)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Menu {
                        Button { startEdit(farm) } label: {
                            Label("Edit farm", systemImage: "pencil")
                        }

                        Button { startEditYards(for: farm) } label: {
                            Label("Add yards", systemImage: "plus")
                        }

                        Divider()

                        Button(role: .destructive) {
                            store.deleteFarm(farm.id)
                            if editingFarm?.id == farm.id { clearForm() }
                            if yardPickFarmID == farm.id { yardPickFarmID = nil; yardsDraft = "" }
                            removeYards(for: farm.id)
                        } label: {
                            Label("Delete farm", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                    .buttonStyle(.plain)
                }
                Divider().opacity(0.12)

                // Yard Locations section
                VStack(alignment: .leading, spacing: 10) {

                    // ✅ Keep the label + put buttons on the right
                    HStack {
                        Text("Yard locations")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                startEditYards(for: farm)
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .glassButton(.compact)

                            Button {
                                manageFarmID = farm.id
                                showManageYards = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .glassButton(.compact)
                        }
                    }

                    let yards = yardsFor(farm.id)

                    if yards.isEmpty {
                        Text("No yards yet. Add names like “Main Yards”, “Drafting Race”, “Woolshed”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowChips(items: yards)
                            .padding(.top, 2)

                        Text("Tip: Tap Edit to rename, delete, or reorder yards.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }

                    // Inline editor (only expands for selected farm)
                    if yardPickFarmID == farm.id {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Add yards (comma separated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            glassField(
                                icon: "mappin.and.ellipse",
                                placeholder: "e.g. Main Yards, Drafting Race, Woolshed",
                                text: $yardsDraft,
                                autocaps: .words
                            )

                            HStack {
                                Spacer()

                                Button {
                                    saveYards(for: farm.id, input: yardsDraft)
                                    yardsDraft = ""
                                    yardPickFarmID = nil
                                } label: {
                                    Label("Save", systemImage: "checkmark.circle.fill")
                                        .font(.headline.weight(.semibold))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(yardsDraft.trimmed.isEmpty)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // =====================================================
    // MARK: - Actions (farm)
    // =====================================================

    private var formValid: Bool {
        !farmName.trimmed.isEmpty && !farmPIC.trimmed.isEmpty
    }

    private func saveFarm() {
        let name = farmName.trimmed
        let pic  = farmPIC.trimmed

        if var farm = editingFarm {
            farm.name = name
            farm.pic = pic
            store.updateFarm(farm)
        } else {
            store.addFarm(name: name, pic: pic)
        }

        clearForm()
    }

    private func startEdit(_ farm: LocalDataStore.Farm) {
        editingFarm = farm
        farmName = farm.name
        farmPIC = farm.pic

        yardPickFarmID = nil
        yardsDraft = ""
    }

    private func clearForm() {
        editingFarm = nil
        farmName = ""
        farmPIC = ""
    }

    // =====================================================
    // MARK: - Actions (yards)
    // =====================================================

    private func startEditYards(for farm: LocalDataStore.Farm) {
        yardPickFarmID = farm.id
        yardsDraft = ""
    }

    // =====================================================
    // MARK: - Yards persistence (UserDefaults for now)
    // =====================================================

    private func yardsKey(_ farmID: UUID) -> String {
        "farms.yards.\(farmID.uuidString)"
    }

    private func yardsFor(_ farmID: UUID) -> [String] {
        let raw = UserDefaults.standard.string(forKey: yardsKey(farmID)) ?? ""
        let parts = raw
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            let k = p.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(p)
        }
        return out
    }

    private func saveYards(for farmID: UUID, input: String) {
        let newOnes = input
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !newOnes.isEmpty else { return }

        var merged = yardsFor(farmID)
        for y in newOnes {
            if merged.contains(where: { $0.caseInsensitiveCompare(y) == .orderedSame }) { continue }
            merged.append(y)
        }

        let packed = merged.joined(separator: "|")
        UserDefaults.standard.set(packed, forKey: yardsKey(farmID))
    }

    // ✅ Write yards in the exact order provided (for Manage sheet)
    private func setYards(for farmID: UUID, yards: [String]) {
        let cleaned = yards
            .map { $0.trimmed }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var out: [String] = []
        for y in cleaned {
            let k = y.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(y)
        }

        UserDefaults.standard.set(out.joined(separator: "|"), forKey: yardsKey(farmID))
    }

    private func removeYards(for farmID: UUID) {
        UserDefaults.standard.removeObject(forKey: yardsKey(farmID))
    }

    // =====================================================
    // MARK: - Glass controls
    // =====================================================

    private func glassField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        autocaps: TextInputAutocapitalization
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(autocaps)
                .textFieldStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

// =====================================================
// MARK: - Flow chips (wrap layout, self-sizing)
// =====================================================

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowWrapLayout(spacing: 10, rowSpacing: 10) {
            ForEach(items, id: \.self) { item in
                YardChip(title: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct YardChip: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.body.weight(.semibold))   // ✅ slightly bigger still
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)                 // ✅ bigger pill
        .padding(.vertical, 12)                   // ✅ bigger pill
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// =====================================================
// MARK: - Wrap Layout (no GeometryReader clipping)
// =====================================================

private struct FlowWrapLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let width = sizes.map(\.width).max() ?? 0
            let height = sizes.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, sizes.count - 1))
            return CGSize(width: width, height: height)
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)

            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// =====================================================
// MARK: - Manage yards sheet (rename/delete/reorder)
// =====================================================

private struct ManageYardsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let farmName: String
    let initialYards: [String]
    let onSave: ([String]) -> Void

    @State private var yards: [String]
    @State private var newYard: String = ""
    @State private var editMode: EditMode = .active

    init(farmName: String, initialYards: [String], onSave: @escaping ([String]) -> Void) {
        self.farmName = farmName
        self.initialYards = initialYards
        self.onSave = onSave
        _yards = State(initialValue: initialYards)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("Add new yard", text: $newYard)
                            .textInputAutocapitalization(.words)

                        Button { addNew() } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(newYard.trimmed.isEmpty)
                    }

                    Text("Tip: Drag to reorder. Swipe left to delete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Yards") {
                    ForEach(yards.indices, id: \.self) { i in
                        TextField("Yard name", text: Binding(
                            get: { yards[i] },
                            set: { yards[i] = $0 }
                        ))
                        .textInputAutocapitalization(.words)
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(farmName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(cleaned(yards))
                        dismiss()
                    }
                    .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func addNew() {
        let v = newYard.trimmed
        guard !v.isEmpty else { return }

        if yards.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) {
            newYard = ""
            return
        }

        yards.append(v)
        newYard = ""
    }

    private func delete(at offsets: IndexSet) {
        yards.remove(atOffsets: offsets)
    }

    private func move(from source: IndexSet, to destination: Int) {
        yards.move(fromOffsets: source, toOffset: destination)
    }

    private func cleaned(_ items: [String]) -> [String] {
        let trimmed = items.map { $0.trimmed }.filter { !$0.isEmpty }
        var seen = Set<String>()
        var out: [String] = []
        for y in trimmed {
            let k = y.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(y)
        }
        return out
    }
}

// =====================================================
// MARK: - String helper
// =====================================================

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
