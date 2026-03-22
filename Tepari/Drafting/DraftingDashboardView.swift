import SwiftUI

struct DraftDashboardView: View {

    @EnvironmentObject private var drafter: DrafterController
    @EnvironmentObject private var sessionCoordinator: ActiveSessionCoordinator
    @EnvironmentObject private var draftSettings: DraftSettings
    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var vm: SessionViewModel
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var animalClassStore: AnimalClassStore

    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhoneCompact: Bool { hSize == .compact }

    private var autoReleaseEnabledBinding: Binding<Bool> {
        Binding(
            get: { draftSettings.autoReleaseMode != .off },
            set: { isOn in
                draftSettings.autoReleaseMode = isOn ? .on : .off
            }
        )
    }

    private var autoReleaseStatusText: String {
        autoReleaseEnabledBinding.wrappedValue
            ? "Auto release is on. After the gate hold time, the animal will release automatically."
            : "Auto release is off. The animal stays held until another control action happens."
    }

    @AppStorage("draft.audio.left") private var leftGateAudioID: String = ""
    @AppStorage("draft.audio.straight") private var straightGateAudioID: String = ""
    @AppStorage("draft.audio.right") private var rightGateAudioID: String = ""
    @AppStorage("draft.audio.gate4") private var gate4AudioID: String = ""

    // =====================================================
    // MARK: - Local setup state
    // =====================================================

    private enum DraftGateBucket: String, CaseIterable, Identifiable, Hashable {
        case left
        case straight
        case right
        case gate4

        var id: String { rawValue }

        var title: String {
            switch self {
            case .left: return "Gate 1"
            case .straight: return "Gate 2"
            case .right: return "Gate 3"
            case .gate4: return "Gate 4"
            }
        }

        var laneTitle: String {
            switch self {
            case .left: return "Left"
            case .straight: return "Straight"
            case .right: return "Right"
            case .gate4: return "Gate 4"
            }
        }

        var color: Color {
            switch self {
            case .left: return .blue
            case .straight: return .green
            case .right: return .purple
            case .gate4: return .orange
            }
        }

        var draftPosition: DraftPosition {
            switch self {
            case .left: return .left
            case .straight: return .straight
            case .right: return .right
            case .gate4: return .farRight
            }
        }
    }

    private enum DraftFallbackOption: String, CaseIterable, Identifiable, Hashable {
        case noDraft
        case left
        case straight
        case right
        case gate4

        var id: String { rawValue }

        var title: String {
            switch self {
            case .noDraft: return "No Draft"
            case .left: return "Gate 1"
            case .straight: return "Gate 2"
            case .right: return "Gate 3"
            case .gate4: return "Gate 4"
            }
        }

        var draftPosition: DraftPosition? {
            switch self {
            case .noDraft: return nil
            case .left: return .left
            case .straight: return .straight
            case .right: return .right
            case .gate4: return .farRight
            }
        }
    }

    private struct WeightDraftRuleRow: Identifiable, Hashable {
        let id = UUID()
        var label: String
        var minKg: String
        var maxKg: String
        var bucket: DraftGateBucket
    }

    private struct MobDraftRuleRow: Identifiable, Hashable {
        let id = UUID()
        var mobName: String
        var bucket: DraftGateBucket
    }

    private struct ClassDraftRuleRow: Identifiable, Hashable {
        let id = UUID()
        var animalClassName: String
        var bucket: DraftGateBucket
    }

    private struct AudioPickerOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    @State private var weightRules: [WeightDraftRuleRow] = []
    @State private var mobRules: [MobDraftRuleRow] = []
    @State private var classRules: [ClassDraftRuleRow] = []

    @State private var mobFallback: DraftFallbackOption = .noDraft
    @State private var classFallback: DraftFallbackOption = .noDraft

    @State private var didSeedMobRules = false
    @State private var didSeedClassRules = false
    @State private var isRestoringDraftSetup = false

    // =====================================================
    // MARK: - Session + derived data
    // =====================================================

    private var activeSessionID: UUID? {
        sessionCoordinator.activeSessionID
    }

    private var activeSession: Session? {
        guard let id = activeSessionID else { return nil }
        return store.sessions.first(where: { $0.id == id })
    }

    private var draftState: DraftTabState {
        vm.draftTabState
    }

    private var dashboardGateSummaries: [DraftDashboardGateSummary] {
        draftState.dashboard.gateSummaries
    }

    private var sessionName: String {
        activeSession?.name ?? "No Active Session"
    }

    private var currentFarmID: UUID? {
        store.sessionFarmID[vm.activeSession.id]
    }

    private var availableMobs: [LocalDataStore.Mob] {
        guard let farmID = currentFarmID else { return [] }
        return store.mobs(for: farmID)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var availableAnimalClasses: [String] {
        let settingsClasses = animalClassStore.classes
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if !settingsClasses.isEmpty {
            return settingsClasses
        }

        return LocalDataStore.AnimalClass.allCases
            .map(\.label)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var orderedGateBuckets: [DraftGateBucket] {
        [.left, .straight, .right, .gate4]
    }

    private var audioOptions: [AudioPickerOption] {
        appSettings.audioClips.map {
            AudioPickerOption(id: $0.id.uuidString, title: $0.name)
        }
    }

    var body: some View {
        ZStack {
            GlassBackground()

            Group {
                if isPhoneCompact {
                    phoneLayout
                } else {
                    padLayout
                }
            }
        }
        .overlay(alignment: .top) {
            if Device.isPhone {
                topSafeAreaGlass
            }
        }
        .onAppear {
            restoreDraftSetupFromStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: activeSessionID) { _, _ in
            restoreDraftSetupFromStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: currentFarmID) { _, _ in
            seedMobRulesIfNeeded(force: true)
            seedClassRulesIfNeeded(force: true)
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: animalClassStore.classes) { _, _ in
            seedClassRulesIfNeeded(force: true)
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: draftState.setup.selectedMode) { _, newMode in
            guard let newMode else {
                saveDraftSetupToStore()
                applyDraftRulesToEngine()
                return
            }

            seedRulesForModeIfNeeded(newMode)
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: weightRules) { _, _ in
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: mobRules) { _, _ in
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: classRules) { _, _ in
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: mobFallback) { _, _ in
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: classFallback) { _, _ in
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        }
        .onChange(of: draftSettings.gateMap) { _, newMap in
            vm.draftEngine?.gateMap = newMap
            applyDraftRulesToEngine()
        }
        .onChange(of: draftSettings.autoReleaseMode) { _, _ in
            applyDraftRulesToEngine()
        }
    }

    // =====================================================
    // MARK: - Top safe-area glass fill
    // =====================================================

    private var topSafeAreaGlass: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top

            if top > 0 {
                Rectangle()
                    .fill(.thinMaterial)
                    .frame(height: top)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 1),
                        alignment: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
            }
        }
        .allowsHitTesting(false)
    }

    // =====================================================
    // MARK: - Layouts
    // =====================================================

    private var phoneLayout: some View {
        ScrollView {
            VStack(spacing: 14) {
                sessionCard

                if activeSessionID == nil {
                    noSessionCard
                } else {
                    setupStatusCard
                    overviewCard
                    gateSummaryStack
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
    }

    private var padLayout: some View {
        ScrollView {
            VStack(spacing: 18) {
                sessionCard

                if activeSessionID == nil {
                    noSessionCard
                } else {
                    setupStatusCard
                    overviewCard
                    gateSummaryGrid
                }
            }
            .padding()
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
            .safeAreaPadding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // =====================================================
    // MARK: - Main cards
    // =====================================================

    private var sessionCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Draft Dashboard")
                        .font(.title3.weight(.bold))

                    Text(sessionName)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if activeSessionID != nil {
                        Text("Live drafting summary from actual session results.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Start or resume a session to see live draft totals.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 12)

                if activeSessionID != nil {
                    VStack(alignment: .trailing, spacing: 8) {
                        statePill(
                            text: draftState.setup.isActive ? "Active" : "Inactive",
                            color: draftState.setup.isActive ? .green : .secondary
                        )

                        statePill(
                            text: sessionCoordinator.locked ? "Locked" : "Live",
                            color: sessionCoordinator.locked ? .blue : .secondary
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(maxWidth: .infinity)
    }

    private var noSessionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("No Active Session")
                    .font(.headline)

                Text("Go to the Session tab and start or resume a draft-enabled session.")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var setupStatusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Draft Mode")
                        .font(.subheadline.weight(.semibold))

                    modePickerGrid
                }

                Divider().opacity(0.22)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Auto Release")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Toggle("", isOn: autoReleaseEnabledBinding)
                            .labelsHidden()
                    }

                    Text(autoReleaseStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let selectedMode = draftState.setup.selectedMode {
                    Divider().opacity(0.22)
                    modeSetupCard(selectedMode)
                }

                if !draftState.advanced.ruleSummary.isEmpty {
                    Divider().opacity(0.22)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Rule Preview")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(draftState.advanced.ruleSummary.prefix(6).enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.secondary.opacity(0.7))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)

                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if !draftState.setup.isConfigured {
                    Divider().opacity(0.22)

                    Text("Start a draft-enabled session to use live draft controls and summaries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private var overviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Overview")
                    .font(.headline)

                Divider().opacity(0.35)

                statRow("Total drafted", "\(draftState.dashboard.totalDrafted)")
                statRow("Current EID", sessionCoordinator.eid == "—" ? "—" : sessionCoordinator.eid)
                statRow("Average weight", overallAverageText)
                statRow("Min / Max", overallMinMaxText)
                statRow("Current weight", sessionCoordinator.eid == "—" ? "—" : "\(fmt1(sessionCoordinator.weight)) kg")
            }
            .padding(14)
        }
    }

    private var gateSummaryStack: some View {
        VStack(spacing: 12) {
            ForEach(Array(dashboardGateSummaries.enumerated()), id: \.element.id) { index, summary in
                gateSummaryCard(
                    summary: summary,
                    title: gateTitle(for: index),
                    subtitle: gateSubtitle(for: index),
                    color: gateColor(for: index)
                )
            }
        }
    }

    private var gateSummaryGrid: some View {
        let cols = [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]

        return LazyVGrid(columns: cols, spacing: 14) {
            ForEach(Array(dashboardGateSummaries.enumerated()), id: \.element.id) { index, summary in
                gateSummaryCard(
                    summary: summary,
                    title: gateTitle(for: index),
                    subtitle: gateSubtitle(for: index),
                    color: gateColor(for: index)
                )
            }
        }
    }

    private func gateSummaryCard(
        summary: DraftDashboardGateSummary,
        title: String,
        subtitle: String,
        color: Color
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                }

                Divider().opacity(0.25)

                HStack {
                    Text("Count")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(summary.count)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }

                HStack {
                    Text("Avg")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(summary.averageWeightKg.map { "\(fmt1($0)) kg" } ?? "—")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                HStack {
                    Text("Min / Max")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(gateMinMaxText(summary))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .padding(14)
        }
    }

    // =====================================================
    // MARK: - Setup UI
    // =====================================================

    private var modePickerGrid: some View {
        let columns = isPhoneCompact
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DraftModeType.allCases, id: \.self) { mode in
                modeButton(mode)
            }
        }
    }

    private func modeButton(_ mode: DraftModeType) -> some View {
        let isSelected = draftState.setup.selectedMode == mode

        return Button {
            vm.selectDraftMode(mode)
            seedRulesForModeIfNeeded(mode)
            saveDraftSetupToStore()
            applyDraftRulesToEngine()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: mode))
                    .font(.system(size: 13, weight: .semibold))

                Text(mode.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color(.secondarySystemBackground)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                        ? Color.accentColor.opacity(0.75)
                        : Color.black.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.12) : .clear,
                radius: 6, y: 2
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modeSetupCard(_ mode: DraftModeType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(mode.rawValue) Setup")
                .font(.subheadline.weight(.semibold))

            Text(modeDescription(for: mode))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch mode {
            case .weight:
                weightSetupEditor
            case .mob:
                mobSetupEditor
            case .animalClass:
                classSetupEditor
            case .pregHistory:
                pregHistorySetupEditor
            case .file:
                fileSetupEditor
            }
        }
    }

    // =====================================================
    // MARK: - Weight setup
    // =====================================================

    private var weightSetupEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign weight bands into the 4 gate columns.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isPhoneCompact {
                VStack(spacing: 10) {
                    ForEach(orderedGateBuckets) { bucket in
                        weightBucketCard(bucket)
                    }
                }
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(orderedGateBuckets) { bucket in
                        weightBucketCard(bucket)
                    }
                }
            }
        }
    }

    private func weightBucketCard(_ bucket: DraftGateBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bucket.color)
                    .frame(width: 10, height: 10)

                Text(bucket.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(weightRules(in: bucket).count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(bucket.color.opacity(0.18))
                    )
            }

            Divider().opacity(0.22)

            if weightRules(in: bucket).isEmpty {
                Text("No bands assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(weightRules(in: bucket)) { rule in
                        weightBandEditor(rule)
                    }
                }
            }

            Divider().opacity(0.22)

            gateAudioPicker(bucket)

            Button {
                weightRules.append(
                    .init(label: "New Band", minKg: "", maxKg: "", bucket: bucket)
                )
            } label: {
                Label("Add Band", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bucket.color.opacity(0.28), lineWidth: 1)
        )
    }

    private func weightBandEditor(_ rule: WeightDraftRuleRow) -> some View {
        let binding = bindingForWeightRule(rule.id)

        return VStack(alignment: .leading, spacing: 8) {
            TextField("Label", text: binding.label)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            HStack(spacing: 8) {
                TextField("Min kg", text: binding.minKg)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                TextField("Max kg", text: binding.maxKg)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            HStack {
                Text(weightRuleSummary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    ForEach(orderedGateBuckets) { bucket in
                        if bucket != rule.bucket {
                            Button("Move to \(bucket.title)") {
                                moveWeightRule(rule.id, to: bucket)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        removeWeightRule(rule.id)
                    } label: {
                        Text("Remove")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rule.bucket.color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rule.bucket.color.opacity(0.22), lineWidth: 1)
        )
    }

    // =====================================================
    // MARK: - Mob setup
    // =====================================================

    private var mobSetupEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableMobs.isEmpty {
                Text("No mobs found for the current farm yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Assign mobs into gate columns. Any mob not listed uses the fallback below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isPhoneCompact {
                VStack(spacing: 10) {
                    ForEach(orderedGateBuckets) { bucket in
                        mobBucketCard(bucket)
                    }
                }
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(orderedGateBuckets) { bucket in
                        mobBucketCard(bucket)
                    }
                }
            }

            fallbackPickerCard(
                title: "Other Mobs",
                selection: $mobFallback,
                helpText: mobFallbackHelpText
            )
        }
    }

    private func mobBucketCard(_ bucket: DraftGateBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bucket.color)
                    .frame(width: 10, height: 10)

                Text(bucket.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(mobs(in: bucket).count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(bucket.color.opacity(0.18))
                    )
            }

            Divider().opacity(0.22)

            if mobs(in: bucket).isEmpty {
                Text("No mobs assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(mobs(in: bucket)) { rule in
                        mobChip(rule: rule)
                    }
                }
            }

            Divider().opacity(0.22)

            gateAudioPicker(bucket)

            Menu {
                ForEach(unassignedMobNames, id: \.self) { mobName in
                    Button(mobName) {
                        addMobNamed(mobName, to: bucket)
                    }
                }
            } label: {
                Label("Add Mob", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(unassignedMobNames.isEmpty)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bucket.color.opacity(0.28), lineWidth: 1)
        )
    }

    private func mobChip(rule: MobDraftRuleRow) -> some View {
        HStack(spacing: 8) {
            Text(rule.mobName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Menu {
                ForEach(orderedGateBuckets) { bucket in
                    if bucket != rule.bucket {
                        Button("Move to \(bucket.title)") {
                            moveMob(rule.id, to: bucket)
                        }
                    }
                }

                Button(role: .destructive) {
                    removeMobRule(rule.id)
                } label: {
                    Text("Remove")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rule.bucket.color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rule.bucket.color.opacity(0.22), lineWidth: 1)
        )
    }

    // =====================================================
    // MARK: - Class setup
    // =====================================================

    private var classSetupEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign classes into gate columns. Any class not listed uses the fallback below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isPhoneCompact {
                VStack(spacing: 10) {
                    ForEach(orderedGateBuckets) { bucket in
                        classBucketCard(bucket)
                    }
                }
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(orderedGateBuckets) { bucket in
                        classBucketCard(bucket)
                    }
                }
            }

            fallbackPickerCard(
                title: "Other Classes",
                selection: $classFallback,
                helpText: classFallbackHelpText
            )
        }
    }

    private func classBucketCard(_ bucket: DraftGateBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bucket.color)
                    .frame(width: 10, height: 10)

                Text(bucket.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(classes(in: bucket).count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(bucket.color.opacity(0.18))
                    )
            }

            Divider().opacity(0.22)

            if classes(in: bucket).isEmpty {
                Text("No classes assigned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(classes(in: bucket)) { rule in
                        classChip(rule: rule)
                    }
                }
            }

            Divider().opacity(0.22)

            gateAudioPicker(bucket)

            Menu {
                ForEach(unassignedAnimalClasses, id: \.self) { animalClassName in
                    Button(animalClassName) {
                        addAnimalClass(named: animalClassName, to: bucket)
                    }
                }
            } label: {
                Label("Add Class", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(unassignedAnimalClasses.isEmpty)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(bucket.color.opacity(0.28), lineWidth: 1)
        )
    }

    private func classChip(rule: ClassDraftRuleRow) -> some View {
        HStack(spacing: 8) {
            Text(rule.animalClassName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Menu {
                ForEach(orderedGateBuckets) { bucket in
                    if bucket != rule.bucket {
                        Button("Move to \(bucket.title)") {
                            moveClass(rule.id, to: bucket)
                        }
                    }
                }

                Button(role: .destructive) {
                    removeClassRule(rule.id)
                } label: {
                    Text("Remove")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rule.bucket.color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rule.bucket.color.opacity(0.22), lineWidth: 1)
        )
    }

    private func fallbackPickerCard(
        title: String,
        selection: Binding<DraftFallbackOption>,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Picker(title, selection: selection) {
                ForEach(DraftFallbackOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mobFallbackHelpText: String {
        switch mobFallback {
        case .noDraft:
            return "Any mob not listed above will not be explicitly drafted by mob rules."
        case .left, .straight, .right, .gate4:
            return "Any mob not listed above will draft to \(mobFallback.title)."
        }
    }

    private var classFallbackHelpText: String {
        switch classFallback {
        case .noDraft:
            return "Any class not listed above will not be explicitly drafted by class rules."
        case .left, .straight, .right, .gate4:
            return "Any class not listed above will draft to \(classFallback.title)."
        }
    }

    // =====================================================
    // MARK: - Gate audio picker
    // =====================================================

    private func gateAudioPicker(_ bucket: DraftGateBucket) -> some View {
        let selectedID = audioBinding(for: bucket).wrappedValue
        let selectedName = audioOptions.first(where: { $0.id == selectedID })?.title ?? "None"

        return VStack(alignment: .leading, spacing: 8) {
            Text("Gate Audio")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                Button("None") {
                    audioBinding(for: bucket).wrappedValue = ""
                }

                if !audioOptions.isEmpty {
                    Divider()

                    ForEach(audioOptions) { option in
                        Button {
                            audioBinding(for: bucket).wrappedValue = option.id
                        } label: {
                            if option.id == selectedID {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedName)
                        .foregroundStyle(selectedID.isEmpty ? .secondary : .primary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Text(audioSummaryText(for: bucket))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func audioBinding(for bucket: DraftGateBucket) -> Binding<String> {
        switch bucket {
        case .left:
            return $leftGateAudioID
        case .straight:
            return $straightGateAudioID
        case .right:
            return $rightGateAudioID
        case .gate4:
            return $gate4AudioID
        }
    }

    private func audioSummaryText(for bucket: DraftGateBucket) -> String {
        let selectedID = audioBinding(for: bucket).wrappedValue
        guard !selectedID.isEmpty else { return "No audio selected for this gate." }

        let name = audioOptions.first(where: { $0.id == selectedID })?.title ?? "Unknown clip"
        return "Selected: \(name)"
    }

    // =====================================================
    // MARK: - Other setup cards
    // =====================================================

    private var pregHistorySetupEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            pregOutcomeRow(title: "Empty", logical: .empty)
            pregOutcomeRow(title: "Single", logical: .single)
            pregOutcomeRow(title: "Twin", logical: .twin)

            Text("These outcomes use the current gate mapping below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pregOutcomeRow(title: String, logical: DraftLogicalTarget) -> some View {
        let physical = draftSettings.gateMap.physical(for: logical)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("→ \(physical.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                drafter.draftAnimal(logical: logical, using: draftSettings.gateMap)
            } label: {
                Label("Test", systemImage: "bolt.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var fileSetupEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File-based drafting UI can sit here when file import or lookup is connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)

                Text("No file selected")
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Choose File") { }
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // =====================================================
    // MARK: - Rule application
    // =====================================================

    private func applyDraftRulesToEngine() {
        guard let engine = vm.draftEngine else { return }

        engine.gateMap = draftSettings.gateMap
        engine.defaultLogicalTarget = nil
        engine.defaultPosition = .straight

        guard let mode = draftState.setup.selectedMode else {
            engine.replaceAllRules([])
            return
        }

        switch mode {
        case .weight:
            let rules: [DraftRule] = weightRules.compactMap { row in
                let label = row.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let minValue = Double(row.minKg.trimmingCharacters(in: .whitespacesAndNewlines))
                let maxValue = Double(row.maxKg.trimmingCharacters(in: .whitespacesAndNewlines))

                guard !label.isEmpty || minValue != nil || maxValue != nil else { return nil }

                return DraftRule(
                    name: label.isEmpty ? weightRuleSummary(row) : label,
                    minWeight: minValue,
                    maxWeight: maxValue,
                    result: row.bucket.draftPosition,
                    logicalTarget: nil
                )
            }
            engine.replaceAllRules(rules)

        case .mob:
            let rules: [DraftRule] = mobRules.compactMap { row in
                let mobName = row.mobName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !mobName.isEmpty else { return nil }
                guard let mob = availableMobs.first(where: { $0.name == mobName }) else { return nil }

                return DraftRule(
                    name: mob.name,
                    mobID: mob.id,
                    result: row.bucket.draftPosition,
                    logicalTarget: nil
                )
            }
            engine.replaceAllRules(rules)
            if let fallback = mobFallback.draftPosition {
                engine.defaultPosition = fallback
            }

        case .animalClass:
            let rules: [DraftRule] = classRules.map { row in
                DraftRule(
                    name: row.animalClassName,
                    klassEquals: row.animalClassName,
                    result: row.bucket.draftPosition,
                    logicalTarget: nil
                )
            }
            engine.replaceAllRules(rules)
            if let fallback = classFallback.draftPosition {
                engine.defaultPosition = fallback
            }

        case .pregHistory:
            let rules: [DraftRule] = [
                DraftRule(
                    name: "Empty",
                    result: draftSettings.gateMap.physical(for: .empty),
                    logicalTarget: .empty
                ),
                DraftRule(
                    name: "Single",
                    result: draftSettings.gateMap.physical(for: .single),
                    logicalTarget: .single
                ),
                DraftRule(
                    name: "Twin",
                    result: draftSettings.gateMap.physical(for: .twin),
                    logicalTarget: .twin
                )
            ]
            engine.replaceAllRules(rules)

        case .file:
            engine.replaceAllRules([])
        }
    }

    // =====================================================
    // MARK: - Persistence helpers
    // =====================================================

    private func restoreDraftSetupFromStore() {
        guard let sessionID = activeSessionID else {
            isRestoringDraftSetup = true
            weightRules = []
            mobRules = []
            classRules = []
            mobFallback = .noDraft
            classFallback = .noDraft
            didSeedMobRules = false
            didSeedClassRules = false
            isRestoringDraftSetup = false
            return
        }

        isRestoringDraftSetup = true
        defer { isRestoringDraftSetup = false }

        let setup = store.draftSetup(for: sessionID)

        weightRules = setup.weightRules.map {
            WeightDraftRuleRow(
                label: $0.name,
                minKg: $0.minWeight.map { trimNumber($0) } ?? "",
                maxKg: $0.maxWeight.map { trimNumber($0) } ?? "",
                bucket: gateBucket(from: $0.draftPositionRaw) ?? .straight
            )
        }

        mobRules = setup.mobRules.map {
            MobDraftRuleRow(
                mobName: $0.mobName,
                bucket: gateBucket(from: $0.draftPositionRaw) ?? .straight
            )
        }

        classRules = setup.classRules.map {
            ClassDraftRuleRow(
                animalClassName: $0.animalClassRaw,
                bucket: gateBucket(from: $0.draftPositionRaw) ?? .straight
            )
        }

        mobFallback = fallbackOption(from: setup.fallback)
        classFallback = fallbackOption(from: setup.fallback)

        didSeedMobRules = !mobRules.isEmpty
        didSeedClassRules = !classRules.isEmpty

        if let mode = draftModeType(from: setup.mode) {
            vm.selectDraftMode(mode)
            seedRulesForModeIfNeeded(mode)
        } else if weightRules.isEmpty {
            weightRules = defaultWeightRules
        }
    }

    private func saveDraftSetupToStore() {
        guard !isRestoringDraftSetup else { return }
        guard let sessionID = activeSessionID else { return }

        let setup = SessionDraftSetup(
            mode: sessionDraftSetupMode(from: draftState.setup.selectedMode),
            weightRules: weightRules.map {
                SessionWeightDraftRule(
                    id: $0.id,
                    name: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                    minWeight: Double($0.minKg.trimmingCharacters(in: .whitespacesAndNewlines)),
                    maxWeight: Double($0.maxKg.trimmingCharacters(in: .whitespacesAndNewlines)),
                    draftPositionRaw: $0.bucket.rawValue
                )
            },
            mobRules: mobRules.map { row in
                let matchedMob = availableMobs.first {
                    $0.name.localizedCaseInsensitiveCompare(row.mobName) == .orderedSame
                }

                return SessionMobDraftRule(
                    id: row.id,
                    mobID: matchedMob?.id ?? UUID(),
                    mobName: row.mobName,
                    draftPositionRaw: row.bucket.rawValue
                )
            },
            classRules: classRules.map {
                SessionClassDraftRule(
                    id: $0.id,
                    animalClassRaw: $0.animalClassName,
                    draftPositionRaw: $0.bucket.rawValue
                )
            },
            fallback: draftFallbackChoiceForCurrentMode(),
            isEnabled: draftState.setup.selectedMode != nil
        )

        store.setDraftSetup(setup, for: sessionID)
    }

    private func sessionDraftSetupMode(from mode: DraftModeType?) -> DraftSetupMode {
        switch mode {
        case .weight:
            return .byWeight
        case .mob:
            return .byMob
        case .animalClass:
            return .byClass
        case .pregHistory, .file, nil:
            return .off
        }
    }

    private func draftModeType(from mode: DraftSetupMode) -> DraftModeType? {
        switch mode {
        case .off:
            return nil
        case .byWeight:
            return .weight
        case .byMob:
            return .mob
        case .byClass:
            return .animalClass
        }
    }

    private func draftFallbackChoiceForCurrentMode() -> DraftFallbackChoice {
        switch draftState.setup.selectedMode {
        case .mob:
            return draftFallbackChoice(from: mobFallback)
        case .animalClass:
            return draftFallbackChoice(from: classFallback)
        default:
            return .keepCurrent
        }
    }

    private func draftFallbackChoice(from option: DraftFallbackOption) -> DraftFallbackChoice {
        switch option {
        case .noDraft:
            return .keepCurrent
        case .left:
            return .left
        case .straight, .right, .gate4:
            return .right
        }
    }

    private func fallbackOption(from choice: DraftFallbackChoice) -> DraftFallbackOption {
        switch choice {
        case .keepCurrent:
            return .noDraft
        case .left:
            return .left
        case .right:
            return .right
        }
    }

    private func gateBucket(from rawValue: String) -> DraftGateBucket? {
        if rawValue == "hold" { return .gate4 }
        return DraftGateBucket(rawValue: rawValue)
    }

    private func trimNumber(_ value: Double) -> String {
        let s = String(format: "%.3f", value)
        var out = s
        while out.contains(".") && (out.hasSuffix("0") || out.hasSuffix(".")) {
            out.removeLast()
        }
        return out
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func seedMobRulesIfNeeded(force: Bool = false) {
        guard force || !didSeedMobRules else { return }
        didSeedMobRules = true

        guard !availableMobs.isEmpty else { return }

        let existingByName = Dictionary(uniqueKeysWithValues: mobRules.map { ($0.mobName, $0) })

        mobRules = availableMobs.compactMap { mob in
            existingByName[mob.name]
        }
    }

    private func seedClassRulesIfNeeded(force: Bool = false) {
        guard force || !didSeedClassRules else { return }
        didSeedClassRules = true

        let validNames = Set(availableAnimalClasses)
        classRules = classRules.filter { validNames.contains($0.animalClassName) }

        let existingByClass = Dictionary(uniqueKeysWithValues: classRules.map { ($0.animalClassName, $0) })
        classRules = availableAnimalClasses.compactMap { existingByClass[$0] }
    }

    private func seedRulesForModeIfNeeded(_ mode: DraftModeType) {
        switch mode {
        case .mob:
            if mobRules.isEmpty {
                seedMobRulesIfNeeded(force: true)
            }

        case .animalClass:
            if classRules.isEmpty {
                seedClassRulesIfNeeded(force: true)
            }

        case .weight:
            if weightRules.isEmpty {
                weightRules = defaultWeightRules
            }

        case .pregHistory, .file:
            break
        }
    }

    private var defaultWeightRules: [WeightDraftRuleRow] {
        [
            .init(label: "Light", minKg: "", maxKg: "45", bucket: .left),
            .init(label: "Medium", minKg: "45", maxKg: "60", bucket: .straight),
            .init(label: "Heavy", minKg: "60", maxKg: "", bucket: .right)
        ]
    }

    private func bindingForWeightRule(_ id: UUID) -> (
        label: Binding<String>,
        minKg: Binding<String>,
        maxKg: Binding<String>
    ) {
        (
            label: Binding(
                get: { weightRules.first(where: { $0.id == id })?.label ?? "" },
                set: { newValue in
                    guard let index = weightRules.firstIndex(where: { $0.id == id }) else { return }
                    weightRules[index].label = newValue
                }
            ),
            minKg: Binding(
                get: { weightRules.first(where: { $0.id == id })?.minKg ?? "" },
                set: { newValue in
                    guard let index = weightRules.firstIndex(where: { $0.id == id }) else { return }
                    weightRules[index].minKg = newValue
                }
            ),
            maxKg: Binding(
                get: { weightRules.first(where: { $0.id == id })?.maxKg ?? "" },
                set: { newValue in
                    guard let index = weightRules.firstIndex(where: { $0.id == id }) else { return }
                    weightRules[index].maxKg = newValue
                }
            )
        )
    }

    private func removeWeightRule(_ id: UUID) {
        weightRules.removeAll { $0.id == id }
    }

    private func moveWeightRule(_ id: UUID, to bucket: DraftGateBucket) {
        guard let index = weightRules.firstIndex(where: { $0.id == id }) else { return }
        weightRules[index].bucket = bucket
    }

    private func weightRules(in bucket: DraftGateBucket) -> [WeightDraftRuleRow] {
        weightRules.filter { $0.bucket == bucket }
    }

    private func removeMobRule(_ id: UUID) {
        mobRules.removeAll { $0.id == id }
    }

    private func mobs(in bucket: DraftGateBucket) -> [MobDraftRuleRow] {
        mobRules
            .filter { $0.bucket == bucket }
            .sorted { $0.mobName.localizedCaseInsensitiveCompare($1.mobName) == .orderedAscending }
    }

    private func moveMob(_ id: UUID, to bucket: DraftGateBucket) {
        guard let index = mobRules.firstIndex(where: { $0.id == id }) else { return }
        mobRules[index].bucket = bucket
    }

    private func addMobNamed(_ mobName: String, to bucket: DraftGateBucket) {
        if let index = mobRules.firstIndex(where: { $0.mobName == mobName }) {
            mobRules[index].bucket = bucket
        } else {
            mobRules.append(.init(mobName: mobName, bucket: bucket))
        }
    }

    private var unassignedMobNames: [String] {
        let assigned = Set(mobRules.map(\.mobName))
        return availableMobs
            .map(\.name)
            .filter { !assigned.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func removeClassRule(_ id: UUID) {
        classRules.removeAll { $0.id == id }
    }

    private func classes(in bucket: DraftGateBucket) -> [ClassDraftRuleRow] {
        classRules
            .filter { $0.bucket == bucket }
            .sorted { $0.animalClassName.localizedCaseInsensitiveCompare($1.animalClassName) == .orderedAscending }
    }

    private func moveClass(_ id: UUID, to bucket: DraftGateBucket) {
        guard let index = classRules.firstIndex(where: { $0.id == id }) else { return }
        classRules[index].bucket = bucket
    }

    private func addAnimalClass(named animalClassName: String, to bucket: DraftGateBucket) {
        if let index = classRules.firstIndex(where: { $0.animalClassName == animalClassName }) {
            classRules[index].bucket = bucket
        } else {
            classRules.append(.init(animalClassName: animalClassName, bucket: bucket))
        }
    }

    private var unassignedAnimalClasses: [String] {
        let assigned = Set(classRules.map(\.animalClassName))
        return availableAnimalClasses.filter { !assigned.contains($0) }
    }

    private func weightRuleSummary(_ rule: WeightDraftRuleRow) -> String {
        let minText = rule.minKg.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxText = rule.maxKg.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (minText.isEmpty, maxText.isEmpty) {
        case (true, true):
            return "Any weight → \(rule.bucket.title)"
        case (true, false):
            return "Up to \(maxText) kg → \(rule.bucket.title)"
        case (false, true):
            return "\(minText) kg and above → \(rule.bucket.title)"
        case (false, false):
            return "\(minText)–\(maxText) kg → \(rule.bucket.title)"
        }
    }

    private var allDashboardWeightsAverage: Double? {
        let weighted: [(count: Int, avg: Double)] = dashboardGateSummaries.compactMap { summary in
            guard let avg = summary.averageWeightKg, summary.count > 0 else { return nil }
            return (summary.count, avg)
        }

        let totalCount = weighted.reduce(0) { $0 + $1.count }
        guard totalCount > 0 else { return nil }

        let totalWeight = weighted.reduce(0.0) { $0 + (Double($1.count) * $1.avg) }
        return totalWeight / Double(totalCount)
    }

    private var overallAverageText: String {
        guard let avg = allDashboardWeightsAverage else { return "—" }
        return "\(fmt1(avg)) kg"
    }

    private var overallMinMaxText: String {
        let mins = dashboardGateSummaries.compactMap(\.minWeightKg)
        let maxs = dashboardGateSummaries.compactMap(\.maxWeightKg)

        guard let minW = mins.min(), let maxW = maxs.max() else { return "—" }
        return "\(fmt1(minW)) / \(fmt1(maxW)) kg"
    }

    private func gateMinMaxText(_ summary: DraftDashboardGateSummary) -> String {
        guard let minW = summary.minWeightKg, let maxW = summary.maxWeightKg else { return "—" }
        return "\(fmt1(minW)) / \(fmt1(maxW)) kg"
    }

    private func gateTitle(for index: Int) -> String {
        "Gate \(index + 1)"
    }

    private func gateSubtitle(for index: Int) -> String {
        switch index {
        case 0: return "Left"
        case 1: return "Straight"
        case 2: return "Right"
        case 3: return "Gate 4"
        default: return "Gate"
        }
    }

    private func gateColor(for index: Int) -> Color {
        switch index {
        case 0: return .blue
        case 1: return .green
        case 2: return .purple
        case 3: return .orange
        default: return .secondary
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 14))
    }

    private func fmt1(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func statePill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.20))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            )
    }

    private func icon(for mode: DraftModeType) -> String {
        switch mode {
        case .weight: return "scalemass"
        case .mob: return "square.grid.2x2"
        case .animalClass: return "tag"
        case .file: return "doc.text"
        case .pregHistory: return "waveform.path.ecg"
        }
    }

    private func modeDescription(for mode: DraftModeType) -> String {
        switch mode {
        case .weight:
            return "Assign weight bands into Gate 1, Gate 2, Gate 3 and Gate 4 columns."
        case .mob:
            return "Assign mobs into Gate 1, Gate 2, Gate 3 and Gate 4 columns, with a fallback for other mobs."
        case .animalClass:
            return "Assign classes into Gate 1, Gate 2, Gate 3 and Gate 4 columns, with a fallback for other classes."
        case .file:
            return "Use this for future imported rule files."
        case .pregHistory:
            return "Preg outcomes use Empty, Single and Twin gate mapping."
        }
    }
}
