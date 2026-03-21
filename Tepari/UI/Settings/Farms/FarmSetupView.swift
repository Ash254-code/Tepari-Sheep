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
                VStack(spacing: 16) {
                    overviewCard
                    farmFormCard
                    farmsSection
                }
                .padding(16)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("Farms")
        .navigationBarTitleDisplayMode(.inline)
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
    // MARK: - Top overview
    // =====================================================

    private var overviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FarmHeroIcon(
                        systemImage: "leaf.fill",
                        tint: .green
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Farm setup")
                            .font(.headline)

                        Text("Create farms, store PICs and manage yard locations used throughout Tepari.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    FarmStatPill(
                        title: "Farms",
                        value: "\(store.farms.count)",
                        systemImage: "building.2.crop.circle",
                        tint: .blue
                    )

                    FarmStatPill(
                        title: "Yards",
                        value: "\(totalYardCount)",
                        systemImage: "mappin.and.ellipse",
                        tint: .orange
                    )
                }
            }
        }
    }

    // =====================================================
    // MARK: - Main sections
    // =====================================================

    private var farmsSection: some View {
        VStack(spacing: 12) {
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
            .padding(.horizontal, 2)

            if store.farms.isEmpty {
                GlassCard {
                    EmptyStateCard(
                        title: "No farms yet",
                        subtitle: "Add your first farm above to start organising PICs and yard locations.",
                        systemImage: "leaf.circle",
                        tint: .green
                    )
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(store.farms) { farm in
                        farmCard(farm)
                    }
                }
            }
        }
    }

    // =====================================================
    // MARK: - Cards
    // =====================================================

    private var farmFormCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FarmHeroIcon(
                        systemImage: editingFarm == nil ? "plus.circle.fill" : "pencil.circle.fill",
                        tint: editingFarm == nil ? .blue : .orange
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(editingFarm == nil ? "Add farm" : "Edit farm")
                            .font(.headline)

                        Text(editingFarm == nil ? "Enter a farm name and PIC to add it to your list." : "Update the selected farm’s details below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if editingFarm != nil {
                        Button {
                            clearForm()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                        }
                        .glassButton(.compact)
                    }
                }

                VStack(spacing: 12) {
                    glassField(
                        icon: "building.2.crop.circle",
                        placeholder: "Farm name",
                        text: $farmName,
                        autocaps: .words
                    )

                    glassField(
                        icon: "number.circle",
                        placeholder: "PIC (Property ID Code)",
                        text: $farmPIC,
                        autocaps: .characters
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                }

                HStack(spacing: 10) {
                    Button {
                        saveFarm()
                    } label: {
                        Label(
                            editingFarm == nil ? "Add farm" : "Save changes",
                            systemImage: editingFarm == nil ? "plus.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(editingFarm == nil ? .blue : .orange)
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
        let yards = yardsFor(farm.id)

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    FarmHeroIcon(
                        systemImage: "leaf.fill",
                        tint: .green,
                        size: 32
                    )
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(farm.name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            SmallInfoPill(
                                title: farm.pic,
                                systemImage: "number.circle",
                                tint: .secondary
                            )

                            SmallInfoPill(
                                title: "\(yards.count) yard" + (yards.count == 1 ? "" : "s"),
                                systemImage: "mappin.and.ellipse",
                                tint: .orange
                            )
                        }
                    }

                    Spacer()

                    Menu {
                        Button {
                            startEdit(farm)
                        } label: {
                            Label("Edit farm", systemImage: "pencil")
                        }

                        Button {
                            startEditYards(for: farm)
                        } label: {
                            Label("Quick add yards", systemImage: "plus")
                        }

                        Button {
                            manageFarmID = farm.id
                            showManageYards = true
                        } label: {
                            Label("Manage yards", systemImage: "slider.horizontal.3")
                        }

                        Divider()

                        Button(role: .destructive) {
                            store.deleteFarm(farm.id)
                            if editingFarm?.id == farm.id { clearForm() }
                            if yardPickFarmID == farm.id {
                                yardPickFarmID = nil
                                yardsDraft = ""
                            }
                            removeYards(for: farm.id)
                        } label: {
                            Label("Delete farm", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.10)

                // Yard section header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)

                        Text("Yard locations")
                            .font(.subheadline.weight(.semibold))
                    }

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
                            Label("Manage", systemImage: "pencil")
                        }
                        .glassButton(.compact)
                    }
                }

                if yards.isEmpty {
                    InlineEmptyMessage(
                        title: "No yard locations yet",
                        subtitle: "Add names like Main Yards, Drafting Race or Woolshed.",
                        systemImage: "tray",
                        tint: .orange
                    )
                } else {
                    FlowChips(items: yards)
                        .padding(.top, 2)

                    Text("Tip: Use Manage to rename, delete or reorder yards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                if yardPickFarmID == farm.id {
                    quickAddYardsCard(for: farm.id)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func quickAddYardsCard(for farmID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)

                Text("Quick add yards")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Enter one or more yard names separated by commas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            glassField(
                icon: "mappin.and.ellipse",
                placeholder: "e.g. Main Yards, Drafting Race, Woolshed",
                text: $yardsDraft,
                autocaps: .words
            )

            HStack(spacing: 10) {
                Button {
                    yardsDraft = ""
                    yardPickFarmID = nil
                } label: {
                    Text("Cancel")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .glassButton(.fullWidth)

                Button {
                    saveYards(for: farmID, input: yardsDraft)
                    yardsDraft = ""
                    yardPickFarmID = nil
                } label: {
                    Label("Save yards", systemImage: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(yardsDraft.trimmed.isEmpty)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // =====================================================
    // MARK: - Actions (farm)
    // =====================================================

    private var formValid: Bool {
        !farmName.trimmed.isEmpty && !farmPIC.trimmed.isEmpty
    }

    private var totalYardCount: Int {
        store.farms.reduce(0) { partial, farm in
            partial + yardsFor(farm.id).count
        }
    }

    private func saveFarm() {
        let name = farmName.trimmed
        let pic = farmPIC.trimmed

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
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

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
// MARK: - Flow chips
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
            Image(systemName: "mappin.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

// =====================================================
// MARK: - Helpers
// =====================================================

private struct FarmHeroIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.22), lineWidth: 1)
                )

            Image(systemName: systemImage)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

private struct FarmStatPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 30, height: 30)

                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SmallInfoPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct EmptyStateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 40, height: 40)

                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct InlineEmptyMessage: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// =====================================================
// MARK: - Wrap Layout
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
// MARK: - Manage yards sheet
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
            ZStack {
                GlassBackground()

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 10) {
                                FarmHeroIcon(
                                    systemImage: "mappin.and.ellipse",
                                    tint: .orange,
                                    size: 34
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Manage yards")
                                        .font(.headline)

                                    Text("Add, rename, delete or reorder yard locations for this farm.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }

                            HStack(spacing: 10) {
                                TextField("Add new yard", text: $newYard)
                                    .textInputAutocapitalization(.words)

                                Button {
                                    addNew()
                                } label: {
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
                        .padding(.vertical, 4)
                    }

                    Section("Yards") {
                        if yards.isEmpty {
                            Text("No yards added yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(yards.indices, id: \.self) { i in
                                HStack(spacing: 10) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(.orange)

                                    TextField("Yard name", text: Binding(
                                        get: { yards[i] },
                                        set: { yards[i] = $0 }
                                    ))
                                    .textInputAutocapitalization(.words)
                                }
                                .padding(.vertical, 4)
                            }
                            .onDelete(perform: delete)
                            .onMove(perform: move)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
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
