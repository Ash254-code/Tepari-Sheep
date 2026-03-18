import SwiftUI

/// Session setup wizard shown when starting a new session.
/// Branching steps build a session config, then applies defaults + session treatments.
///
/// NOTE: This file now expects SetupWizardStep to include:
/// - .defaults
/// - .treatments
/// and you should remove/stop using .defaultsAndTreatments.
struct SessionSetupView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var sessionCoordinator: ActiveSessionCoordinator
    @EnvironmentObject private var presetStore: TreatmentPresetStore

    let sessionID: UUID
    var onDone: (() -> Void)? = nil

    // =========================================================
    // MARK: Wizard State
    // =========================================================

    @State var step: SetupWizardStep = .farm

    @State var selectedFarmID: UUID? = nil
    @State var manualFarmName: String = ""

    @State private var selectedYard: String? = nil
    @State private var sessionNameText: String = ""

    @State var selectedTypes: Set<SetupSessionType> = []
    @State var selectedEquipment: Set<SetupEquipment> = []

    // Locked by types (wizard no longer asks)
    @State var scannerType: LocalDataStore.ScannerType? = nil
    @State var weightSource: LocalDataStore.WeightSource? = nil

    @State var scanningEnabled: Bool? = nil
    @State var weighingEnabled: Bool? = nil

    @State private var planErrorMessage: String? = nil

    @State var recordTreatments: Bool = true
    @State var recordLambsProduced: Bool = false
    @State var recordFleeceWeight: Bool = false
    @State var recordStapleLength: Bool = false
    @State var recordMicron: Bool = false

    @State private var recordCustom1: Bool = false
    @State private var recordCustom2: Bool = false
    @State private var lastTraitsOn: Bool = false
    @State private var didAssignSuggestedName: Bool = false

    // =========================================================
    // MARK: Defaults / Treatments
    // =========================================================

    @State private var selectedSex: LocalDataStore.Sex = .ewe
    @State private var selectedClass: LocalDataStore.AnimalClass = .flock

    @State private var selectedBreed: String = ""
    @State private var selectedBirthYear: Int? = nil
    @State private var selectedBirthMonth: Int? = nil
    @State private var selectedStatus: AnimalStatus? = nil

    @State private var selectedMobName: String = SessionSetupMobStepView.noneSentinel

    @State private var overwriteSex: Bool = false
    @State private var overwriteBreed: Bool = false
    @State private var overwriteMob: Bool = false
    @State private var overwriteClass: Bool = false
    @State private var overwriteBirthYear: Bool = false
    @State private var overwriteBirthMonth: Bool = false
    @State private var overwriteStatus: Bool = false

    @State private var pendingOverwriteToggle: OverwriteField? = nil
    @State private var showOverwriteConfirm: Bool = false

    private enum OverwriteField: String {
        case sex = "Sex"
        case animalClass = "Class"
        case mob = "Mob"
    }

    private let addMobSentinel = "__ADD_NEW_MOB__"
    @State private var showAddMobPrompt: Bool = false
    @State private var newMobName: String = ""

    // =========================================================
    // MARK: Treatments
    // =========================================================

    @State private var selectedTreatmentIDs: Set<UUID> = []
    @State private var treatmentDoseOverrides: [UUID: DoseValue] = [:]

    // ✅ NEW: Tepari dosing gun toggle (drives "G" connectivity pill + connection prompt)
    @State private var tepariGunEnabled: Bool = false
    @State private var tepariTreatmentID: UUID? = nil

    private var treatmentLibrary: [TreatmentTemplate] {
        presetStore.presets.map { p in
            TreatmentTemplate(
                id: p.id,
                product: p.name,
                doseValue: p.doseAmount ?? "",
                doseUnit: p.doseUnit ?? .mL,
                doseBasis: p.doseBasis ?? .perAnimal,
                dosePerKg: p.dosePerKg,
                withholding: p.defaultWithholdingDays.map(String.init) ?? ""
            )
        }
    }

    private var hasFarmsConfigured: Bool { !store.farms.isEmpty }

    private var selectedFarm: LocalDataStore.Farm? {
        guard let id = selectedFarmID else { return nil }
        return store.farms.first(where: { $0.id == id })
    }

    private var resolvedFarmName: String {
        if hasFarmsConfigured {
            return selectedFarm?.name ?? ""
        } else {
            return manualFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var isSessionTypeSelectionValid: Bool {
        SetupSessionTypeRules.isValid(selectedTypes) && (planErrorMessage == nil)
    }

    private var availableMobsForSelectedFarm: [LocalDataStore.Mob] {
        guard let farmID = selectedFarmID else { return [] }
        return store.mobs(for: farmID)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isMixedMobSelection: Bool {
        selectedMobName.isMobMixed
    }

    private var shouldApplyMobOverwrite: Bool {
        overwriteMob && !isMixedMobSelection
    }

    // =========================================================
    // MARK: Derived navigation
    // =========================================================


    private var isScanOnly: Bool {
        selectedTypes == [.scan]
    }

    private var visibleSteps: [SetupWizardStep] {
        var s: [SetupWizardStep] = [.farm]
        s.append(.yards)
        s.append(.mob)
        s.append(.sessionTypes)

        if isScanOnly {
            s.append(.scannerType)
        }

        s.append(.defaults)

        if selectedTypes.contains(.treatment) {
            s.append(.treatments)
        }

        s.append(.sessionName)
        s.append(.review)
        return s
    }

    private var canGoBack: Bool { step != .farm }
    private var canGoNext: Bool { isStepValid(step) }

    private var isFullScreenTileStep: Bool {
        step == .farm || step == .yards || step == .sessionTypes || step == .mob || step == .scannerType
    }

    // =========================================================
    // MARK: Locked Plan (Session Types → Equipment/Mode)
    // =========================================================

    private func equipmentRequired(for type: SetupSessionType) -> Set<SetupEquipment> {
        switch type {
        case .draft:
            return [.handler, .draft]
        case .weigh:
            return [.handler, .scales]
        case .fleeceWeigh:
            return [.stickReader, .fleeceScales]
        case .scan, .transfer, .sale:
            return [.handler, .scanner]
        case .lambMarking:
            return [.stickReader]
        case .traitInput:
            return []
        case .treatment:
            return []
        default:
            return []
        }
    }

    private var custom1EnabledInSettings: Bool {
        let label = store.traitsConfig.customFields.first(where: { $0.id == "custom1" })?.label ?? ""
        return !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var custom2EnabledInSettings: Bool {
        let label = store.traitsConfig.customFields.first(where: { $0.id == "custom2" })?.label ?? ""
        return !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ✅ The “brain”: sets defaults for scanner/weight based on selectedTypes
    private func applyLockedPlanFromTypes() {

        var locked: Set<SetupEquipment> = []
        for t in selectedTypes {
            locked.formUnion(equipmentRequired(for: t))
        }

        if selectedTypes.contains(.draft) {
            locked.insert(.scales)
            locked.insert(.handler)
            locked.insert(.draft)
        }

        selectedEquipment = locked

        if locked.contains(.scanner) && locked.contains(.stickReader) {
            planErrorMessage = "Can’t combine Scanner sessions with Stick Reader sessions."
        } else {
            planErrorMessage = nil
        }

        scanningEnabled = selectedTypes.contains(.scan) || locked.contains(.scanner) || locked.contains(.stickReader)
        weighingEnabled = locked.contains(.scales) || locked.contains(.fleeceScales)

        if weighingEnabled == true {
            if weightSource == nil { weightSource = .tepariT1 }
        } else {
            weightSource = nil
        }

        if selectedTypes.contains(.scan) {
            if isScanOnly {
                if scannerType == nil {
                    scannerType = .stickReader
                }
            } else {
                scannerType = .racewell
            }
        } else {
            scannerType = nil
        }

        applyScannerSelectionToEquipment()

        recordTreatments = selectedTypes.contains(.treatment)
        recordLambsProduced = selectedTypes.contains(.lambMarking)
        recordFleeceWeight = selectedTypes.contains(.fleeceWeigh)

        let traitsOn = selectedTypes.contains(.traitInput)

        if traitsOn {
            if lastTraitsOn == false {
                recordMicron = false
                recordStapleLength = false
                recordCustom1 = custom1EnabledInSettings ? recordCustom1 : false
                recordCustom2 = custom2EnabledInSettings ? recordCustom2 : false
            }
            if !custom1EnabledInSettings { recordCustom1 = false }
            if !custom2EnabledInSettings { recordCustom2 = false }
        } else {
            recordStapleLength = false
            recordMicron = false
            recordCustom1 = false
            recordCustom2 = false
        }

        lastTraitsOn = traitsOn

        if recordTreatments == false {
            selectedTreatmentIDs.removeAll()
            treatmentDoseOverrides.removeAll()
            store.clearTreatments(sessionID: sessionID)
        }
    }

    // =========================================================
    // MARK: Session naming
    // =========================================================

    private var currentAnimalCountForName: Int? { nil }

    private func resolvedMobLabelForName() -> String? {
        let mobTrim = selectedMobName.trimmingCharacters(in: .whitespacesAndNewlines)
        if mobTrim == SessionSetupMobStepView.mixedSentinel { return "Mixed" }
        if mobTrim == SessionSetupMobStepView.noneSentinel || mobTrim.isEmpty { return nil }
        return mobTrim
    }

    private func suggestSessionNameIfNeeded() {
        guard !didAssignSuggestedName else { return }
        guard sessionNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let farmName = resolvedFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !farmName.isEmpty else { return }

        let typeLabel = primaryTypeLabel
        let mobLabel = resolvedMobLabelForName()

        let suggested = store.makeUniqueSessionName(
            typeLabel: typeLabel,
            farmName: farmName,
            yardName: selectedYard,
            mobName: mobLabel,
            animalCount: currentAnimalCountForName,
            at: Date()
        )

        sessionNameText = suggested
        didAssignSuggestedName = true
    }

    private func persistSessionNameNow() {
        let trimmed = sessionNameText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            let farmName = resolvedFarmName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !farmName.isEmpty else { return }

            let typeLabel = primaryTypeLabel
            let mobLabel = resolvedMobLabelForName()

            let fallback = store.makeUniqueSessionName(
                typeLabel: typeLabel,
                farmName: farmName,
                yardName: selectedYard,
                mobName: mobLabel,
                animalCount: currentAnimalCountForName,
                at: Date()
            )

            store.setSessionName(sessionID: sessionID, name: fallback)
            sessionNameText = fallback
            return
        }

        store.setSessionName(sessionID: sessionID, name: trimmed)
    }

    private func refineSessionNameAfterTypesIfNeeded() {
        guard didAssignSuggestedName else { return }
        sessionNameText = ""
        didAssignSuggestedName = false
        suggestSessionNameIfNeeded()
        persistSessionNameNow()
    }

    private var primaryTypeLabel: String {
        var parts: [String] = []

        if selectedTypes.contains(.draft) { parts.append("Draft") }
        if selectedTypes.contains(.weigh) { parts.append("Weigh") }
        if selectedTypes.contains(.treatment) { parts.append("Treat") }

        if !parts.isEmpty {
            return parts.joined(separator: "/")
        }

        if selectedTypes.contains(.fleeceWeigh) { return "Fleece Weigh" }
        if selectedTypes.contains(.traitInput) { return "Traits" }
        if selectedTypes.contains(.lambMarking) { return "Lamb Marking" }
        if selectedTypes.contains(.pregTesting) { return "Preg Test" }
        if selectedTypes.contains(.transfer) { return "Transfer" }
        if selectedTypes.contains(.sale) { return "Sale" }
        if selectedTypes.contains(.scan) { return "Scan" }

        return ""
    }
    private var readerModeLabel: String {
        if let st = scannerType { return st.label }
        return "—"
    }

    private var weightModeLabel: String {
        if let ws = weightSource { return ws.label }
        return "—"
    }

    // =========================================================
    // MARK: Body
    // =========================================================

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("New Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelToolbar }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .onAppear {
                    handleOnAppear()
                    snapStepIntoVisibleRange()
                }
                .onChange(of: selectedTypes) { _, _ in
                    applyLockedPlanFromTypes()
                    snapStepIntoVisibleRange()
                    refineSessionNameAfterTypesIfNeeded()
                }
                .onChange(of: scannerType) { _, _ in
                    applyScannerSelectionToEquipment()
                }
                .onChange(of: recordTreatments) { _, newValue in
                    if newValue == false {
                        selectedTreatmentIDs.removeAll()
                        treatmentDoseOverrides.removeAll()
                        store.clearTreatments(sessionID: sessionID)
                    } else {
                        syncSelectedTreatmentsToStore()
                    }
                }
                .onChange(of: selectedFarmID) { _, newID in
                    handleFarmChange(newID)
                }
                .onChange(of: selectedYard) { _, _ in
                    if didAssignSuggestedName {
                        sessionNameText = ""
                        didAssignSuggestedName = false
                    }
                }
                .onChange(of: selectedMobName) { _, newValue in
                    handleMobSelectionChange(newValue)
                    if didAssignSuggestedName {
                        sessionNameText = ""
                        didAssignSuggestedName = false
                    }
                }
                .onChange(of: sessionNameText) { _, newValue in
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        didAssignSuggestedName = false
                    }
                }
                .alert("Add New Mob", isPresented: $showAddMobPrompt) {
                    TextField("Mob name", text: $newMobName)
                    Button("Cancel", role: .cancel) { newMobName = "" }
                    Button("Add") { addNewMobNow() }
                        .disabled(newMobName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } message: {
                    Text("This will create a new Mob in Settings for the selected Farm.")
                }
                .alert("WARNING", isPresented: $showOverwriteConfirm) {
                    Button("Cancel", role: .cancel) { revertPendingOverwriteToggle() }
                    Button("Overwrite", role: .destructive) { confirmPendingOverwriteToggle() }
                } message: {
                    let field = pendingOverwriteToggle?.rawValue ?? "this field"
                    Text("This will overwrite ALL existing animal records for \(field).\n\nAre you sure you want to proceed?")
                }
        }
        .presentationDetents([.fraction(0.95), .large])
        .presentationDragIndicator(.visible)
    }

    // =========================================================
    // MARK: Main content + Toolbar
    // =========================================================

    private var mainContent: some View {
        ZStack {
            GlassBackground()

            if isFullScreenTileStep {
                stepBody
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        stepBody
                        Spacer(minLength: 8)
                    }
                    .padding(16)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var cancelToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
    }

    // =========================================================
    // MARK: Step Body
    // =========================================================

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .farm:
            SessionSetupFarmStepView(
                selectedFarmID: $selectedFarmID,
                manualFarmName: $manualFarmName,
                onAutoNext: { goNext() }
            )

        case .yards:
            SessionSetupYardStepView(
                selectedFarmID: $selectedFarmID,
                selectedYard: $selectedYard,
                onAutoNext: { goNext() }
            )

        case .mob:
            SessionSetupMobStepView(
                selectedMobName: $selectedMobName,
                mobs: availableMobsForSelectedFarm,
                addMobSentinel: addMobSentinel,
                onTapAddNew: { showAddMobPrompt = true },
                onAutoNext: { goNext() }
            )

        case .sessionTypes:
            SessionSetupSessionTypesStepView(
                selectedTypes: $selectedTypes,
                lockedEquipment: selectedEquipment,
                planErrorMessage: planErrorMessage,
                onSelectionChanged: { applyLockedPlanFromTypes() }
            )

        case .scannerType:
            SessionSetupChooseScannerStepView(
                scannerType: $scannerType
            )

        case .defaults:
            SessionSetupDefaultsStepView(
                selectedFarmID: selectedFarmID,
                availableMobsForSelectedFarm: availableMobsForSelectedFarm,
                selectedSex: $selectedSex,
                selectedBreed: $selectedBreed,
                selectedMobName: $selectedMobName,
                selectedClass: $selectedClass,
                selectedBirthYear: $selectedBirthYear,
                selectedBirthMonth: $selectedBirthMonth,
                selectedStatus: $selectedStatus,
                overwriteSex: $overwriteSex,
                overwriteBreed: $overwriteBreed,
                overwriteMob: $overwriteMob,
                overwriteClass: $overwriteClass,
                overwriteBirthYear: $overwriteBirthYear,
                overwriteBirthMonth: $overwriteBirthMonth,
                overwriteStatus: $overwriteStatus,
                onRequestOverwriteConfirmSex: { requestOverwriteConfirm(.sex) },
                onRequestOverwriteConfirmClass: { requestOverwriteConfirm(.animalClass) },
                onRequestOverwriteConfirmMob: { requestOverwriteConfirm(.mob) },
                addMobSentinel: addMobSentinel,
                showAddMobPrompt: $showAddMobPrompt,
                newMobName: $newMobName
            )

        case .treatments:
            SessionSetupTreatmentsStepView(
                tepariGunEnabled: $tepariGunEnabled,
                tepariTreatmentID: $tepariTreatmentID,
                onTepariChanged: { _ in },
                recordTreatments: $recordTreatments,
                treatmentLibrary: treatmentLibrary,
                selectedTreatmentIDs: $selectedTreatmentIDs,
                doseOverrides: $treatmentDoseOverrides,
                onAddTreatmentTemplate: { template in
                    addTemplateToSettings(template)
                },
                onSelectionChanged: {
                    syncSelectedTreatmentsToStore()
                }
            )

        case .sessionName:
            SessionSetupNameStepView(
                sessionNameText: $sessionNameText,
                didAssignSuggestedName: $didAssignSuggestedName,
                suggestSessionNameIfNeeded: {
                    sessionNameText = ""
                    didAssignSuggestedName = false
                    suggestSessionNameIfNeeded()
                },
                persistSessionNameNow: { persistSessionNameNow() }
            )

        case .review:
            SessionSetupReviewStepView(
                resolvedFarmName: resolvedFarmName,
                selectedYard: selectedYard,
                sessionNameText: sessionNameText,
                hasFarmsConfigured: hasFarmsConfigured,
                selectedFarmPIC: selectedFarm?.pic,
                selectedTypesText: selectedTypes.map { $0.rawValue }.sorted().joined(separator: ", "),
                selectedEquipmentText: selectedEquipment.map { $0.rawValue }.sorted().joined(separator: ", "),
                scannerLabel: readerModeLabel,
                weighingEnabled: (weighingEnabled == true),
                weightSourceLabel: weightModeLabel,
                recordTreatments: recordTreatments,
                recordLambsProduced: recordLambsProduced,
                recordFleeceWeight: recordFleeceWeight,
                recordStapleLength: recordStapleLength,
                recordMicron: recordMicron,
                defaultSexLabel: selectedSex.label,
                defaultClassLabel: selectedClass.label,
                defaultMobName: selectedMobName,
                overwriteSex: overwriteSex,
                overwriteClass: overwriteClass,
                overwriteMob: shouldApplyMobOverwrite,
                sessionTreatments: treatmentLibrary
                    .filter { selectedTreatmentIDs.contains($0.id) }
                    .sorted { $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending }
                    .map { t in
                        let ov = treatmentDoseOverrides[t.id]

                        let value = (ov?.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                            ? ov?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            : t.doseValue

                        let unit = ov?.unit ?? t.doseUnit
                        let basis = ov?.basis ?? t.doseBasis
                        let perKg = (ov?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                            ? ov?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines)
                            : t.dosePerKg?.trimmedOrNil

                        let reviewValue: String
                        let reviewUnit: DoseUnit

                        switch basis {
                        case .perAnimal:
                            reviewValue = value
                            reviewUnit = unit
                        case .perBodyWeight:
                            let per = (perKg ?? "10")
                            reviewValue = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\(value) / \(per)kg"
                            reviewUnit = unit
                        }

                        return SessionSetupReviewStepView.TreatmentSummary(
                            id: t.id,
                            product: t.product,
                            doseValue: reviewValue,
                            doseUnit: reviewUnit,
                            withholding: t.withholding
                        )
                    }
            )
        }
    }
    // =========================================================
    // MARK: Bottom Bar
    // =========================================================

    private var bottomBar: some View {
        GlassCard {
            HStack(spacing: 10) {

                Button { goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .foregroundStyle(canGoBack ? Color.primary : Color.secondary)
                }
                .glassButton(.compact)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0.35)

                Spacer()

                if step == .review {
                    Button { startSession() } label: {
                        Label("Start", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.blue)
                    }
                    .glassButton(.compact)
                    .tint(.blue)

                } else {
                    Button { goNext() } label: {
                        Label("Next", systemImage: "chevron.right")
                            .foregroundStyle(canGoNext ? Color.blue : Color.secondary)
                    }
                    .glassButton(.compact)
                    .disabled(!canGoNext)
                    .opacity(canGoNext ? 1 : 0.55)
                    .animation(.easeInOut(duration: 0.15), value: canGoNext)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// =========================================================
// MARK: - Wizard helpers
// =========================================================

private extension SessionSetupView {

    // ---------- Validation ----------

    func isStepValid(_ step: SetupWizardStep) -> Bool {
        switch step {

        case .farm:
            if hasFarmsConfigured {
                return selectedFarmID != nil
            } else {
                return !manualFarmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

        case .sessionTypes:
            return isSessionTypeSelectionValid

        case .scannerType:
            return scannerType != nil

        default:
            return true
        }
    }

    // ---------- Navigation ----------

    func goNext() {
        guard let idx = visibleSteps.firstIndex(of: step) else { return }
        let nextIdx = min(idx + 1, visibleSteps.count - 1)

        if step == .farm, let farmID = selectedFarmID {
            store.setFarm(for: sessionID, farmID: farmID)
        }

        if step == .sessionTypes {
            applyLockedPlanFromTypes()
        }

        if step == .sessionName {
            persistSessionNameNow()
        }

        step = visibleSteps[nextIdx]
    }

    func goBack() {
        guard let idx = visibleSteps.firstIndex(of: step) else { return }
        let prevIdx = max(idx - 1, 0)
        step = visibleSteps[prevIdx]
    }

    func snapStepIntoVisibleRange() {
        if visibleSteps.contains(step) { return }
        step = visibleSteps.first ?? .farm
    }

    // ---------- Lifecycle ----------

    func handleOnAppear() {
        if let existingSex = store.defaultSex(for: sessionID) { selectedSex = existingSex }
        if let existingClass = store.defaultClass(for: sessionID) { selectedClass = existingClass }

        selectedBreed = store.defaultBreed(for: sessionID)
        selectedBirthYear = store.defaultBirthYear(for: sessionID)
        selectedBirthMonth = store.defaultBirthMonth(for: sessionID)
        selectedStatus = store.defaultStatus(for: sessionID)

        if let mobName = store.defaultMobName(for: sessionID) {
            let t = mobName.trimmingCharacters(in: .whitespacesAndNewlines)
            selectedMobName = t.isEmpty ? SessionSetupMobStepView.noneSentinel : t
        }

        overwriteSex = store.overwriteSexEnabled(for: sessionID)
        overwriteClass = store.overwriteClassEnabled(for: sessionID)
        overwriteMob = store.overwriteMobEnabled(for: sessionID)

        if selectedMobName.isMobMixed {
            overwriteMob = false
        }

        bootstrapSelectedTreatmentsFromStore()

        applyLockedPlanFromTypes()

        if visibleSteps.contains(step) {
            // keep current step
        } else {
            step = .farm
        }
    }

    func handleFarmChange(_ newID: UUID?) {
        if let farmID = newID {
            store.setFarm(for: sessionID, farmID: farmID)
        }
    }

    func handleMobSelectionChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == SessionSetupMobStepView.mixedSentinel {
            overwriteMob = false
            if pendingOverwriteToggle == .mob {
                pendingOverwriteToggle = nil
                showOverwriteConfirm = false
            }
        }
    }

    // ---------- Add Mob ----------

    func addNewMobNow() {
        guard let farmID = selectedFarmID else { return }

        let trimmed = newMobName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = store.mobs(for: farmID).first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedMobName = existing.name
            newMobName = ""
            return
        }

        let created = store.addMob(farmID: farmID, name: trimmed, colorHex: "#4CAF50")
        selectedMobName = created.name
        newMobName = ""
    }

    // ---------- Overwrite confirm ----------

    private func requestOverwriteConfirm(_ field: OverwriteField) {
        if field == .mob && isMixedMobSelection {
            overwriteMob = false
            return
        }

        pendingOverwriteToggle = field
        showOverwriteConfirm = true
    }

    func revertPendingOverwriteToggle() {
        guard let field = pendingOverwriteToggle else { return }
        switch field {
        case .sex: overwriteSex = false
        case .animalClass: overwriteClass = false
        case .mob: overwriteMob = false
        }
        pendingOverwriteToggle = nil
    }

    func confirmPendingOverwriteToggle() {
        guard let field = pendingOverwriteToggle else { return }
        switch field {
        case .sex:
            overwriteSex = true
        case .animalClass:
            overwriteClass = true
        case .mob:
            overwriteMob = isMixedMobSelection ? false : true
        }
        pendingOverwriteToggle = nil
    }

    // ---------- Treatments ----------

    func bootstrapSelectedTreatmentsFromStore() {
        let current = store.treatments(for: sessionID)
        guard !current.isEmpty else { return }

        var ids: Set<UUID> = []
        var overrides: [UUID: DoseValue] = [:]

        for s in current {
            if let match = treatmentLibrary.first(where: { $0.product.caseInsensitiveCompare(s.product) == .orderedSame }) {
                ids.insert(match.id)

                if let override = doseValueFromSessionTreatment(s, fallbackUnit: match.doseUnit) {
                    overrides[match.id] = override
                }
            }
        }

        selectedTreatmentIDs = ids
        treatmentDoseOverrides = overrides
    }

    func addTemplateToSettings(_ template: TreatmentTemplate) {
        let _ = template
    }

    func syncSelectedTreatmentsToStore() {
        guard recordTreatments else {
            store.clearTreatments(sessionID: sessionID)
            return
        }

        let ids = selectedTreatmentIDs
        let picked = treatmentLibrary
            .filter { ids.contains($0.id) }
            .sorted { $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending }

        let mapped: [SessionTreatment] = picked.map { t in
            let ov = treatmentDoseOverrides[t.id]

            let value = (ov?.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? ov?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                : t.doseValue

            let unit = ov?.unit ?? t.doseUnit
            let basis = ov?.basis ?? t.doseBasis
            let perKg = (ov?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? ov?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines)
                : t.dosePerKg?.trimmedOrNil

            let doseString: String = {
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedValue.isEmpty else { return "" }

                switch basis {
                case .perAnimal:
                    return "\(trimmedValue) \(unit.rawValue)"
                case .perBodyWeight:
                    let per = (perKg ?? "10").trimmingCharacters(in: .whitespacesAndNewlines)
                    let safePer = per.isEmpty ? "10" : per
                    return "\(trimmedValue) \(unit.rawValue) / \(safePer) kg"
                }
            }()

            return SessionTreatment(
                product: t.product,
                dosage: doseString,
                withholding: t.withholding,
                doseValue: value.trimmedOrNil,
                doseUnit: unit,
                doseBasis: basis,
                dosePerKg: basis == .perBodyWeight ? perKg : nil,
                minimumDose: nil,
                maximumDose: nil,
                doseStep: nil,
                requiresStableWeight: true
            )
        }

        store.setSessionTreatments(mapped, for: sessionID)
    }

    func doseValueFromSessionTreatment(_ treatment: SessionTreatment, fallbackUnit: DoseUnit) -> DoseValue? {
        if let value = treatment.doseValue?.trimmedOrNil {
            let unit = treatment.doseUnit ?? fallbackUnit
            let basis = treatment.doseBasis ?? .perAnimal
            let perKg = basis == .perBodyWeight ? treatment.dosePerKg : nil
            return DoseValue(value: value, unit: unit, basis: basis, perKg: perKg)
        }

        let legacy = treatment.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else { return nil }
        return parseDoseValueFromLegacyString(legacy, fallbackUnit: fallbackUnit)
    }

    func parseDoseValueFromLegacyString(_ s: String, fallbackUnit: DoseUnit) -> DoseValue {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return DoseValue(value: "", unit: fallbackUnit) }

        let compact = raw.replacingOccurrences(of: " ", with: "")

        if compact.contains("/") {
            let parts = compact.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let left = parts[0]
                let right = parts[1]

                let (value, unit) = parseAmountAndUnit(left, fallbackUnit: fallbackUnit)

                let rightLower = right.lowercased()
                if rightLower.hasSuffix("kg") {
                    let perRaw = String(right.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let perKg = perRaw.isEmpty ? "10" : perRaw
                    return DoseValue(value: value, unit: unit, basis: .perBodyWeight, perKg: perKg)
                }

                return DoseValue(value: value, unit: unit, basis: .perBodyWeight, perKg: "10")
            }
        }

        let (value, unit) = parseAmountAndUnit(compact, fallbackUnit: fallbackUnit)
        return DoseValue(value: value, unit: unit, basis: .perAnimal)
    }

    func parseAmountAndUnit(_ raw: String, fallbackUnit: DoseUnit) -> (String, DoseUnit) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", fallbackUnit) }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count >= 2 {
            let maybeUnit = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = DoseUnit(rawValue: maybeUnit) {
                let v = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                return (v, u)
            }
        }

        for u in DoseUnit.allCases {
            if trimmed.hasSuffix(u.rawValue) {
                let v = trimmed.replacingOccurrences(of: u.rawValue, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (v, u)
            }
        }

        return (trimmed, fallbackUnit)
    }

    // ---------- Start session ----------

    func startSession() {

        if let farmID = selectedFarmID {
            store.setFarm(for: sessionID, farmID: farmID)
        }

        if sessionNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            didAssignSuggestedName = false
            suggestSessionNameIfNeeded()
        }
        persistSessionNameNow()

        applyLockedPlanFromTypes()

        store.setConfig(buildConfig(), for: sessionID)
        applyDefaults()

        syncSelectedTreatmentsToStore()

        sessionCoordinator.setSessionTypes(selectedTypes, for: sessionID)

        onDone?()
        dismiss()
    }

    func buildConfig() -> LocalDataStore.SessionConfig {
        let yardTrim = (selectedYard ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let yardOptional: String? = yardTrim.isEmpty ? nil : yardTrim

        let scanning = (scanningEnabled == true)
        let weighing = (weighingEnabled == true)

        return LocalDataStore.SessionConfig(
            farmID: selectedFarmID,
            farmName: resolvedFarmName,
            locationName: yardOptional,
            scanningEnabled: scanning,
            scannerType: scanning ? scannerType : nil,
            weighingEnabled: weighing,
            weightSource: weighing ? weightSource : nil,
            equipment: selectedEquipment.compactMap { LocalDataStore.SessionEquipment(rawValue: $0.rawValue.lowercased()) },
            tepariGunEnabled: tepariGunEnabled,
            recordTreatments: recordTreatments,
            recordLambsProduced: recordLambsProduced,
            recordFleeceWeight: recordFleeceWeight,
            recordStapleLength: recordStapleLength,
            recordMicron: recordMicron,
            recordCustom1: recordCustom1,
            recordCustom2: recordCustom2
        )
    }

    func applyDefaults() {
        store.setDefaultSex(selectedSex, for: sessionID)
        store.setDefaultClass(selectedClass, for: sessionID)

        store.setDefaultBreed(selectedBreed, for: sessionID)
        store.setDefaultBirthYear(selectedBirthYear, for: sessionID)
        store.setDefaultBirthMonth(selectedBirthMonth, for: sessionID)

        if let selectedStatus {
            store.setDefaultStatus(selectedStatus, for: sessionID)
        } else {
            store.clearDefaultStatus(for: sessionID)
        }

        let mobTrim = selectedMobName.trimmingCharacters(in: .whitespacesAndNewlines)
        if mobTrim.isEmpty || mobTrim == SessionSetupMobStepView.noneSentinel {
            store.setDefaultMobName(nil, for: sessionID)
        } else {
            // Mixed is stored as a session-level sentinel only.
            // Downstream animal update logic must preserve each animal's existing mob.
            store.setDefaultMobName(mobTrim, for: sessionID)
        }

        store.setOverwriteSexEnabled(overwriteSex, for: sessionID)
        store.setOverwriteClassEnabled(overwriteClass, for: sessionID)
    }
}

private extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
