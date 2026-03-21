import SwiftUI
import Foundation

struct SessionLayoutScanTreatView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var tepariGun: TepariGunManager
    @ObservedObject var vm: SessionViewModel

    let activeTypes: Set<SetupSessionType>

    @Binding var showZeroConfirmation: Bool
    @Binding var showDetails: Bool

    let isPhone: Bool
    let scannedCount: Int

    let onStartNewSession: () -> Void
    let onSyncCoordinator: () -> Void
    let onOpenTreatments: () -> Void

    @State private var lastAutoSentSignature: String? = nil

    private var reservedBottomHeight: CGFloat {
        isPhone ? 150 : 0
    }

    // =====================================================
    // MARK: - Capabilities
    // =====================================================

    private var canScan: Bool { activeTypes.contains(.scan) }
    private var canTreat: Bool { activeTypes.contains(.treatment) }
    private var canTraits: Bool { activeTypes.contains(.traitInput) }

    // =====================================================
    // MARK: - Session config gates
    // =====================================================

    private var sessionConfig: LocalDataStore.SessionConfig? {
        store.config(for: vm.activeSession.id)
    }

    private var recordsNewestFirst: [AnimalRecord] {
        Array(store.records(for: vm.activeSession.id).reversed())
    }

    private var showMicron: Bool { sessionConfig?.recordMicron ?? true }
    private var showStaple: Bool { sessionConfig?.recordStapleLength ?? true }
    private var showCustom1: Bool { sessionConfig?.recordCustom1 ?? false }
    private var showCustom2: Bool { sessionConfig?.recordCustom2 ?? false }

    private var anyTraitsFieldsEnabled: Bool {
        showMicron || showStaple || showCustom1 || showCustom2
    }

    // =====================================================
    // MARK: - Custom trait helpers
    // =====================================================

    private var userDefinedFields: [LocalDataStore.CustomTraitDefinition] {
        vm.customTraitDefs
            .filter { $0.id == "custom1" || $0.id == "custom2" }
            .sorted { $0.id < $1.id }
            .filter { def in
                let labelOK = !def.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let enabledBySession: Bool = {
                    switch def.id {
                    case "custom1": return showCustom1
                    case "custom2": return showCustom2
                    default: return false
                    }
                }()
                return labelOK && enabledBySession
            }
    }

    private func customDraftValue(for id: String) -> String {
        vm.draftCustomTraits[id] ?? ""
    }

    // =====================================================
    // MARK: - Treatment helpers
    // =====================================================

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

    // =====================================================
    // MARK: - Body
    // =====================================================

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            mainBody
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SessionLayoutScanTreatHeaderHUD(
                eid: vm.currentEID,
                sessionName: vm.activeSession.name,
                scannedCount: scannedCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.thinMaterial)
            .overlay(Divider().opacity(0.20), alignment: .bottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPhone {
                phoneBottomActions
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(.thinMaterial)
                    .overlay(Divider().opacity(0.25), alignment: .top)
            }
        }
        .fullScreenCover(isPresented: $showDetails) {
            NavigationStack {
                SessionFullRecordListView(
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
    }

    @ViewBuilder
    private var mainBody: some View {
        if canTraits && canTreat {
            SessionTwoTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight,
                interTileSpacing: 12
            ) {
                traitsMegaCard
            } bottomContent: {
                treatmentsInfoCard
            }
        } else if canTraits {
            SessionSingleTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight
            ) {
                traitsMegaCard
            }
        } else {
            SessionSingleTileTemplateView(
                horizontalPadding: 16,
                topPadding: 14,
                bottomPadding: 12,
                reservedBottomHeight: reservedBottomHeight
            ) {
                treatmentsInfoCard
            }
        }
    }

    // =====================================================
    // MARK: - Traits Card
    // =====================================================

    private var traitsMegaCard: some View {
        SessionLayoutScanTreatPanel(
            title: "Traits",
            systemImage: "slider.horizontal.3",
            trailingText: "Auto-saves on next scan"
        ) {
            VStack(alignment: .leading, spacing: 12) {

                if !anyTraitsFieldsEnabled {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)

                        Text("No trait fields are enabled for this session. Re-run the wizard and enable Micron / Staple / Custom fields.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                selectedSummaryRow

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {

                        if showMicron {
                            micronFieldCardTwoRows
                        }

                        if showStaple {
                            stapleFieldCardTwoRows
                        }

                        ForEach(userDefinedFields, id: \.id) { def in
                            customFieldCard(def)
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var selectedSummaryRow: some View {
        HStack(spacing: 10) {

            if showMicron {
                selectedSummaryPill(
                    title: "Micron",
                    value: micronSelectedText,
                    isSet: vm.draftMicron != nil
                )
            }

            if showStaple {
                selectedSummaryPill(
                    title: "Staple",
                    value: stapleSelectedText,
                    isSet: vm.draftStapleLengthMm != nil
                )
            }

            if (showMicron ? 1 : 0) + (showStaple ? 1 : 0) == 1 {
                Spacer(minLength: 0)
            }
        }
    }

    private func selectedSummaryPill(title: String, value: String, isSet: Bool) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSet ? Color.green : Color.secondary.opacity(0.55))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }

    private var micronSelectedText: String {
        guard let v = vm.draftMicron else { return "—" }
        return "\(formatMicron(v)) µ"
    }

    private var stapleSelectedText: String {
        guard let v = vm.draftStapleLengthMm else { return "—" }
        return "\(v) mm"
    }

    // =====================================================
    // MARK: - Micron / Staple cards
    // =====================================================

    private var micronFieldCardTwoRows: some View {
        traitPickCard(
            title: "Micron",
            systemImage: "waveform.path.ecg",
            selectedLine: vm.draftMicron == nil ? "Selected: —" : "Selected: \(formatMicron(vm.draftMicron!)) µ",
            picks: vm.micronQuickPicks.map {
                TraitPick(label: "\(formatMicron($0))", isSelected: vm.draftMicron == $0)
            },
            onTapPickAtIndex: { idx in
                let v = vm.micronQuickPicks[idx]
                vm.setDraftMicron(v)
            }
        )
    }

    private var stapleFieldCardTwoRows: some View {
        traitPickCard(
            title: "Staple",
            systemImage: "ruler",
            selectedLine: vm.draftStapleLengthMm == nil ? "Selected: —" : "Selected: \(vm.draftStapleLengthMm!) mm",
            picks: vm.stapleQuickPicksMm.map { mm in
                TraitPick(label: "\(mm)", isSelected: vm.draftStapleLengthMm == mm)
            },
            onTapPickAtIndex: { idx in
                let v = vm.stapleQuickPicksMm[idx]
                vm.setDraftStapleLengthMm(v)
            }
        )
    }

    private struct TraitPick: Hashable {
        let label: String
        let isSelected: Bool
    }

    private func traitPickCard(
        title: String,
        systemImage: String,
        selectedLine: String,
        picks: [TraitPick],
        onTapPickAtIndex: @escaping (Int) -> Void
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)

                        Text(selectedLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)
                }

                let rowSize = 5
                let row1 = Array(picks.prefix(rowSize))
                let row2 = Array(picks.dropFirst(rowSize).prefix(rowSize))

                VStack(spacing: 10) {
                    pickRow(row1, baseIndex: 0, onTapPickAtIndex: onTapPickAtIndex)

                    if !row2.isEmpty {
                        pickRow(row2, baseIndex: rowSize, onTapPickAtIndex: onTapPickAtIndex)
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
    }

    private func pickRow(
        _ row: [TraitPick],
        baseIndex: Int,
        onTapPickAtIndex: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(row.enumerated()), id: \.offset) { (i, p) in
                Button {
                    onTapPickAtIndex(baseIndex + i)
                } label: {
                    Text(p.label)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(p.isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(p.isSelected ? Color.blue.opacity(0.95) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(p.isSelected ? 0.14 : 0.10), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // =====================================================
    // MARK: - Custom fields
    // =====================================================

    private func customFieldCard(_ def: LocalDataStore.CustomTraitDefinition) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text(def.label)
                        .font(.headline)
                    Spacer()
                }

                if !def.quickPicks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(def.quickPicks, id: \.self) { p in
                                Button {
                                    vm.setDraftCustomTrait(id: def.id, value: p)
                                } label: {
                                    Text(p)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                TextField(
                    "Enter…",
                    text: Binding(
                        get: { customDraftValue(for: def.id) },
                        set: { vm.setDraftCustomTrait(id: def.id, value: $0) }
                    )
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            }
            .padding(12)
        }
    }

    // =====================================================
    // MARK: - Treatments Card
    // =====================================================

    private var treatmentsInfoCard: some View {
        SessionLayoutScanTreatPanel(
            title: "Treatment",
            systemImage: "cross.case.fill",
            trailingText: canScan ? nil : "No scan"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if vm.sessionTreatments.isEmpty {
                    Text("No treatments configured for this session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button {
                        onOpenTreatments()
                    } label: {
                        Text("+Add Treatments")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
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

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(selectedTreatmentName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Dose")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(treatmentDoseText)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(vm.calculatedDoseText == nil ? .secondary : .primary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }

                    Text(treatmentDoseBasisText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(treatmentStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Divider().opacity(0.18)

                    HStack(spacing: 10) {
                        Button {
                            guard let treatment = vm.selectedSessionTreatment else { return }

                            let weight: Double = {
                                if vm.hasDoseReadyWeight { return vm.currentWeight }
                                if vm.isLocked { return vm.currentWeight }
                                return 0
                            }()

                            tepariGun.sendSelectedTreatment(treatment, weightKg: weight)
                            lastAutoSentSignature = currentAutoSendSignature
                        } label: {
                            HStack {
                                Image(systemName: "syringe.fill")
                                Text(tepariGun.isSending ? "Sending…" : "Set Gun Dose")
                                    .lineLimit(1)
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canSendDoseToGun ? Color.white : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(canSendDoseToGun ? Color.blue.opacity(0.92) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .disabled(!canSendDoseToGun || tepariGun.isSending)

                        Button {
                            onOpenTreatments()
                        } label: {
                            Text("Edit")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(gunDotColor)
                            .frame(width: 8, height: 8)

                        Text("Gun")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(gunStatusText)
                            .font(.caption)
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
        .contentShape(Rectangle())
        .onTapGesture {
            if vm.sessionTreatments.isEmpty {
                onOpenTreatments()
            }
        }
    }

    // =====================================================
    // MARK: - Bottom actions
    // =====================================================

    private var phoneBottomActions: some View {
        VStack(spacing: 10) {
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

            HStack(spacing: 10) {
                SessionWideTile(
                    title: "Treatments",
                    systemImage: "cross.case.fill",
                    dotColor: nil,
                    height: 54,
                    enabled: canTreat,
                    action: onOpenTreatments
                )

                SessionWideTile(
                    title: "Undo",
                    systemImage: "arrow.uturn.backward",
                    dotColor: nil,
                    height: 54,
                    enabled: false,
                    action: { }
                )
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 16)
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

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

    private func formatMicron(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.0001 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
    }
}

// =====================================================
// MARK: - Shared Panel
// =====================================================

private struct SessionLayoutScanTreatPanel<Content: View>: View {
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
                            .minimumScaleFactor(0.8)
                    }
                }

                Divider().opacity(0.18)

                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }
}

// =====================================================
// MARK: - Full session list
// =====================================================

private struct SessionFullRecordListView: View {
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
                    ForEach(Array(recordsNewestFirst.enumerated()), id: \.offset) { _, r in
                        VStack(alignment: .leading, spacing: 6) {

                            Text(r.eidRaw)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 10) {
                                if let m = r.micron {
                                    Text("Micron: \(formatMicronStatic(m)) μ")
                                        .foregroundStyle(.secondary)
                                }

                                if let s = r.stapleLengthMm {
                                    Text("Staple: \(s) mm")
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func formatMicronStatic(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.0001 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
    }
}

// =====================================================
// MARK: - Header HUD
// =====================================================

private struct SessionLayoutScanTreatHeaderHUD: View {
    let eid: String
    let sessionName: String
    let scannedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            SessionLayoutScanTreatGlassChip {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(eid == "—" ? "Scan EID" : eid)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
            }

            Spacer()

            SessionLayoutScanTreatGlassChip {
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

            SessionLayoutScanTreatGlassChip {
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
}

private struct SessionLayoutScanTreatGlassChip<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    private let chipHeight: CGFloat = 56

    var body: some View {
        content
            .frame(height: chipHeight)
            .padding(.horizontal, 18)
            .background(
                Capsule()
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.14), lineWidth: 1)
            )
    }
}
