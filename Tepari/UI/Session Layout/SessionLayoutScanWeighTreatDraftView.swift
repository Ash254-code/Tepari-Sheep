import SwiftUI

struct SessionLayoutScanWeighTreatDraftView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var tepariGun: TepariGunManager
    @EnvironmentObject private var drafter: DrafterController
    @EnvironmentObject private var draftRuleEngine: DraftRuleEngine

    @ObservedObject var vm: SessionViewModel

    let activeTypes: Set<SetupSessionType>

    @Binding var showWeighMode: Bool
    @Binding var showZeroConfirmation: Bool
    @Binding var showDetails: Bool

    let isPhone: Bool
    let isTCPConnected: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void
    let onOpenTreatments: () -> Void
    let onGoToDraftTab: () -> Void

    @State private var lastAutoSentSignature: String? = nil
    @State private var flashingPosition: DraftPosition? = nil

    private var reservedBottomHeight: CGFloat {
        isPhone ? 152 : 0
    }

    private var recordsNewestFirst: [AnimalRecord] {
        Array(store.records(for: vm.activeSession.id).reversed())
    }

    private var leftSummary: SessionViewModel.DraftGateSummary {
        vm.draftLeftSummary
    }

    private var straightSummary: SessionViewModel.DraftGateSummary {
        vm.draftStraightSummary
    }

    private var rightSummary: SessionViewModel.DraftGateSummary {
        vm.draftRightSummary
    }

    private var farRightSummary: SessionViewModel.DraftGateSummary {
        vm.draftFarRightSummary
    }

    private var currentDisplayedRecord: AnimalRecord? {
        let eid = vm.currentEID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eid.isEmpty, eid != "—" else { return nil }
        return recordsNewestFirst.first { $0.eidRaw == eid }
    }

    private var resolvedDraftPositionForCurrentAnimal: DraftPosition? {
        currentDisplayedRecord?.draftResult
    }

    private var selectedTreatmentName: String {
        vm.selectedSessionTreatment?.product ?? "—"
    }

    private var treatmentDoseText: String {
        vm.calculatedDoseText ?? "—"
    }

    private var treatmentDoseBasisText: String {
        guard let treatment = vm.selectedSessionTreatment else { return "No treatment selected" }
        let base = treatment.displayDoseString.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Dose rule unavailable" : base
    }

    private var treatmentStatusText: String {
        if vm.sessionTreatments.isEmpty {
            return "No treatments configured for this session."
        }
        if vm.currentEID == "—" {
            return "Scan an animal to prepare treatment dose."
        }
        if vm.hasDoseReadyWeight || vm.isLocked {
            return vm.calculatedDoseText != nil
                ? "Calculated from locked weight."
                : "Dose unavailable for selected treatment."
        }
        return "Dose appears once weight locks."
    }

    private var canSendDoseToGun: Bool {
        tepariGun.isEnabled &&
        vm.selectedSessionTreatment != nil &&
        vm.calculatedDoseText != nil &&
        (vm.isLocked || vm.hasDoseReadyWeight)
    }

    private var currentDoseReadyWeight: Double? {
        guard vm.isLocked || vm.hasDoseReadyWeight else { return nil }
        return vm.currentWeight
    }

    private var currentAutoSendSignature: String? {
        guard tepariGun.isEnabled else { return nil }

        let eid = vm.currentEID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eid.isEmpty, eid != "—" else { return nil }

        guard let treatment = vm.selectedSessionTreatment else { return nil }
        guard let doseText = vm.calculatedDoseText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !doseText.isEmpty,
              doseText != "—" else { return nil }
        guard let weight = currentDoseReadyWeight else { return nil }

        let weightText = String(format: "%.2f", weight)
        return "\(eid)|\(treatment.id.uuidString)|\(doseText)|\(weightText)"
    }

    private var gunStatusText: String {
        if tepariGun.isSending {
            return "Sending dose to gun…"
        }

        if let err = tepariGun.lastErrorText, !err.isEmpty {
            return err
        }

        if let response = tepariGun.lastResponseText, !response.isEmpty {
            return response
        }

        if tepariGun.isVisible {
            return "Gun visible on network."
        }

        switch tepariGun.state {
        case .connected:
            return "Gun connected."
        case .connecting:
            return "Connecting to gun…"
        case .disconnected:
            return "Gun disconnected."
        case .error:
            return "Gun error."
        }
    }

    private var gunDotColor: Color {
        if tepariGun.isVisible || tepariGun.state == .connected {
            return .green
        }

        switch tepariGun.state {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private var gunStatusColor: Color {
        if tepariGun.isSending {
            return .orange
        }

        if tepariGun.isVisible || tepariGun.state == .connected {
            return .secondary
        }

        switch tepariGun.state {
        case .connected: return .secondary
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            SessionThreeTileTemplateView(
                horizontalPadding: 16,
                topPadding: 12,
                bottomPadding: isPhone ? 8 : 18,
                reservedBottomHeight: reservedBottomHeight,
                verticalSpacing: 14,
                horizontalSpacing: 14,
                topTileHeightRatio: isPhone ? 0.42 : 0.43
            ) {
                weightPanel
            } bottomLeadingContent: {
                draftPanel
            } bottomTrailingContent: {
                treatmentPanel
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionLayoutScanWeighTreatDraftHeaderHUD(
                eid: vm.currentEID,
                sessionName: vm.activeSession.name,
                scannedCount: scannedCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.thinMaterial)
            .overlay(Divider().opacity(0.20), alignment: .bottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPhone {
                bottomActions
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(.thinMaterial)
                    .overlay(Divider().opacity(0.25), alignment: .top)
            }
        }
        .fullScreenCover(isPresented: $showDetails) {
            NavigationStack {
                SessionLayoutScanWeighTreatDraftFullRecordListView(
                    sessionName: vm.activeSession.name,
                    recordsNewestFirst: recordsNewestFirst
                )
                .navigationTitle("Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDetails = false }
                    }
                }
            }
        }
        .onAppear {
            vm.reloadSessionTreatments()
            onSyncCoordinator()
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.currentEID) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.selectedSessionTreatmentID) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.calculatedDoseText) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.currentWeight) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.isLocked) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: vm.hasDoseReadyWeight) { _, _ in
            autoSendDoseIfNeeded()
        }
        .onChange(of: resolvedDraftPositionForCurrentAnimal) { _, newValue in
            guard let pos = newValue else { return }

            flashingPosition = pos

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if flashingPosition == pos {
                    flashingPosition = nil
                }
            }
        }
    }

    private var weightPanel: some View {
        SessionLayoutScanWeighTreatDraftPanel(
            title: "Weight",
            systemImage: "scalemass.fill"
        ) {
            SessionCenteredWeightBoard(
                weight: vm.currentWeight,
                locked: vm.isLocked,
                stable: vm.isStable,
                onWeighMode: { showWeighMode = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showWeighMode = true
        }
    }

    private var draftPanel: some View {
        SessionLayoutScanWeighTreatDraftPanel(
            title: "Drafting",
            systemImage: "arrow.triangle.branch"
        ) {
            HStack(spacing: 8) {
                draftCountTile(
                    title: gateLabel(for: .left),
                    subtitle: positionLabelShort(.left),
                    summary: leftSummary,
                    color: .blue,
                    position: .left
                )

                draftCountTile(
                    title: gateLabel(for: .straight),
                    subtitle: positionLabelShort(.straight),
                    summary: straightSummary,
                    color: .green,
                    position: .straight
                )

                draftCountTile(
                    title: gateLabel(for: .right),
                    subtitle: positionLabelShort(.right),
                    summary: rightSummary,
                    color: .purple,
                    position: .right
                )

                draftCountTile(
                    title: gateLabel(for: .farRight),
                    subtitle: positionLabelShort(.farRight),
                    summary: farRightSummary,
                    color: .orange,
                    position: .farRight
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onGoToDraftTab()
        }
    }

    private func draftCountTile(
        title: String,
        subtitle: String,
        summary: SessionViewModel.DraftGateSummary,
        color: Color,
        position: DraftPosition
    ) -> some View {
        let isActive = resolvedDraftPositionForCurrentAnimal == position
        let isFlashing = flashingPosition == position

        return VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive || isFlashing ? .white : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)

            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive || isFlashing ? .white.opacity(0.96) : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 2)

            Text("\(summary.count)")
                .font(.system(size: isPhone ? 15 : 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isActive || isFlashing ? .white : .primary)
                .lineLimit(1)

            Text(summary.averageWeightKg.map { String(format: "%.1f kg avg", $0) } ?? "—")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive || isFlashing ? .white.opacity(0.92) : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isFlashing
                    ? color
                    : (isActive ? color.opacity(0.92) : Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isFlashing
                    ? color
                    : (isActive ? color.opacity(0.98) : color.opacity(0.22)),
                    lineWidth: isFlashing ? 2 : (isActive ? 1.5 : 1)
                )
        )
        .shadow(color: (isActive || isFlashing) ? color.opacity(0.18) : .clear, radius: 8, y: 2)
        .animation(.easeOut(duration: 0.25), value: isFlashing)
    }

    private var treatmentPanel: some View {
        SessionLayoutScanWeighTreatDraftPanel(
            title: "Treatment",
            systemImage: "cross.case.fill"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if vm.sessionTreatments.isEmpty {
                    Text("No treatments configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Button {
                        onOpenTreatments()
                    } label: {
                        Text("Open Treatments")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                } else {
                    if vm.sessionTreatments.count > 1 {
                        Picker(
                            "Treatment",
                            selection: Binding<UUID?>(
                                get: { vm.selectedSessionTreatmentID },
                                set: { vm.selectSessionTreatment(id: $0) }
                            )
                        ) {
                            ForEach(vm.sessionTreatments) { treatment in
                                Text(treatment.product).tag(Optional(treatment.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Selected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(selectedTreatmentName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Dose")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(treatmentDoseText)
                                .font(.system(size: isPhone ? 18 : 22, weight: .bold, design: .rounded))
                                .foregroundStyle(vm.calculatedDoseText == nil ? .secondary : .primary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }

                    Text(treatmentDoseBasisText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(treatmentStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Button {
                            guard let treatment = vm.selectedSessionTreatment else { return }
                            let weight = (vm.hasDoseReadyWeight || vm.isLocked) ? vm.currentWeight : 0
                            tepariGun.sendSelectedTreatment(treatment, weightKg: weight)
                            lastAutoSentSignature = currentAutoSendSignature
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "syringe.fill")
                                Text(tepariGun.isSending ? "Sending…" : "Set Gun Dose")
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canSendDoseToGun ? .white : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canSendDoseToGun ? Color.blue.opacity(0.92) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .disabled(!canSendDoseToGun || tepariGun.isSending)

                        Button {
                            onOpenTreatments()
                        } label: {
                            Text("Edit")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(gunDotColor)
                            .frame(width: 8, height: 8)

                        Text("Gun")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 8)

                        Text(gunStatusText)
                            .font(.caption2)
                            .foregroundStyle(gunStatusColor)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SessionWideTile(
                    title: "Reweigh",
                    systemImage: "arrow.triangle.branch",
                    dotColor: nil,
                    height: 54,
                    enabled: true,
                    action: onGoToDraftTab
                )

                SessionWideTile(
                    title: "Treatments (\(vm.sessionTreatments.count))",
                    systemImage: "cross.case.fill",
                    dotColor: nil,
                    height: 54,
                    enabled: true,
                    action: onOpenTreatments
                )
            }

            HStack(spacing: 10) {
                SessionWideTile(
                    title: "New Session",
                    systemImage: "plus.circle",
                    dotColor: nil,
                    height: 54,
                    enabled: true,
                    action: onStartNewSession
                )

                SessionWideTile(
                    title: "Display",
                    systemImage: "chevron.up",
                    dotColor: nil,
                    height: 54,
                    enabled: true
                ) {
                    showDetails = true
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func autoSendDoseIfNeeded() {
        guard let signature = currentAutoSendSignature else {
            if vm.currentEID == "—" || vm.currentEID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastAutoSentSignature = nil
            }
            return
        }

        guard signature != lastAutoSentSignature else { return }
        guard !tepariGun.isSending else { return }
        guard let treatment = vm.selectedSessionTreatment,
              let weight = currentDoseReadyWeight else { return }

        lastAutoSentSignature = signature
        tepariGun.sendSelectedTreatment(treatment, weightKg: weight)
    }

    private func gateLabel(for position: DraftPosition) -> String {
        let matchingRules = draftRuleEngine.rules.filter { rule in
            rule.resolvedPosition(using: draftRuleEngine.gateMap) == position
        }

        if let first = matchingRules.first {
            let names = matchingRules
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if names.isEmpty {
                return "Configured"
            }

            if names.count == 1 {
                return names[0]
            }

            if names.count == 2 {
                return "\(names[0]), \(names[1])"
            }

            return "\(names[0]) +\(names.count - 1)"
        }

        if let fallback = defaultLogicalLabel(for: position) {
            return fallback
        }

        return "Not set"
    }

    private func defaultLogicalLabel(for position: DraftPosition) -> String? {
        let map = draftRuleEngine.gateMap

        var labels: [String] = []

        if map.empty == position { labels.append(DraftLogicalTarget.empty.label) }
        if map.single == position { labels.append(DraftLogicalTarget.single.label) }
        if map.twin == position { labels.append(DraftLogicalTarget.twin.label) }
        if map.keep == position { labels.append(DraftLogicalTarget.keep.label) }
        if map.cull == position { labels.append(DraftLogicalTarget.cull.label) }
        if map.custom == position { labels.append(DraftLogicalTarget.custom.label) }

        guard !labels.isEmpty else { return nil }

        if labels.count == 1 {
            return labels[0]
        }

        if labels.count == 2 {
            return "\(labels[0]), \(labels[1])"
        }

        return "\(labels[0]) +\(labels.count - 1)"
    }

    private func positionLabelShort(_ position: DraftPosition) -> String {
        switch position {
        case .left: return "Left gate"
        case .straight: return "Straight gate"
        case .right: return "Right gate"
        case .farRight: return "Far right gate"
        }
    }
}

private struct SessionLayoutScanWeighTreatDraftPanel<Content: View>: View {
    let title: String
    let systemImage: String?
    let trailingText: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        trailingText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingText = trailingText
        self.content = content()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Text(title)
                        .font(.headline)

                    Spacer(minLength: 8)

                    if let trailingText, !trailingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(trailingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Divider().opacity(0.18)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SessionCenteredWeightBoard: View {
    let weight: Double
    let locked: Bool
    let stable: Bool
    let onWeighMode: () -> Void

    private var weightText: String {
        String(format: "%.1f", weight)
    }

    private var highlightColor: Color {
        if locked { return .blue }
        if stable { return .green }
        return .white
    }

    private var isHighlightMode: Bool {
        locked || stable
    }

    var body: some View {
        GeometryReader { geo in
            let digitSize = min(geo.size.width * 0.30, geo.size.height * 0.60)
            let unitSize = digitSize * 0.46

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        isHighlightMode
                        ? highlightColor.opacity(0.18)
                        : Color.white.opacity(0.04)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isHighlightMode
                                ? highlightColor.opacity(0.85)
                                : Color.white.opacity(0.12),
                                lineWidth: isHighlightMode ? 2 : 1
                            )
                    )

                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            statusBadge(
                                title: stable ? "Stable" : "Unstable",
                                fill: stable ? Color.green.opacity(0.22) : Color.orange.opacity(0.18),
                                stroke: stable ? Color.green.opacity(0.40) : Color.orange.opacity(0.36),
                                text: stable ? .green : .orange,
                                icon: stable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                            )

                            statusBadge(
                                title: locked ? "Locked" : "Live",
                                fill: locked ? Color.blue.opacity(0.22) : Color.white.opacity(0.08),
                                stroke: locked ? Color.blue.opacity(0.40) : Color.white.opacity(0.16),
                                text: locked ? .blue : .secondary,
                                icon: locked ? "lock.fill" : "waveform.path.ecg"
                            )
                        }

                        Spacer(minLength: 8)

                        Button(action: onWeighMode) {
                            Image(systemName: "square.on.square")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    Spacer(minLength: 0)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        Text(weightText)
                            .font(.system(size: digitSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isHighlightMode ? highlightColor : .white)
                            .minimumScaleFactor(0.42)
                            .lineLimit(1)

                        Text(" kg")
                            .font(.system(size: unitSize, weight: .bold, design: .rounded))
                            .foregroundStyle(isHighlightMode ? highlightColor : .white)
                            .minimumScaleFactor(0.7)
                            .padding(.top, digitSize * 0.10)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)

                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onWeighMode)
    }

    private func statusBadge(
        title: String,
        fill: Color,
        stroke: Color,
        text: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
    }
}

private struct SessionLayoutScanWeighTreatDraftFullRecordListView: View {
    let sessionName: String
    let recordsNewestFirst: [AnimalRecord]

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()

            List {
                Section {
                    Text(sessionName)
                        .font(.headline)
                }

                Section("Scans (Most recent first)") {
                    if recordsNewestFirst.isEmpty {
                        Text("No animals recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(recordsNewestFirst.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(r.eidRaw)
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                HStack(spacing: 10) {
                                    if r.lockedWeight > 0 {
                                        Text(String(format: "%.1f kg", r.lockedWeight))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let pos = r.draftResult {
                                        Text(positionLabel(pos))
                                            .foregroundStyle(.secondary)
                                    }

                                    if !r.treatments.isEmpty {
                                        Text("Treat")
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func positionLabel(_ p: DraftPosition) -> String {
        switch p {
        case .left: return "Left"
        case .straight: return "Straight"
        case .right: return "Right"
        case .farRight: return "Far Right"
        }
    }
}

private struct SessionLayoutScanWeighTreatDraftHeaderHUD: View {
    @EnvironmentObject private var store: LocalDataStore
    @Environment(\.colorScheme) private var scheme

    let eid: String
    let sessionName: String
    let scannedCount: Int

    private var cleanedEID: String {
        EIDValidator.cleanedRaw(eid)
    }

    private var currentMob: LocalDataStore.Mob? {
        guard cleanedEID != "—", !cleanedEID.isEmpty else { return nil }
        guard let profile = store.animalProfileAnyFarm(eidRaw: cleanedEID) else { return nil }
        guard let mobID = profile.mobID else { return nil }
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
        currentMobColor == nil ? .secondary : .white
    }

    var body: some View {
        HStack(spacing: 12) {
            SessionLayoutScanWeighTreatDraftGlassChip(
                fillColor: eidPillFill,
                strokeColor: eidPillStroke
            ) {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(eidPillText)

                    Text(eid == "—" ? "Scan EID" : eid)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(eidPillText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
            }

            Spacer()

            SessionLayoutScanWeighTreatDraftGlassChip {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    Text(sessionName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            SessionLayoutScanWeighTreatDraftGlassChip {
                HStack(spacing: 12) {
                    Text("Tally")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("\(scannedCount)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
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
}

private struct SessionLayoutScanWeighTreatDraftGlassChip<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    private let chipHeight: CGFloat = 56
    private let fillColor: Color?
    private let strokeColor: Color?

    init(
        fillColor: Color? = nil,
        strokeColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.content = content()
    }

    var body: some View {
        content
            .frame(height: chipHeight)
            .padding(.horizontal, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor ?? Color.clear)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        strokeColor ?? Color.white.opacity(scheme == .dark ? 0.18 : 0.14),
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule(style: .continuous))
    }
}
