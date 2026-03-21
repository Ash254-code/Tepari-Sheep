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
    case blue = "Blue"

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

enum YearColourCycle {
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

                ScrollView {
                    VStack(spacing: 14) {
                        SettingsHeroCard(
                            title: "Select Year Colour",
                            subtitle: "Choose the ear tag year. The mob colour is assigned automatically from the yearly cycle.",
                            systemImage: "paintpalette.fill",
                            tint: .orange
                        )

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Year Options")
                                    .font(.headline)

                                Text("Tap a year to use its mapped colour.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Divider().opacity(0.18)

                                VStack(spacing: 10) {
                                    ForEach(years, id: \.self) { y in
                                        let c = YearColourCycle.colour(for: y, anchorYear: anchorYear)

                                        Button {
                                            selectedYear = y
                                            dismiss()
                                        } label: {
                                            YearColourOptionRow(
                                                year: y,
                                                colour: c,
                                                isSelected: y == selectedYear
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
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
    let editMobID: UUID?

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

    private var farmName: String {
        store.farms.first(where: { $0.id == farmID })?.name ?? "Farm"
    }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {
                    SettingsHeroCard(
                        title: editingMob == nil ? "Mob Setup" : "Edit Mob",
                        subtitle: editingMob == nil
                            ? "Create mobs and assign the correct year colour for tagging."
                            : "Update this mob name or change its year colour.",
                        systemImage: "tag.fill",
                        tint: .green
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center, spacing: 12) {
                                SettingsMiniIcon(systemImage: "shippingbox.fill", tint: .green)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(editingMob == nil ? "Add Mob" : "Edit Mob")
                                        .font(.headline)

                                    Text(farmName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mob Name")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                TextField("Mob name", text: $mobName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Year Colour")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Button {
                                    if editingMob == nil && (selectedYear < (currentYear - 8) || selectedYear > anchorYear) {
                                        selectedYear = anchorYear
                                    }
                                    showYearPicker = true
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(selectedColour.color.opacity(0.18))
                                                .frame(width: 34, height: 34)

                                            Circle()
                                                .fill(selectedColour.color)
                                                .frame(width: 14, height: 14)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Selected Colour")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)

                                            Text("\(selectedYear.formatted(.number.grouping(.never))) — \(selectedColour.rawValue)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if !mobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Preview")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    let previewLabel = "\(mobName.trimmingCharacters(in: .whitespacesAndNewlines))-\(selectedYear)"
                                    MobNamePill(
                                        name: previewLabel,
                                        colour: selectedColour
                                    )
                                }
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

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                SettingsMiniIcon(systemImage: "list.bullet.rectangle.portrait.fill", tint: .blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Existing Mobs")
                                        .font(.headline)

                                    Text("Tap Edit or delete a mob from this farm.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }

                            let list = store.mobs(for: farmID)

                            if list.isEmpty {
                                EmptySettingsStateRow(
                                    title: "No mobs yet",
                                    subtitle: "Add your first mob above to get started.",
                                    systemImage: "tray"
                                )
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(list) { mob in
                                        mobRow(mob)

                                        if mob.id != list.last?.id {
                                            Divider().opacity(0.14)
                                        }
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
            VStack(alignment: .leading, spacing: 8) {
                MobNamePill(name: label, colour: colour)

                Text("Tap Edit to update this mob")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    startEdit(mob)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

                Button(role: .destructive) {
                    store.deleteMob(mob.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
            }
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
        selectedYear = inferredYearFromColourHex(mob.colorHex) ?? currentYear
    }

    private func clearForm() {
        editingMob = nil
        mobName = ""
        selectedYear = currentYear
    }
}

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
                    HStack(spacing: 12) {
                        SettingsMiniIcon(systemImage: "building.2.crop.circle.fill", tint: .green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(farmName)
                                .font(.headline.weight(.semibold))

                            if !farmPIC.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("PIC: \(farmPIC)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
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
                    EmptySettingsStateRow(
                        title: "No mobs yet",
                        subtitle: "Add a mob for this farm to start grouping animals.",
                        systemImage: "tray"
                    )
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
// MARK: - Styling helpers
// =====================================================

private struct SettingsHeroCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                SettingsMiniIcon(
                    systemImage: systemImage,
                    tint: tint,
                    size: 52,
                    iconFont: .title2.weight(.semibold)
                )

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
        }
    }
}

private struct SettingsMiniIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 38
    var iconFont: Font = .headline.weight(.semibold)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundStyle(tint)
        }
    }
}

private struct EmptySettingsStateRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsMiniIcon(systemImage: systemImage, tint: .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct YearColourOptionRow: View {
    let year: Int
    let colour: MobColour
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colour.color.opacity(0.18))
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(colour.color)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(year, format: .number.grouping(.never))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(colour.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "circle")
                    .font(.headline)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08), lineWidth: 1)
        )
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
