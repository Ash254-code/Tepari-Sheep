import SwiftUI

// =====================================================
// MARK: - Global Mob Colours (shared)
// =====================================================

enum MobColour: String, CaseIterable, Identifiable {
    case black = "Black"
    case white = "White"
    case orange = "Orange"
    case green = "Green"
    case purple = "Purple"
    case yellow = "Yellow"
    case red = "Red"
    case blue = "Blue"        // using your “Blue” (works for the yearly cycle)

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .black:   return "#000000"
        case .white:   return "#FFFFFF"
        case .orange:  return "#FF9800"
        case .green:   return "#4CAF50"
        case .purple:  return "#9C27B0"
        case .yellow:  return "#FFEB3B"
        case .red:     return "#F44336"
        case .blue:    return "#03A9F4"
        }
    }

    var color: Color {
        Color(hex: hex) ?? .gray
    }

    static func from(hex: String) -> MobColour? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Self.allCases.first { $0.hex.uppercased() == cleaned }
    }
}

// =====================================================
// MARK: - Global Year → Colour Cycle (shared)
// =====================================================
//
// Cycle repeats every 8 years, anchored so:
// (currentYear + 1) is ALWAYS Green
//
enum YearColourCycle {

    // Order must match your mapping above
    static let cycle: [MobColour] = [
        .green, .orange, .white, .black, .blue, .red, .yellow, .purple
    ]

    static func colour(for year: Int, anchorYear: Int) -> MobColour {
        let diff = anchorYear - year
        let idx = mod(diff, cycle.count)
        return cycle[idx]
    }

    static func yearsList(referenceDate: Date = Date()) -> [Int] {
        let currentYear = Calendar.current.component(.year, from: referenceDate)
        let anchorYear = currentYear + 1
        let minYear = currentYear - 8
        return Array(stride(from: anchorYear, through: minYear, by: -1))
    }

    static func mod(_ a: Int, _ n: Int) -> Int {
        let r = a % n
        return r >= 0 ? r : r + n
    }
}

// =====================================================
// MARK: - Global Mob Name Pill (shared)
// =====================================================

struct MobNamePill: View {
    let name: String
    let colour: MobColour

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(name)
            .font(.headline.weight(.semibold))
            .foregroundStyle(bestTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(colour.color.opacity(scheme == .dark ? 0.90 : 0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.10), lineWidth: 1)
            )
            .lineLimit(1)
    }

    private var bestTextColor: Color {
        if colour == .white || colour == .yellow { return .black }
        return .white
    }
}

// =====================================================
// MARK: - Year Colour Picker Sheet (popup)
// =====================================================

private struct YearColourPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let years: [Int]
    let anchorYear: Int

    @Binding var selectedYear: Int

    var body: some View {
        NavigationView {
            ZStack {
                GlassBackground()

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select Year Colour")
                            .font(.headline)

                        Text("Choose the ear tag year. Colour is auto-assigned.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider().opacity(0.22)

                        VStack(spacing: 8) {
                            ForEach(years, id: \.self) { y in
                                let c = YearColourCycle.colour(for: y, anchorYear: anchorYear)

                                Button {
                                    selectedYear = y
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(c.color)
                                            .frame(width: 12, height: 12)

                                        Text(y, format: .number.grouping(.never))
                                            .font(.headline.weight(.semibold))

                                        Text("— \(c.rawValue)")
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        if y == selectedYear {
                                            Image(systemName: "checkmark")
                                                .font(.headline.weight(.semibold))
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// =====================================================
// MARK: - Mob Setup View
// =====================================================

struct MobSetupView: View {
    @EnvironmentObject private var store: LocalDataStore
    @Environment(\.dismiss) private var dismiss

    let farmID: UUID
    let editMobID: UUID?   // ✅ NEW (optional preselect for edit)

    init(farmID: UUID, editMobID: UUID? = nil) {
        self.farmID = farmID
        self.editMobID = editMobID
    }

    @State private var mobName: String = ""

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showYearPicker = false

    @State private var editingMob: LocalDataStore.Mob? = nil

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var anchorYear: Int {
        currentYear + 1
    }

    private var years: [Int] {
        YearColourCycle.yearsList()
    }

    private var selectedColour: MobColour {
        YearColourCycle.colour(for: selectedYear, anchorYear: anchorYear)
    }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    // =====================================================
                    // Add / Edit Mob
                    // =====================================================
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {

                            Text(editingMob == nil ? "Add Mob" : "Edit Mob")
                                .font(.headline)

                            TextField("Mob name", text: $mobName)
                                .textFieldStyle(.roundedBorder)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Colour")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Button {
                                    if editingMob == nil && (selectedYear < (currentYear - 8) || selectedYear > anchorYear) {
                                        selectedYear = anchorYear
                                    }
                                    showYearPicker = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(selectedColour.color)
                                            .frame(width: 10, height: 10)

                                        Text("Colour")
                                            .font(.caption.weight(.semibold))

                                        Text("\(selectedYear.formatted(.number.grouping(.never))) — \(selectedColour.rawValue)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule(style: .continuous))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if !mobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let previewLabel = "\(mobName.trimmingCharacters(in: .whitespacesAndNewlines))-\(selectedYear)"
                                MobNamePill(
                                    name: previewLabel,
                                    colour: selectedColour
                                )
                                .padding(.top, 2)
                            }

                            HStack(spacing: 10) {
                                Button(editingMob == nil ? "Add Mob" : "Save Changes") {
                                    saveMob()
                                }
                                .buttonStyle(GlassButtonStyle())
                                .disabled(!formValid)

                                if editingMob != nil {
                                    Button("Cancel Edit") {
                                        clearForm()
                                    }
                                    .buttonStyle(GlassButtonStyle())
                                }
                            }
                        }
                    }

                    // =====================================================
                    // Existing mobs (for this farm)
                    // =====================================================
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Existing Mobs")
                                .font(.headline)

                            let list = store.mobs(for: farmID)

                            if list.isEmpty {
                                Text("No mobs yet for this farm.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(list) { mob in
                                        mobRow(mob)
                                        Divider().opacity(0.18)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            // ✅ If opened from overview in edit mode, preselect that mob.
            guard let editMobID else { return }
            if let mob = store.mobs(for: farmID).first(where: { $0.id == editMobID }) {
                startEdit(mob)
            }
        }
        .navigationTitle("Mobs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showYearPicker) {
            YearColourPickerSheet(
                years: years,
                anchorYear: anchorYear,
                selectedYear: $selectedYear
            )
        }
    }

    // =====================================================
    // MARK: - Year inference (from saved colour hex)
    // =====================================================

    private func inferredYearFromColourHex(_ hex: String) -> Int? {
        guard let mobColour = MobColour.from(hex: hex) else { return nil }
        let years = YearColourCycle.yearsList(referenceDate: Date())
        return years.first { YearColourCycle.colour(for: $0, anchorYear: anchorYear) == mobColour }
    }

    // =====================================================
    // MARK: - Row
    // =====================================================

    private func mobRow(_ mob: LocalDataStore.Mob) -> some View {
        let colour = MobColour.from(hex: mob.colorHex) ?? .green
        let year = inferredYearFromColourHex(mob.colorHex)
        let label = year == nil ? mob.name : "\(mob.name)-\(year!)"

        return HStack(spacing: 12) {
            MobNamePill(name: label, colour: colour)

            Spacer()

            Button("Edit") { startEdit(mob) }
                .buttonStyle(.plain)

            Button(role: .destructive) {
                store.deleteMob(mob.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    // =====================================================
    // MARK: - Actions
    // =====================================================

    private var formValid: Bool {
        !mobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveMob() {
        let name = mobName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = selectedColour.hex

        if var mob = editingMob {
            mob.name = name
            mob.colorHex = hex
            store.updateMob(mob)
        } else {
            store.addMob(farmID: farmID, name: name, colorHex: hex)
        }

        clearForm()
    }

    private func startEdit(_ mob: LocalDataStore.Mob) {
        editingMob = mob
        mobName = mob.name

        // Best-effort: infer the year from the saved colour, default to currentYear if unknown.
        selectedYear = inferredYearFromColourHex(mob.colorHex) ?? currentYear
    }

    private func clearForm() {
        editingMob = nil
        mobName = ""
        selectedYear = currentYear
    }
}

// =====================================================
// MARK: - Mobs Overview (grouped by farm)
// =====================================================



// =====================================================
// MARK: - Farm Card (with mobs inside)
// =====================================================

private struct FarmMobsCard: View {
    let farmName: String
    let farmPIC: String
    let mobs: [LocalDataStore.Mob]

    let onAddMob: () -> Void
    let onEditMob: (LocalDataStore.Mob) -> Void
    let onDeleteMob: (LocalDataStore.Mob) -> Void

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var anchorYear: Int {
        currentYear + 1
    }

    private func inferredYearFromColourHex(_ hex: String) -> Int? {
        guard let mobColour = MobColour.from(hex: hex) else { return nil }
        let years = YearColourCycle.yearsList(referenceDate: Date())
        return years.first { YearColourCycle.colour(for: $0, anchorYear: anchorYear) == mobColour }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(farmName)
                            .font(.headline.weight(.semibold))

                        if !farmPIC.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("PIC: \(farmPIC)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        onAddMob()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Mob")
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                Divider().opacity(0.18)

                if mobs.isEmpty {
                    Text("No mobs yet for this farm.")
                        .foregroundStyle(.secondary)
                } else {
                    FlowWrapLayout(spacing: 10, lineSpacing: 10) {
                        ForEach(mobs) { mob in
                            let colour = MobColour.from(hex: mob.colorHex) ?? .green
                            let year = inferredYearFromColourHex(mob.colorHex)
                            let label = year == nil ? mob.name : "\(mob.name)-\(year!)"

                            MobNamePill(name: label, colour: colour)
                                .onTapGesture {
                                    onEditMob(mob)
                                }
                                .contextMenu {
                                    Button {
                                        onEditMob(mob)
                                    } label: {
                                        Label("Edit Mob", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        onDeleteMob(mob)
                                    } label: {
                                        Label("Delete Mob", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

// =====================================================
// MARK: - Flow Wrap Layout (pills wrap to next line)
// =====================================================

private struct FlowWrapLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {

        let maxWidth = proposal.width ?? .greatestFiniteMagnitude

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)

            if x > 0, (x + size.width) > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            x += (x == 0 ? 0 : spacing) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: proposal.width ?? maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width

        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)

            if x > bounds.minX, (x + size.width) > (bounds.minX + maxWidth) {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            s.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// =====================================================
// MARK: - Hex Color helper
// =====================================================

private extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self = Color(red: r, green: g, blue: b)
    }
}
