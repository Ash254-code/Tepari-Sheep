import SwiftUI
import Charts

struct IndividualAnimalView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    // Editable fields
    @State private var sex: LocalDataStore.Sex? = nil
    @State private var selectedMobID: UUID? = nil
    @State private var animalClass: LocalDataStore.AnimalClass? = nil
    @State private var animalStatus: AnimalStatus? = nil
    @State private var comments: String = ""
    @State private var user1: String = ""
    @State private var user2: String = ""

    @State private var lastLoadedEID: String = "—"
    @State private var resolvedFarmID: UUID? = nil

    @State private var showAllWeights: Bool = false
    @State private var showAllTreatments: Bool = false
    @State private var showAllPregTests: Bool = false
    @State private var showAllLambing: Bool = false

    private let pagePadding: CGFloat = 14
    private let sectionSpacing: CGFloat = 14

    private struct WeightPoint: Identifiable {
        let id = UUID()
        let date: Date
        let weight: Double
    }

    private struct SnapshotData {
        let weight: String
        let micron: String
        let staple: String
        let fleece: String
        let totalLambs: String
        let lambing: String
    }

    private var weightChartPoints: [WeightPoint] {
        weightHistory
            .filter { $0.lockedWeight > 0 }
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { WeightPoint(date: $0.recordedAt, weight: $0.lockedWeight) }
    }

    private var latestWeightValue: String {
        guard let latest = weightHistory.first(where: { $0.lockedWeight > 0 }) else { return "—" }
        return "\(formatOneDecimal(latest.lockedWeight)) kg"
    }

    private var latestMicronValue: String {
        guard let value = latestTraitRow?.micron else { return "—" }
        return formatOneDecimal(value)
    }

    private var latestStapleValue: String {
        if let value = latestTraitRow?.stapleLengthMm {
            return "\(value) mm"
        }
        if let value = profile?.stapleLengthMm {
            return "\(formatNoDecimal(value)) mm"
        }
        return "—"
    }

    private var latestFleeceValue: String {
        if let value = latestTraitRow?.fleeceWeightKg {
            return "\(formatUpToTwoDecimals(value)) kg"
        }
        if let value = profile?.fleeceWeightKg {
            return "\(formatUpToTwoDecimals(value)) kg"
        }
        return "—"
    }

    private var totalLambsValue: String {
        guard displayEID != "—", !displayEID.isEmpty else { return "—" }
        guard let farmID = preferredFarmID else { return "—" }

        let total = store.totalLambsForAnimal(
            farmID: farmID,
            eidRaw: displayEID
        )
        return "\(total)"
    }

    private var latestLambingValue: String {
        guard let latest = lambingHistory.first else { return "—" }
        return latest.summary
    }

    private var latestSnapshotData: SnapshotData {
        SnapshotData(
            weight: latestWeightValue,
            micron: latestMicronValue,
            staple: latestStapleValue,
            fleece: latestFleeceValue,
            totalLambs: totalLambsValue,
            lambing: latestLambingValue
        )
    }

    private var chartYMin: Double {
        let values = weightChartPoints.map(\.weight)
        guard let min = values.min() else { return 0 }
        return max(0, floor((min - 2) / 5) * 5)
    }

    private var chartYMax: Double {
        let values = weightChartPoints.map(\.weight)
        guard let max = values.max() else { return 10 }
        return ceil((max + 2) / 5) * 5
    }

    private var displayEID: String {
        EIDValidator.cleanedRaw(coordinator.displayEID)
    }

    private var activeFarmID: UUID? {
        guard let sid = coordinator.activeSessionID else { return nil }
        return store.farmID(for: sid)
    }

    private var preferredFarmID: UUID? {
        coordinator.selectedIndividualAnimalFarmID ?? resolvedFarmID ?? activeFarmID
    }

    private var profile: LocalDataStore.AnimalProfile? {
        guard displayEID != "—", !displayEID.isEmpty else { return nil }

        if let farmID = preferredFarmID,
           let exact = store.animalProfile(farmID: farmID, eidRaw: displayEID) {
            return exact
        }

        if let activeFarmID,
           let active = store.animalProfile(farmID: activeFarmID, eidRaw: displayEID) {
            return active
        }

        return store.animalProfileAnyFarm(eidRaw: displayEID)
    }

    private var history: [AnimalRecord] {
        store.allRecords(forEID: displayEID)
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    private var detailsDirty: Bool {
        let existing = profile

        return sex != existing?.sex
            || selectedMobID != existing?.mobID
            || animalClass != existing?.animalClass
            || animalStatus != existing?.status
            || comments.trimmedOrNil != existing?.comments?.trimmedOrNil
            || user1.trimmedOrNil != existing?.userField1?.trimmedOrNil
            || user2.trimmedOrNil != existing?.userField2?.trimmedOrNil
    }

    private func applyDetailsEdits() {
        guard detailsDirty, canSave else { return }
        saveEdits()
    }

    private var weightHistory: [AnimalRecord] {
        history.filter { $0.lockedWeight > 0 }
    }

    private var treatmentHistory: [TreatmentHistoryRow] {
        let eid = displayEID
        guard !eid.isEmpty, eid != "—" else { return [] }

        return store.animalEvents
            .filter { event in
                event.kind == .treatment &&
                EIDValidator.cleanedRaw(event.eidRaw) == eid &&
                (preferredFarmID == nil || event.farmID == preferredFarmID)
            }
            .sorted { $0.date > $1.date }
            .map { event in
                TreatmentHistoryRow(
                    title: event.text1 ?? "Treatment",
                    subtitle: event.text2,
                    date: event.date
                )
            }
    }

    private var pregHistory: [PregHistoryRow] {
        let eid = displayEID
        guard !eid.isEmpty, eid != "—" else { return [] }

        return store.animalEvents
            .filter { event in
                event.kind == .pregnancy &&
                EIDValidator.cleanedRaw(event.eidRaw) == eid &&
                (preferredFarmID == nil || event.farmID == preferredFarmID)
            }
            .sorted { $0.date > $1.date }
            .map { event in
                PregHistoryRow(
                    date: event.date,
                    status: event.text1 ?? "Pregnancy",
                    fetusCount: event.int1,
                    method: event.text2
                )
            }
    }

    private var lambingHistory: [LambingHistoryRow] {
        guard let farmID = preferredFarmID else { return [] }

        return store.lambingEventsForAnimal(farmID: farmID, eidRaw: displayEID)
            .map { event in
                let year = event.int1 ?? Calendar.current.component(.year, from: event.date)
                let born = event.json?["born"].flatMap(Int.init)
                let weaned = event.json?["weaned"].flatMap(Int.init)
                let notes = event.json?["notes"]

                return LambingHistoryRow(
                    date: event.date,
                    year: year,
                    born: born,
                    weaned: weaned,
                    notes: notes
                )
            }
            .sorted { lhs, rhs in
                if lhs.year != rhs.year { return lhs.year > rhs.year }
                return lhs.date > rhs.date
            }
    }

    private var latestTraitRow: TraitHistoryRow? {
        let eid = displayEID
        guard !eid.isEmpty, eid != "—" else { return nil }

        return store.animalEvents
            .filter { event in
                event.kind == .traits &&
                EIDValidator.cleanedRaw(event.eidRaw) == eid &&
                (preferredFarmID == nil || event.farmID == preferredFarmID)
            }
            .sorted { $0.date > $1.date }
            .map { event in
                TraitHistoryRow(
                    date: event.date,
                    micron: event.number1,
                    stapleLengthMm: event.int1,
                    fleeceWeightKg: parseDouble(event.json?["fleeceWeightKg"])
                )
            }
            .first
    }

    private var canSave: Bool {
        displayEID != "—" && !displayEID.isEmpty
    }

    private var liveWeightText: String? {
        guard coordinator.focusedEID == nil else { return nil }
        return String(format: "%.1f kg", coordinator.weight)
    }

    private var liveStateText: String? {
        guard coordinator.focusedEID == nil else { return nil }
        if coordinator.locked { return "Locked" }
        if coordinator.stable { return "Stable" }
        return "Live"
    }

    private var availableMobsForAnimal: [LocalDataStore.Mob] {
        guard let farmID = preferredFarmID else { return [] }
        return store.mobs(for: farmID).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var currentMob: LocalDataStore.Mob? {
        let mobID = selectedMobID ?? profile?.mobID
        guard let mobID else { return nil }
        return store.mobs.first(where: { $0.id == mobID })
    }

    private var currentMobColor: Color? {
        guard let mob = currentMob else { return nil }
        let hex = mob.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty else { return nil }
        return colorFromHex(hex)
    }

    private var eidPillFill: Color {
        currentMobColor ?? (scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82))
    }

    private var eidPillStroke: Color {
        if let mobColor = currentMobColor {
            return mobColor.opacity(scheme == .dark ? 0.95 : 0.80)
        }
        return scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var eidPillText: Color {
        guard let mobColor = currentMobColor else { return .primary }
        return preferredTextColor(for: mobColor)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                ZStack {
                    GlassBackground()

                    ScrollView {
                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            if displayEID == "—" || displayEID.isEmpty {
                                emptyGlass
                            } else if isLandscape {
                                landscapeContent
                            } else {
                                portraitContent
                            }
                        }
                        .padding(.horizontal, pagePadding)
                        .padding(.top, pagePadding)
                        .padding(.bottom, 120)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .navigationTitle("Individual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if coordinator.showIndividualAnimalView {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            coordinator.closeIndividualAnimal()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .onAppear {
                applyCoordinatorSelectionIfNeeded()
                loadFromStoreIfNeeded(force: true)
            }
            .onChange(of: coordinator.displayEID) { _, _ in
                applyCoordinatorSelectionIfNeeded()
                loadFromStoreIfNeeded(force: true)
            }
            .onChange(of: coordinator.selectedIndividualAnimalEID) { _, _ in
                applyCoordinatorSelectionIfNeeded()
                loadFromStoreIfNeeded(force: true)
            }
            .onChange(of: coordinator.selectedIndividualAnimalFarmID) { _, _ in
                applyCoordinatorSelectionIfNeeded()
                loadFromStoreIfNeeded(force: true)
            }
        }
    }

    // =====================================================
    // MARK: - Layout
    // =====================================================

    private var portraitContent: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            identityGlass
            latestSnapshotGlass
            detailsGlass
            lambingHistoryGlass
            weightTrendGlass
            weightHistoryGlass
            treatmentHistoryGlass
            pregHistoryGlass
        }
    }

    private var landscapeContent: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            identityGlass

            HStack(alignment: .top, spacing: sectionSpacing) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    latestSnapshotGlass
                    detailsGlass
                    lambingHistoryGlass
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: sectionSpacing) {
                    weightTrendGlass
                    weightHistoryGlass
                    treatmentHistoryGlass
                    pregHistoryGlass
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // =====================================================
    // MARK: - Snapshot
    // =====================================================

    private var latestSnapshotGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(
                    title: "Latest Snapshot",
                    subtitle: "Current values",
                    icon: "waveform.path.ecg.rectangle.fill",
                    tint: .blue
                ) {
                    labelChip("Now")
                        .fixedSize()
                }
                Divider().opacity(0.10)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        snapshotValueCard(title: "Weight", value: latestWeightValue, icon: "scalemass", tint: .blue)
                        snapshotValueCard(title: "Micron", value: latestMicronValue, icon: "waveform.path.ecg", tint: .purple)
                    }

                    HStack(spacing: 10) {
                        snapshotValueCard(title: "Staple", value: latestStapleValue, icon: "ruler", tint: .orange)
                        snapshotValueCard(title: "Fleece", value: latestFleeceValue, icon: "tshirt.fill", tint: .teal)
                    }

                    HStack(spacing: 10) {
                        snapshotValueCard(title: "Total Lambs", value: totalLambsValue, icon: "sum", tint: .green)
                        snapshotValueCard(title: "Lambing", value: latestLambingValue, icon: "hare.fill", tint: .pink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func snapshotValueCard(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.monochrome)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(normalizeSnapshotValue(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(glassFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(glassFieldStroke, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    // =====================================================
    // MARK: - Empty
    // =====================================================

    private var emptyGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(
                    title: "No animal loaded",
                    subtitle: "Scan an animal to open its details",
                    icon: "dot.scope",
                    tint: .orange
                )
            }
        }
    }

    // =====================================================
    // MARK: - Identity
    // =====================================================

    private var identityGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(profile?.eidRaw ?? displayEID)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .foregroundStyle(eidPillText)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(eidPillFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(eidPillStroke, lineWidth: 1)
                            )

                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(resolvedFarmID.flatMap(farmName) ?? "Unknown farm")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 8) {
                        if let w = liveWeightText {
                            Text(w)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .lineLimit(1)

                            if let state = liveStateText {
                                statusChip(
                                    state,
                                    tone: coordinator.locked ? .good : (coordinator.stable ? .good : .muted),
                                    icon: coordinator.locked ? "lock.fill" : (coordinator.stable ? "checkmark.seal.fill" : "dot.radiowaves.left.and.right")
                                )
                            }
                        } else {
                            statusChip("Manual", tone: .muted, icon: "hand.tap")
                        }
                    }
                }

                HStack(spacing: 8) {
                    detailPill(currentMob?.name ?? "No Mob", tint: currentMobColor ?? .green, icon: "person.3.fill")
                    detailPill(animalClass?.label ?? profile?.animalClass?.label ?? "No Class", tint: .purple, icon: "tag.fill")
                    detailPill(animalStatus?.label ?? profile?.status?.label ?? "No Status", tint: .orange, icon: "exclamationmark.circle.fill")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // =====================================================
    // MARK: - Details
    // =====================================================

    private var detailsGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(
                    title: "Details",
                    subtitle: "Edit animal fields",
                    icon: "slider.horizontal.3",
                    tint: .orange
                )

                Divider().opacity(0.10)

                HStack(spacing: 10) {
                    glassMenuPicker(
                        title: "Sex",
                        value: sex?.label ?? "—",
                        icon: "person.fill"
                    ) {
                        Picker("Sex", selection: bindingSex()) {
                            Text("—").tag(LocalDataStore.Sex?.none)
                            ForEach(LocalDataStore.Sex.allCases) { s in
                                Text(s.label).tag(LocalDataStore.Sex?.some(s))
                            }
                        }
                    }

                    glassMenuPicker(
                        title: "Mob",
                        value: currentMob?.name ?? "—",
                        icon: "person.3.fill"
                    ) {
                        Picker("Mob", selection: bindingMobID()) {
                            Text("—").tag(UUID?.none)
                            ForEach(availableMobsForAnimal) { mob in
                                Text(mob.name).tag(UUID?.some(mob.id))
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    glassMenuPicker(
                        title: "Class",
                        value: animalClass?.label ?? "—",
                        icon: "tag.fill"
                    ) {
                        Picker("Class", selection: bindingClass()) {
                            Text("—").tag(LocalDataStore.AnimalClass?.none)
                            ForEach(LocalDataStore.AnimalClass.allCases) { c in
                                Text(c.label).tag(LocalDataStore.AnimalClass?.some(c))
                            }
                        }
                    }

                    glassMenuPicker(
                        title: "Status",
                        value: animalStatus?.label ?? "—",
                        icon: "exclamationmark.circle.fill"
                    ) {
                        Picker("Status", selection: bindingStatus()) {
                            Text("—").tag(AnimalStatus?.none)
                            ForEach(AnimalStatus.allCases) { status in
                                Text(status.label).tag(AnimalStatus?.some(status))
                            }
                        }
                    }
                }

                glassTextField(
                    title: "Comments",
                    text: $comments,
                    icon: "text.bubble.fill",
                    isMultiline: true
                )

                HStack(spacing: 10) {
                    glassTextField(
                        title: "User Field 1",
                        text: $user1,
                        icon: "1.circle.fill",
                        isMultiline: false
                    )

                    glassTextField(
                        title: "User Field 2",
                        text: $user2,
                        icon: "2.circle.fill",
                        isMultiline: false
                    )
                }

                quickPicksRow

                HStack {
                    Spacer()

                    Button("Save") {
                        applyDetailsEdits()
                    }
                    .disabled(!detailsDirty || !canSave)
                    .foregroundStyle(detailsDirty && canSave ? .white : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        detailsDirty && canSave
                        ? Color.accentColor
                        : Color.gray.opacity(scheme == .dark ? 0.28 : 0.18)
                    )
                    .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quickPicksRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comment quick picks")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickAdd("Un-mulesed", token: "un-mulesed", icon: "checkmark.seal.fill")
                    quickAdd("Black wool", token: "black wool", icon: "circle.lefthalf.filled")
                    quickAdd("Lame", token: "lame", icon: "cross.case.fill")
                }
                .padding(.vertical, 1)
            }
        }
    }

    // =====================================================
    // MARK: - Lambing History
    // =====================================================

    private var visibleLambing: [LambingHistoryRow] {
        showAllLambing ? lambingHistory : Array(lambingHistory.prefix(5))
    }

    private var lambingHistoryGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHistoryHeader(
                    title: "Lambing History",
                    subtitle: "Born and weaned history",
                    icon: "hare.fill",
                    tint: .pink,
                    count: lambingHistory.count,
                    expandTitle: showAllLambing ? "Collapse" : "Show all"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllLambing.toggle()
                    }
                }

                Divider().opacity(0.10)

                if lambingHistory.isEmpty {
                    emptySectionText("No lambing records yet for this animal.")
                } else if showAllLambing {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(visibleLambing) { row in
                                lambingRow(row)

                                if row.id != visibleLambing.last?.id {
                                    Divider().opacity(0.08)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleLambing) { row in
                            lambingRow(row)

                            if row.id != visibleLambing.last?.id {
                                Divider().opacity(0.08)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func lambingRow(_ row: LambingHistoryRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sectionIcon(icon: "hare.fill", tint: .pink, size: 30)
                .fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                Text(row.summary)
                    .font(.subheadline.weight(.semibold))

                if let notes = row.notes?.trimmedOrNil {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(row.year))
                    .font(.subheadline.weight(.semibold))

                Text(row.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    // =====================================================
    // MARK: - Weight Trend
    // =====================================================

    private var weightTrendGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(
                    title: "Weight Trend",
                    subtitle: "Visual trend over time",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .blue
                ) {
                    labelChip("\(weightChartPoints.count)")
                        .fixedSize()
                }
                Divider().opacity(0.10)

                if weightChartPoints.count < 2 {
                    emptySectionText("At least 2 weights are needed to show a trend.")
                } else {
                    Chart(weightChartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                        .opacity(0.18)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.weight)
                        )
                    }
                    .chartYScale(domain: chartYMin...chartYMax)
                    .frame(height: 190)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    // =====================================================
    // MARK: - Weight History
    // =====================================================

    private var visibleWeights: [AnimalRecord] {
        showAllWeights ? weightHistory : Array(weightHistory.prefix(5))
    }

    private var weightHistoryGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHistoryHeader(
                    title: "Weight History",
                    subtitle: "Recorded weights",
                    icon: "scalemass",
                    tint: .blue,
                    count: weightHistory.count,
                    expandTitle: showAllWeights ? "Collapse" : "Show all"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllWeights.toggle()
                    }
                }

                Divider().opacity(0.10)

                if weightHistory.isEmpty {
                    emptySectionText("No weights yet for this animal.")
                } else if showAllWeights {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(visibleWeights, id: \.id) { r in
                                weightRow(r)

                                if r.id != visibleWeights.last?.id {
                                    Divider().opacity(0.08)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleWeights, id: \.id) { r in
                            weightRow(r)

                            if r.id != visibleWeights.last?.id {
                                Divider().opacity(0.08)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func weightRow(_ r: AnimalRecord) -> some View {
        HStack(spacing: 12) {
            sectionIcon(icon: "scalemass", tint: .blue, size: 30)
                .fixedSize()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f kg", r.lockedWeight))
                    .font(.subheadline.weight(.semibold))

                Text(sessionName(r.sessionID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(r.recordedAt, style: .date)
                .font(.subheadline)
        }
        .padding(.vertical, 10)
    }

    // =====================================================
    // MARK: - Treatment History
    // =====================================================

    private var visibleTreatments: [TreatmentHistoryRow] {
        showAllTreatments ? treatmentHistory : Array(treatmentHistory.prefix(5))
    }

    private var treatmentHistoryGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHistoryHeader(
                    title: "Treatment History",
                    subtitle: "Treatments and dosage notes",
                    icon: "cross.case.fill",
                    tint: .green,
                    count: treatmentHistory.count,
                    expandTitle: showAllTreatments ? "Collapse" : "Show all"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllTreatments.toggle()
                    }
                }

                Divider().opacity(0.10)

                if treatmentHistory.isEmpty {
                    emptySectionText("No treatments yet for this animal.")
                } else if showAllTreatments {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(visibleTreatments) { row in
                                treatmentRow(row)

                                if row.id != visibleTreatments.last?.id {
                                    Divider().opacity(0.08)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleTreatments) { row in
                            treatmentRow(row)

                            if row.id != visibleTreatments.last?.id {
                                Divider().opacity(0.08)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func treatmentRow(_ row: TreatmentHistoryRow) -> some View {
        HStack(spacing: 12) {
            sectionIcon(icon: "cross.case.fill", tint: .green, size: 30)
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))

                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(row.date, style: .date)
                .font(.subheadline)
        }
        .padding(.vertical, 10)
    }

    // =====================================================
    // MARK: - Preg Test History
    // =====================================================

    private var visiblePregTests: [PregHistoryRow] {
        showAllPregTests ? pregHistory : Array(pregHistory.prefix(5))
    }

    private var pregHistoryGlass: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHistoryHeader(
                    title: "Preg Test History",
                    subtitle: "Pregnancy results",
                    icon: "stethoscope",
                    tint: .purple,
                    count: pregHistory.count,
                    expandTitle: showAllPregTests ? "Collapse" : "Show all"
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllPregTests.toggle()
                    }
                }

                Divider().opacity(0.10)

                if pregHistory.isEmpty {
                    emptySectionText("No preg test entries yet.")
                } else if showAllPregTests {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(visiblePregTests) { row in
                                pregRow(row)

                                if row.id != visiblePregTests.last?.id {
                                    Divider().opacity(0.08)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visiblePregTests) { row in
                            pregRow(row)

                            if row.id != visiblePregTests.last?.id {
                                Divider().opacity(0.08)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func pregRow(_ row: PregHistoryRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sectionIcon(icon: "stethoscope", tint: .purple, size: 30)
                .fixedSize()

            VStack(alignment: .leading, spacing: 4) {
                Text(row.summary)
                    .font(.subheadline.weight(.semibold))

                if let method = row.method, !method.isEmpty {
                    Text(method)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(row.date, style: .date)
                .font(.subheadline)
        }
        .padding(.vertical, 10)
    }

    // =====================================================
    // MARK: - Load / Save
    // =====================================================

    private func applyCoordinatorSelectionIfNeeded() {
        if let selectedEID = coordinator.selectedIndividualAnimalEID,
           !selectedEID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedFarmID = coordinator.selectedIndividualAnimalFarmID ?? resolvedFarmID
        }
    }

    private func loadFromStoreIfNeeded(force: Bool = false) {
        let eid = displayEID
        guard eid != "—", !eid.isEmpty else {
            lastLoadedEID = "—"
            resolvedFarmID = nil
            sex = nil
            selectedMobID = nil
            animalClass = nil
            animalStatus = nil
            comments = ""
            user1 = ""
            user2 = ""
            return
        }

        if !force, eid == lastLoadedEID { return }
        lastLoadedEID = eid

        if let selectedFarmID = coordinator.selectedIndividualAnimalFarmID,
           store.animalProfile(farmID: selectedFarmID, eidRaw: eid) != nil {
            resolvedFarmID = selectedFarmID
        } else if let f = activeFarmID,
                  store.animalProfile(farmID: f, eidRaw: eid) != nil {
            resolvedFarmID = f
        } else if let p = store.animalProfileAnyFarm(eidRaw: eid) {
            resolvedFarmID = p.farmID
        } else {
            resolvedFarmID = coordinator.selectedIndividualAnimalFarmID
        }

        if let p = profile {
            sex = p.sex
            selectedMobID = p.mobID
            animalClass = p.animalClass
            animalStatus = p.status
            comments = p.comments ?? ""
            user1 = p.userField1 ?? ""
            user2 = p.userField2 ?? ""
        } else {
            sex = nil
            selectedMobID = nil
            animalClass = nil
            animalStatus = nil
            comments = ""
            user1 = ""
            user2 = ""
        }
    }

    private func saveEdits() {
        let eid = displayEID
        guard eid != "—", !eid.isEmpty else { return }

        let farmID: UUID
        if let f = resolvedFarmID {
            farmID = f
        } else {
            guard let anyFarm = store.farms.first?.id else { return }
            farmID = anyFarm
            resolvedFarmID = anyFarm
        }

        let base = store.animalProfile(farmID: farmID, eidRaw: eid)
            ?? LocalDataStore.AnimalProfile(farmID: farmID, eidRaw: eid)

        var updated = base
        updated.sex = sex
        updated.mobID = selectedMobID
        updated.animalClass = animalClass
        updated.status = animalStatus
        updated.comments = comments.trimmedOrNil
        updated.userField1 = user1.trimmedOrNil
        updated.userField2 = user2.trimmedOrNil

        store.upsertAnimal(updated)
        loadFromStoreIfNeeded(force: true)
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        let r, g, b, a: Double

        if cleaned.count == 8 {
            a = Double((value & 0xFF000000) >> 24) / 255.0
            r = Double((value & 0x00FF0000) >> 16) / 255.0
            g = Double((value & 0x0000FF00) >> 8) / 255.0
            b = Double(value & 0x000000FF) / 255.0
        } else {
            a = 1.0
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private func preferredTextColor(for color: Color) -> Color {
        #if canImport(UIKit)
        let uiColor = UIColor(color)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .white
        }

        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.7 ? .black : .white
        #else
        return .white
        #endif
    }

    private func parseDouble(_ text: String?) -> Double? {
        guard let text else { return nil }
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func formatNoDecimal(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formatUpToTwoDecimals(_ value: Double) -> String {
        let s = String(format: "%.2f", value)
        var t = s
        while t.contains(".") && (t.hasSuffix("0") || t.hasSuffix(".")) {
            t.removeLast()
        }
        return t
    }

    private func normalizeSnapshotValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func bindingSex() -> Binding<LocalDataStore.Sex?> {
        Binding(get: { sex }, set: { sex = $0 })
    }

    private func bindingMobID() -> Binding<UUID?> {
        Binding(get: { selectedMobID }, set: { selectedMobID = $0 })
    }

    private func bindingClass() -> Binding<LocalDataStore.AnimalClass?> {
        Binding(get: { animalClass }, set: { animalClass = $0 })
    }

    private func bindingStatus() -> Binding<AnimalStatus?> {
        Binding(get: { animalStatus }, set: { animalStatus = $0 })
    }

    private func farmName(_ id: UUID) -> String {
        store.farms.first(where: { $0.id == id })?.name ?? "Unknown farm"
    }

    private func sessionName(_ id: UUID) -> String {
        store.sessions.first(where: { $0.id == id })?.name ?? "Session"
    }

    // =====================================================
    // MARK: - Quick add
    // =====================================================

    private func quickAdd(_ title: String, token: String, icon: String) -> some View {
        Button {
            addTokenToComments(token)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(glassFieldFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(glassFieldStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func addTokenToComments(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        let existing = comments
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if existing.contains(t.lowercased()) { return }

        let trimmed = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            comments = t
        } else {
            comments = trimmed.hasSuffix(",") ? "\(trimmed) \(t)" : "\(trimmed), \(t)"
        }
    }

    // =====================================================
    // MARK: - Glass building blocks
    // =====================================================

    private var glassFieldFill: Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.70)
    }

    private var glassFieldStroke: Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private enum PillTone { case good, warn, muted }

    private func sectionIcon(icon: String, tint: Color, size: CGFloat = 28) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.18 : 0.12))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(scheme == .dark ? 0.20 : 0.10), lineWidth: 1)

            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .fixedSize()
    }
    private func sectionTitle<Trailing: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            sectionIcon(icon: icon, tint: tint)
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
                .fixedSize()
        }
    }

    private func sectionTitle(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            sectionIcon(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
    private func sectionHistoryHeader(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        count: Int,
        expandTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        sectionTitle(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: tint
        ) {
            HStack(spacing: 8) {
                labelChip("\(count)")
                if count > 5 {
                    Button(expandTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
    
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
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

    private func detailPill(_ text: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(scheme == .dark ? 0.38 : 0.22), lineWidth: 1)
        )
    }

    private func emptySectionText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func statusChip(_ text: String, tone: PillTone, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(pillFill(tone))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(pillStroke(tone), lineWidth: 1)
        )
        .foregroundStyle(pillText(tone))
    }

    private func pillFill(_ tone: PillTone) -> Color {
        let base: Color
        switch tone {
        case .good: base = .green
        case .warn: base = .orange
        case .muted: base = .secondary
        }
        return base.opacity(scheme == .dark ? 0.20 : 0.12)
    }

    private func pillStroke(_ tone: PillTone) -> Color {
        let base: Color
        switch tone {
        case .good: base = .green
        case .warn: base = .orange
        case .muted: base = .secondary
        }
        return base.opacity(scheme == .dark ? 0.45 : 0.30)
    }

    private func pillText(_ tone: PillTone) -> Color {
        switch tone {
        case .good: return .green
        case .warn: return .orange
        case .muted: return .secondary
        }
    }

    private func glassTextField(title: String, text: Binding<String>, icon: String, isMultiline: Bool) -> some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, isMultiline ? 12 : 0)

            if isMultiline {
                TextField(title, text: text, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(glassFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(glassFieldStroke, lineWidth: 1)
        )
    }

    private func glassMenuPicker<Content: View>(
        title: String,
        value: String,
        icon: String,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        Menu {
            picker()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(glassFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(glassFieldStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private struct TreatmentHistoryRow: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let date: Date
    }

    private struct TraitHistoryRow: Identifiable {
        let id = UUID()
        let date: Date
        let micron: Double?
        let stapleLengthMm: Int?
        let fleeceWeightKg: Double?
    }

    private struct PregHistoryRow: Identifiable {
        let id = UUID()
        let date: Date
        let status: String
        let fetusCount: Int?
        let method: String?

        var summary: String {
            let cleanStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fetusCount {
                return "\(cleanStatus) - \(fetusCount)"
            }
            return cleanStatus
        }
    }

    private struct LambingHistoryRow: Identifiable {
        let id = UUID()
        let date: Date
        let year: Int
        let born: Int?
        let weaned: Int?
        let notes: String?

        var summary: String {
            var parts: [String] = []

            if let born {
                parts.append("Born \(born)")
            }

            if let weaned {
                parts.append("Weaned \(weaned)")
            }

            if parts.isEmpty {
                return "\(year) - No values"
            }

            return "\(year) - " + parts.joined(separator: " · ")
        }
    }
}

// =====================================================
// MARK: - Small helpers
// =====================================================

private extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
