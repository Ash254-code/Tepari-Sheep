import Foundation
import Combine

@MainActor
final class SessionViewModel: ObservableObject {

    // =====================================================
    // MARK: - Draft gate live summary
    // =====================================================

    struct DraftGateSummary: Equatable, Codable {
        let position: DraftPosition

        var count: Int = 0
        var totalWeightKg: Double = 0
        var minWeightKg: Double? = nil
        var maxWeightKg: Double? = nil

        var averageWeightKg: Double? {
            guard count > 0 else { return nil }
            return totalWeightKg / Double(count)
        }

        mutating func record(weight: Double?) {
            count += 1

            guard let weight, weight > 0 else { return }

            totalWeightKg += weight
            minWeightKg = min(minWeightKg ?? weight, weight)
            maxWeightKg = max(maxWeightKg ?? weight, weight)
        }

        mutating func reset() {
            count = 0
            totalWeightKg = 0
            minWeightKg = nil
            maxWeightKg = nil
        }
    }

    // =====================================================
    // MARK: - Quick trait draft setters (called from Views)
    // =====================================================

    func setDraftMicron(_ v: Double) {
        draftMicron = v
    }

    func setDraftStapleLengthMm(_ v: Int) {
        draftStapleLengthMm = v
    }

    func setDraftCustomTrait(id: String, value: String) {
        let trimmedKey = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        let trimmedVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVal.isEmpty {
            draftCustomTraits.removeValue(forKey: trimmedKey)
        } else {
            draftCustomTraits[trimmedKey] = trimmedVal
        }
    }

    // =====================================================
    // MARK: - Published UI State
    // =====================================================

    @Published var activeSession: Session
    @Published var connectionState: ConnectionState = .disconnected

    @Published var currentEID: String = "—"
    @Published var currentWeight: Double = 0

    @Published var isStable: Bool = false
    @Published var isLocked: Bool = false

    @Published var showDuplicatePrompt: Bool = false

    @Published private(set) var weighingEnabled: Bool = true
    @Published private(set) var draftingEnabled: Bool = false
    @Published private(set) var traitsEnabled: Bool = false

    @Published private(set) var recordMicronEnabled: Bool = true
    @Published private(set) var recordStapleEnabled: Bool = true
    @Published private(set) var recordCustom1Enabled: Bool = false
    @Published private(set) var recordCustom2Enabled: Bool = false

    @Published private(set) var nextDraftPosition: DraftPosition = .straight
    @Published private(set) var nextDraftRuleName: String? = nil

    @Published private(set) var draftLeftCount: Int = 0
    @Published private(set) var draftStraightCount: Int = 0
    @Published private(set) var draftRightCount: Int = 0
    @Published private(set) var draftFarRightCount: Int = 0

    @Published private(set) var draftLeftSummary: DraftGateSummary = .init(position: .left)
    @Published private(set) var draftStraightSummary: DraftGateSummary = .init(position: .straight)
    @Published private(set) var draftRightSummary: DraftGateSummary = .init(position: .right)
    @Published private(set) var draftFarRightSummary: DraftGateSummary = .init(position: .farRight)

    @Published private(set) var sessionTreatments: [SessionTreatment] = []
    @Published var selectedSessionTreatmentID: UUID? = nil
    @Published private(set) var calculatedDoseText: String? = nil

    // =====================================================
    // MARK: - Traits UI draft state (per current animal)
    // =====================================================

    @Published var draftMicron: Double? = nil
    @Published var draftStapleLengthMm: Int? = nil
    @Published var draftTraitClass: LocalDataStore.AnimalClass? = nil
    @Published var draftTraitNotes: String = ""

    @Published var draftCustomTraits: [String: String] = [:]

    @Published private(set) var micronQuickPicks: [Double] = []
    @Published private(set) var stapleQuickPicksMm: [Int] = []
    @Published private(set) var customTraitDefs: [LocalDataStore.CustomTraitDefinition] = []
    @Published private(set) var selectedDraftMode: DraftModeType? = nil

    func selectDraftMode(_ mode: DraftModeType) {
        selectedDraftMode = mode
    }

    // =====================================================
    // MARK: - Dependencies
    // =====================================================

    var store: LocalDataStore
    var settings: AppSettings
    var draftSettings: DraftSettings

    var draftEngine: DraftRuleEngine?
    var drafterController: DrafterController?

    var tepariGun: TepariGunManager?
    var gunListener: GunListener?

    // =====================================================
    // MARK: - Internals
    // =====================================================

    private let demo = DemoDataGenerator()
    private var timer: Timer?

    private var stableSince: Date? = nil
    private var lastStableFlag: Bool = false

    private var lastLockedEID: String?
    private var lastLockedWeight: Double?
    private var lockedWeightSnapshot: Double? = nil

    private var isDisplayHoldingLockedWeight: Bool = false
    private var lockedDisplayReleaseWorkItem: DispatchWorkItem? = nil
    private let lockedDisplayHoldSeconds: TimeInterval = 5.0

    private var zeroOffset: Double = 0
    private var lastRawWeight: Double = 0
    private var lastNetWeight: Double = 0

    private let scanSpeaker = SpeechAnnouncer()

    private var lastScanEID: String?
    private var lastScanTime: Date = .distantPast

    private var pendingDuplicateEID: String? = nil
    private var allowDuplicateOverwrite: Bool = false

    private var lastDraftFiredEID: String? = nil

    private var currentAnimalDraftCompleted: Bool = false
    private var currentAnimalTraitsCompleted: Bool = false
    private var currentAnimalPregCompleted: Bool = false
    private var currentAnimalTreatmentCompleted: Bool = false
    private var currentAnimalReleased: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    // =====================================================
    // MARK: - Inferred stability buffer
    // =====================================================

    private struct WeightSample {
        let t: Date
        let w: Double
    }

    private var weightSamples: [WeightSample] = []

    // =====================================================
    // MARK: - Init
    // =====================================================

    init(
        store: LocalDataStore,
        settings: AppSettings,
        draftSettings: DraftSettings,
        initialSession: Session,
        draftEngine: DraftRuleEngine? = nil,
        drafterController: DrafterController? = nil,
        tepariGun: TepariGunManager? = nil,
        gunListener: GunListener? = nil
    ) {
        self.store = store
        self.settings = settings
        self.draftSettings = draftSettings
        self.activeSession = initialSession
        self.draftEngine = draftEngine
        self.drafterController = drafterController
        self.tepariGun = tepariGun
        self.gunListener = gunListener

        syncDraftEngineGateMap()
        reloadDraftSetupFromStore()
        reloadTraitCapabilityFromSessionConfig()
        reloadTraitSettingsFromStore()
        reloadSessionTreatments()
        wireTraitsConfigNotifications()
    }

    // =====================================================
    // MARK: - Rebinding
    // =====================================================

    func rebind(
        store newStore: LocalDataStore,
        settings newSettings: AppSettings,
        draftSettings newDraftSettings: DraftSettings,
        tepariGun newTepariGun: TepariGunManager? = nil,
        gunListener newGunListener: GunListener? = nil
    ) {
        let storeChanged = ObjectIdentifier(self.store) != ObjectIdentifier(newStore)

        self.store = newStore
        self.settings = newSettings
        self.draftSettings = newDraftSettings
        self.tepariGun = newTepariGun
        self.gunListener = newGunListener

        syncDraftEngineGateMap()
        reloadDraftSetupFromStore()
        reloadTraitCapabilityFromSessionConfig()
        reloadTraitSettingsFromStore()
        reloadSessionTreatments()

        if storeChanged {
            wireTraitsConfigNotifications()
        }
    }

    // =====================================================
    // MARK: - Draft tab state
    // =====================================================

    private var totalDraftedCount: Int {
        draftLeftCount + draftStraightCount + draftRightCount + draftFarRightCount
    }

    private var inferredDraftMode: DraftModeType? {
        guard draftingEnabled else { return nil }

        let rules = draftEngine?.rules ?? []

        if rules.contains(where: { $0.minWeight != nil || $0.maxWeight != nil }) {
            return .weight
        }

        if rules.contains(where: { $0.mobID != nil }) {
            return .mob
        }

        if rules.contains(where: { ($0.klassEquals?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }) {
            return .animalClass
        }

        if activeSession.name.localizedCaseInsensitiveContains("preg") {
            return .pregHistory
        }

        return .weight
    }

    private var resolvedDraftMode: DraftModeType? {
        selectedDraftMode ?? inferredDraftMode
    }

    private var gateMappingSummaryLines: [String] {
        [
            "Empty → \(draftSettings.gateMap.empty.label)",
            "Single → \(draftSettings.gateMap.single.label)",
            "Twin → \(draftSettings.gateMap.twin.label)",
            "Keep → \(draftSettings.gateMap.keep.label)",
            "Cull → \(draftSettings.gateMap.cull.label)"
        ]
    }

    private var ruleSummaryLines: [String] {
        let rules = draftEngine?.rules ?? []
        guard !rules.isEmpty else { return [] }

        return rules.map { rule in
            let output: String
            if let logical = rule.logicalTarget {
                output = "\(logical.label) → \(rule.resolvedPosition(using: draftSettings.gateMap).label)"
            } else {
                output = rule.result.label
            }
            return "\(rule.name) → \(output)"
        }
    }

    private var draftSetupSummaryText: String {
        guard draftingEnabled else { return "Drafting not enabled in this session" }

        if let mode = resolvedDraftMode {
            return "\(mode.rawValue) drafting running from session rules"
        }

        return "Drafting running from session rules"
    }

    var draftTabState: DraftTabState {
        let total = totalDraftedCount
        let hasRules = !(draftEngine?.rules.isEmpty ?? true)

        return DraftTabState(
            setup: DraftSetupState(
                selectedMode: resolvedDraftMode,
                isConfigured: draftingEnabled || hasRules || resolvedDraftMode != nil,
                isActive: draftingEnabled,
                summaryText: draftSetupSummaryText,
                isExpanded: !draftingEnabled
            ),

            dashboard: DraftDashboardState(
                activeModeTitle: draftingEnabled ? "Active" : "Inactive",
                totalDrafted: total,
                gateSummaries: [
                    DraftDashboardGateSummary(
                        gate: 1,
                        count: draftLeftSummary.count,
                        averageWeightKg: draftLeftSummary.averageWeightKg,
                        minWeightKg: draftLeftSummary.minWeightKg,
                        maxWeightKg: draftLeftSummary.maxWeightKg
                    ),
                    DraftDashboardGateSummary(
                        gate: 2,
                        count: draftStraightSummary.count,
                        averageWeightKg: draftStraightSummary.averageWeightKg,
                        minWeightKg: draftStraightSummary.minWeightKg,
                        maxWeightKg: draftStraightSummary.maxWeightKg
                    ),
                    DraftDashboardGateSummary(
                        gate: 3,
                        count: draftRightSummary.count,
                        averageWeightKg: draftRightSummary.averageWeightKg,
                        minWeightKg: draftRightSummary.minWeightKg,
                        maxWeightKg: draftRightSummary.maxWeightKg
                    ),
                    DraftDashboardGateSummary(
                        gate: 4,
                        count: draftFarRightSummary.count,
                        averageWeightKg: draftFarRightSummary.averageWeightKg,
                        minWeightKg: draftFarRightSummary.minWeightKg,
                        maxWeightKg: draftFarRightSummary.maxWeightKg
                    )
                ],
                hasLiveData: total > 0
            ),

            advanced: DraftAdvancedState(
                isAvailable: true,
                gateMappingSummary: gateMappingSummaryLines,
                ruleSummary: ruleSummaryLines
            )
        )
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

    // =====================================================
    // MARK: - Draft engine sync
    // =====================================================

    private func syncDraftEngineGateMap() {
        draftEngine?.gateMap = draftSettings.gateMap
    }

    private func reloadDraftSetupFromStore() {
        syncDraftEngineGateMap()

        let setup = store.draftSetup(for: activeSession.id)

        draftingEnabled = setup.isEnabled
        selectedDraftMode = draftModeType(from: setup.mode)

        nextDraftPosition = .straight
        nextDraftRuleName = nil
        lastDraftFiredEID = nil

        guard let engine = draftEngine else { return }

        engine.gateMap = draftSettings.gateMap
        engine.defaultLogicalTarget = nil
        engine.defaultPosition = .straight

        switch setup.mode {
        case .off:
            engine.replaceAllRules([])

        case .byWeight:
            let rules: [DraftRule] = setup.weightRules.compactMap { row in
                let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty || row.minWeight != nil || row.maxWeight != nil else { return nil }

                return DraftRule(
                    name: name.isEmpty ? "Weight Rule" : name,
                    minWeight: row.minWeight,
                    maxWeight: row.maxWeight,
                    result: draftPosition(fromStoredValue: row.draftPositionRaw) ?? .straight,
                    logicalTarget: nil
                )
            }
            engine.replaceAllRules(rules)

        case .byMob:
            let rules: [DraftRule] = setup.mobRules.map { row in
                DraftRule(
                    name: row.mobName,
                    mobID: row.mobID,
                    result: draftPosition(fromStoredValue: row.draftPositionRaw) ?? .straight,
                    logicalTarget: nil
                )
            }
            engine.replaceAllRules(rules)

            if let fallback = draftPosition(fromFallbackChoice: setup.fallback) {
                engine.defaultPosition = fallback
            }

        case .byClass:
            let rules: [DraftRule] = setup.classRules.compactMap { row in
                let klass = row.animalClassRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !klass.isEmpty else { return nil }

                return DraftRule(
                    name: klass,
                    klassEquals: klass,
                    result: draftPosition(fromStoredValue: row.draftPositionRaw) ?? .straight,
                    logicalTarget: nil
                )
            }
            engine.replaceAllRules(rules)

            if let fallback = draftPosition(fromFallbackChoice: setup.fallback) {
                engine.defaultPosition = fallback
            }
        }
    }

    private func draftPosition(fromStoredValue rawValue: String) -> DraftPosition? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left":
            return .left
        case "straight":
            return .straight
        case "right":
            return .right
        case "hold", "farright", "far_right", "far right":
            return .farRight
        default:
            return nil
        }
    }

    private func draftPosition(fromFallbackChoice choice: DraftFallbackChoice) -> DraftPosition? {
        switch choice {
        case .keepCurrent:
            return nil
        case .left:
            return .left
        case .right:
            return .right
        }
    }

    // =====================================================
    // MARK: - Traits config notifications
    // =====================================================

    private func wireTraitsConfigNotifications() {
        cancellables.removeAll()

        NotificationCenter.default.publisher(for: LocalDataStore.traitsConfigChangedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reloadTraitCapabilityFromSessionConfig()
                self.reloadTraitSettingsFromStore()
            }
            .store(in: &cancellables)
    }

    // =====================================================
    // MARK: - Capability gates
    // =====================================================

    func setWeighingEnabled(_ enabled: Bool) {
        weighingEnabled = enabled

        if !enabled {
            cancelLockedDisplayRelease()
            isDisplayHoldingLockedWeight = false
            isLocked = false
            isStable = false
            lockedWeightSnapshot = nil
            stableSince = nil
            lastStableFlag = false
            weightSamples.removeAll()
            refreshCalculatedDose()
        }
    }

    func setDraftingEnabled(_ enabled: Bool) {
        draftingEnabled = enabled

        if enabled {
            reloadDraftSetupFromStore()
        } else {
            nextDraftPosition = .straight
            nextDraftRuleName = nil
            lastDraftFiredEID = nil
            draftEngine?.replaceAllRules([])
        }
    }

    func setTraitsEnabled(_ enabled: Bool) {
        traitsEnabled = enabled
        if enabled {
            reloadTraitCapabilityFromSessionConfig()
            reloadTraitSettingsFromStore()
        } else {
            clearTraitDraft()
        }
    }

    func resetDraftTotals() {
        draftLeftCount = 0
        draftStraightCount = 0
        draftRightCount = 0
        draftFarRightCount = 0

        draftLeftSummary.reset()
        draftStraightSummary.reset()
        draftRightSummary.reset()
        draftFarRightSummary.reset()

        lastDraftFiredEID = nil
        nextDraftPosition = .straight
        nextDraftRuleName = nil
    }

    // =====================================================
    // MARK: - Session Treatments + Dose
    // =====================================================

    var selectedSessionTreatment: SessionTreatment? {
        guard let id = selectedSessionTreatmentID else { return nil }
        return sessionTreatments.first(where: { $0.id == id })
    }

    var hasDoseReadyWeight: Bool {
        isDisplayHoldingLockedWeight || isLocked
    }

    func reloadSessionTreatments() {
        sessionTreatments = store.treatments(for: activeSession.id)

        if let selectedID = selectedSessionTreatmentID,
           sessionTreatments.contains(where: { $0.id == selectedID }) {
            // keep current selection
        } else {
            selectedSessionTreatmentID = sessionTreatments.first?.id
        }

        refreshCalculatedDose()
    }

    func selectSessionTreatment(id: UUID?) {
        selectedSessionTreatmentID = id
        refreshCalculatedDose()
    }

    func refreshCalculatedDose() {
        guard let treatment = selectedSessionTreatment else {
            calculatedDoseText = nil
            return
        }

        let effectiveWeight: Double = hasDoseReadyWeight ? currentWeight : 0
        calculatedDoseText = treatment.calculatedDoseString(forWeightKg: effectiveWeight)
    }

    // =====================================================
    // MARK: - Demo
    // =====================================================

    func startDemoIfNeeded() {
        guard settings.demoMode else { return }

        connectionState = .connected

        timer?.invalidate()
        let newTimer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let out = self.demo.next()
                self.ingest(eid: out.eid, weight: out.weight, stableFlag: out.stable)
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopDemo() {
        Task { @MainActor in
            timer?.invalidate()
            timer = nil
            connectionState = .disconnected
        }
    }

    // =====================================================
    // MARK: - Session
    // =====================================================

    func setSession(_ session: Session) {
        autoCommitTraitsIfNeeded()

        activeSession = session
        clearCurrent()
        resetDraftTotals()
        clearTraitDraft()

        syncDraftEngineGateMap()
        reloadDraftSetupFromStore()
        reloadTraitCapabilityFromSessionConfig()
        reloadTraitSettingsFromStore()
        reloadSessionTreatments()

        if settings.autoZeroOnSessionStart, weighingEnabled {
            zeroNow()
        }
    }

    func clearCurrent() {
        autoCommitTraitsIfNeeded()
        cancelLockedDisplayRelease()

        currentEID = "—"
        currentWeight = 0
        isStable = false
        isLocked = false
        isDisplayHoldingLockedWeight = false

        stableSince = nil
        lastStableFlag = false

        lastLockedEID = nil
        lastLockedWeight = nil
        lockedWeightSnapshot = nil

        showDuplicatePrompt = false

        zeroOffset = 0
        lastRawWeight = 0
        lastNetWeight = 0

        pendingDuplicateEID = nil
        allowDuplicateOverwrite = false

        weightSamples.removeAll()

        lastDraftFiredEID = nil
        nextDraftPosition = .straight
        nextDraftRuleName = nil

        currentAnimalDraftCompleted = false
        currentAnimalTraitsCompleted = false
        currentAnimalPregCompleted = false
        currentAnimalTreatmentCompleted = false
        currentAnimalReleased = false

        refreshCalculatedDose()
    }

    func reweigh() {
        guard weighingEnabled else { return }
        cancelLockedDisplayRelease()
        isLocked = false
        isDisplayHoldingLockedWeight = false
        lockedWeightSnapshot = nil
        stableSince = nil
        lastStableFlag = false
        weightSamples.removeAll()
        refreshCalculatedDose()
    }

    // =====================================================
    // MARK: - Zero
    // =====================================================

    func zeroNow() {
        guard weighingEnabled else { return }
        zeroOffset = lastRawWeight
        lastNetWeight = max(0, lastRawWeight - zeroOffset)
        if !isDisplayHoldingLockedWeight {
            currentWeight = 0
        }
        weightSamples.removeAll()
        refreshCalculatedDose()
    }

    // =====================================================
    // MARK: - Traits helpers
    // =====================================================

    private func reloadTraitCapabilityFromSessionConfig() {
        guard traitsEnabled else {
            recordMicronEnabled = false
            recordStapleEnabled = false
            recordCustom1Enabled = false
            recordCustom2Enabled = false
            return
        }

        guard let cfg = store.config(for: activeSession.id) else {
            recordMicronEnabled = true
            recordStapleEnabled = true
            recordCustom1Enabled = false
            recordCustom2Enabled = false
            return
        }

        recordMicronEnabled = cfg.recordMicron
        recordStapleEnabled = cfg.recordStapleLength
        recordCustom1Enabled = cfg.recordCustom1
        recordCustom2Enabled = cfg.recordCustom2
    }

    func reloadTraitSettingsFromStore() {
        micronQuickPicks = (traitsEnabled && recordMicronEnabled) ? store.traitsConfig.micronQuickPicks : []
        stapleQuickPicksMm = (traitsEnabled && recordStapleEnabled) ? store.traitsConfig.stapleLengthQuickPicksMm : []

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
                : .init(id: "custom2", label: "", kind: .number, quickPicks: [])
            )

        let out1: LocalDataStore.CustomTraitDefinition = recordCustom1Enabled
            ? .init(id: "custom1", label: c1.label, kind: c1.kind, quickPicks: c1.quickPicks)
            : .init(id: "custom1", label: "", kind: c1.kind, quickPicks: [])

        let out2: LocalDataStore.CustomTraitDefinition = recordCustom2Enabled
            ? .init(id: "custom2", label: c2.label, kind: c2.kind, quickPicks: c2.quickPicks)
            : .init(id: "custom2", label: "", kind: c2.kind, quickPicks: [])

        customTraitDefs = [out1, out2]
    }

    func clearTraitDraft() {
        draftMicron = nil
        draftStapleLengthMm = nil
        draftTraitClass = nil
        draftTraitNotes = ""
        draftCustomTraits = [:]
    }

    func loadTraitDraftFromLatestRecordIfExists() {
        guard traitsEnabled else { return }
        guard currentEID != "—", !currentEID.isEmpty else { return }
        // Intentionally blank for now.
    }

    private func autoCommitTraitsIfNeeded() {
        guard traitsEnabled else { return }
        guard currentEID != "—", !currentEID.isEmpty else { return }

        let hasContent =
            draftMicron != nil ||
            draftStapleLengthMm != nil ||
            draftTraitClass != nil ||
            !draftTraitNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !draftCustomTraits.isEmpty

        guard hasContent else { return }

        commitTraitsForCurrentAnimal()
    }

    func commitTraitsForCurrentAnimal() {
        guard traitsEnabled else { return }
        guard currentEID != "—", !currentEID.isEmpty else { return }
        if pendingDuplicateEID == currentEID && !allowDuplicateOverwrite { return }

        let cleanedNotes: String? = {
            let t = draftTraitNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }()

        let cleanedCustom: [String: String]? = {
            let pairs: [String: String] = draftCustomTraits.compactMapValues { raw in
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return pairs.isEmpty ? nil : pairs
        }()

        let fleece = cleanedCustom?["fleeceWeightKg"].flatMap(Double.init)

        _ = store.applyTraits(
            sessionID: activeSession.id,
            eidRaw: currentEID,
            micron: draftMicron,
            stapleLengthMm: draftStapleLengthMm,
            fleeceWeightKg: fleece,
            traitClass: draftTraitClass,
            notes: cleanedNotes,
            customTraits: cleanedCustom
        )

        currentAnimalTraitsCompleted = true

        if settings.audioEnabled {
            scanSpeaker.say("Saved")
        }

        attemptAutoReleaseIfReady()
    }

    func markTreatmentCompleted() {
        currentAnimalTreatmentCompleted = true
        attemptAutoReleaseIfReady()
    }

    // =====================================================
    // MARK: - Ingest
    // =====================================================

    func ingest(events: [TepariEvent]) {
        var eid: String?
        var weight: Double?
        var stable: Bool?

        for e in events {
            switch e {
            case .eid(let v): eid = v
            case .weight(let v): weight = v
            case .stable(let v): stable = v
            @unknown default:
                break
            }
        }

        ingest(
            eid: eid ?? "—",
            weight: weight ?? lastRawWeight,
            stableFlag: stable ?? false
        )
    }

    func ingest(eid: String, weight: Double, stableFlag: Bool) {
        let eidClean = EIDValidator.cleanedRaw(eid)
        lastRawWeight = weight

        let netWeight = max(0, weight - zeroOffset)
        lastNetWeight = netWeight

        if isDisplayHoldingLockedWeight, let snap = lockedWeightSnapshot {
            currentWeight = snap
        } else {
            let delta = abs(netWeight - currentWeight)
            let snapJump = max(0.0, settings.displaySnapJumpKg)
            let alpha = min(max(settings.displaySmoothingAlpha, 0.0), 1.0)

            if currentWeight == 0 || delta >= snapJump {
                currentWeight = netWeight
            } else {
                currentWeight = (currentWeight * (1.0 - alpha)) + (netWeight * alpha)
            }
        }

        refreshCalculatedDose()

        if !weighingEnabled {
            cancelLockedDisplayRelease()
            isDisplayHoldingLockedWeight = false
            isStable = false
            isLocked = false
            lockedWeightSnapshot = nil
            stableSince = nil
            lastStableFlag = false
            weightSamples.removeAll()
            refreshCalculatedDose()
            return
        }

        let isRapidRepeatSameEID =
            eidClean != "—" &&
            eidClean == lastScanEID &&
            Date().timeIntervalSince(lastScanTime) < 5.0

        if eidClean != "—", !isRapidRepeatSameEID {
            lastScanEID = eidClean
            lastScanTime = Date()
        }

        let isNewCurrentAnimal =
            eidClean != currentEID &&
            eidClean != "—" &&
            !isRapidRepeatSameEID

        let hasFreshEIDInThisEvent = eid != "—" && !eid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let isRepeatCurrentAnimal =
            hasFreshEIDInThisEvent &&
            eidClean == currentEID &&
            eidClean != "—" &&
            !isRapidRepeatSameEID

        if isNewCurrentAnimal {
            autoCommitTraitsIfNeeded()

            let wasDuplicateInSession = store.records(for: activeSession.id)
                .contains { $0.eidRaw == eidClean }

            let farmID = store.sessionFarmID[activeSession.id]
            let knownAnimal = (farmID != nil)
                ? (store.animalProfile(farmID: farmID!, eidRaw: eidClean) != nil)
                : false

            currentEID = eidClean
            resetScanState()
            refreshCalculatedDose()

            if traitsEnabled {
                clearTraitDraft()
                loadTraitDraftFromLatestRecordIfExists()
            }

            let scannedClassName: String? = {
                guard let farmID else { return nil }
                return resolvedAnimalClassNameForScan(eid: eidClean, farmID: farmID)
            }()

            if let farmID {
                applyAnimalDefaults(eid: eidClean, farmID: farmID)
            }

            if draftingEnabled {
                evaluateDraftDecisionForCurrentAnimal()
            } else {
                nextDraftPosition = .straight
                nextDraftRuleName = nil
            }

            if wasDuplicateInSession {
                AudioManager.shared.playTrigger(.rescanInSession, settings: settings)
            } else if knownAnimal {
                AudioManager.shared.playTrigger(.scanSuccessful, settings: settings)
            } else {
                AudioManager.shared.playTrigger(.newAnimal, settings: settings)
            }

            if let scannedClassName {
                AudioManager.shared.playTrigger(
                    .animalClassAnnouncement,
                    settings: settings,
                    className: scannedClassName
                )
            }
            if wasDuplicateInSession {
                pendingDuplicateEID = eidClean
                showDuplicatePrompt = true
            }

            if wasDuplicateInSession && !allowDuplicateOverwrite {
                return
            }

            handleNonWeighingSessionActionOnScan(
                eid: eidClean,
                wasDuplicateInSession: wasDuplicateInSession
            )

            if draftingEnabled && !weighingEnabled {
                fireDraftIfNeeded(
                    eid: eidClean,
                    position: nextDraftPosition,
                    weight: nil
                )

                store.applyDraftResult(
                    sessionID: activeSession.id,
                    eidRaw: eidClean,
                    draftResult: nextDraftPosition,
                    matchedRuleName: nextDraftRuleName
                )

                attemptAutoReleaseIfReady()
            }
        } else if isRepeatCurrentAnimal {
            let wasDuplicateInSession = store.records(for: activeSession.id)
                .contains { $0.eidRaw == eidClean }

            if wasDuplicateInSession {
                AudioManager.shared.playTrigger(.rescanInSession, settings: settings)
                pendingDuplicateEID = eidClean
                showDuplicatePrompt = true

                if !allowDuplicateOverwrite {
                    return
                }
            }
        }

        guard currentEID != "—" else {
            isStable = false
            refreshCalculatedDose()
            return
        }

        if isLocked {
            isStable = true
            refreshCalculatedDose()
            return
        }

        pushWeightSample(lastNetWeight)

        let inferred = inferredStableNow()
        let effectiveStable = settings.effectiveStable(
            scaleStable: stableFlag,
            inferredStable: inferred
        )

        isStable = effectiveStable

        if pendingDuplicateEID == currentEID && !allowDuplicateOverwrite {
            return
        }

        handleStableLock(stableFlag: effectiveStable)
    }

    private func resetScanState() {
        cancelLockedDisplayRelease()
        isLocked = false
        isDisplayHoldingLockedWeight = false
        lockedWeightSnapshot = nil
        stableSince = nil
        lastStableFlag = false
        lastLockedEID = nil
        lastLockedWeight = nil
        pendingDuplicateEID = nil
        allowDuplicateOverwrite = false
        weightSamples.removeAll()

        currentAnimalDraftCompleted = false
        currentAnimalTraitsCompleted = false
        currentAnimalPregCompleted = false
        currentAnimalTreatmentCompleted = false
        currentAnimalReleased = false
    }

    private func cancelLockedDisplayRelease() {
        lockedDisplayReleaseWorkItem?.cancel()
        lockedDisplayReleaseWorkItem = nil
    }

    private func scheduleLockedDisplayRelease() {
        cancelLockedDisplayRelease()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isDisplayHoldingLockedWeight = false
            self.lockedWeightSnapshot = nil
            self.refreshCalculatedDose()
        }

        lockedDisplayReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + lockedDisplayHoldSeconds, execute: workItem)
    }

    // =====================================================
    // MARK: - Draft decision + firing
    // =====================================================

    private func evaluateDraftDecisionForCurrentAnimal() {
        let eid = currentEID
        guard eid != "—", !eid.isEmpty else { return }

        syncDraftEngineGateMap()

        let farmID = store.sessionFarmID[activeSession.id]

        if let engine = draftEngine {
            let eval = engine.evaluateDetailed(
                eid: eid,
                weight: currentWeight,
                store: store,
                farmID: farmID
            )

            if let logical = eval.logicalTarget {
                nextDraftPosition = draftSettings.gateMap.physical(for: logical)
            } else {
                nextDraftPosition = eval.position
            }

            nextDraftRuleName = eval.matchedRuleName
        } else {
            nextDraftPosition = .straight
            nextDraftRuleName = nil
        }
    }

    private func fireDraftIfNeeded(eid: String, position: DraftPosition, weight: Double?) {
        guard draftingEnabled || drafterController != nil else { return }
        guard eid != "—", !eid.isEmpty else { return }
        guard lastDraftFiredEID != eid else { return }

        lastDraftFiredEID = eid
        currentAnimalDraftCompleted = true
        currentAnimalReleased = false

        drafterController?.draftAnimal(to: position)
        playGateAudio(for: position)
        bumpDraftTotals(for: position, weight: weight)
    }

    private func playGateAudio(for position: DraftPosition) {
        let trigger: SpeechTrigger

        switch position {
        case .left:
            trigger = .gate1
        case .straight:
            trigger = .gate2
        case .right:
            trigger = .gate3
        case .farRight:
            trigger = .gate4
        }

        AudioManager.shared.playTrigger(trigger, settings: settings)
    }

    private func bumpDraftTotals(for pos: DraftPosition, weight: Double?) {
        switch pos {
        case .left:
            draftLeftCount += 1
            draftLeftSummary.record(weight: weight)

        case .straight:
            draftStraightCount += 1
            draftStraightSummary.record(weight: weight)

        case .right:
            draftRightCount += 1
            draftRightSummary.record(weight: weight)

        case .farRight:
            draftFarRightCount += 1
            draftFarRightSummary.record(weight: weight)
        }
    }

    // =====================================================
    // MARK: - Preg Test Manual Draft
    // =====================================================

    func manualPregDraft(fetusCount: Int) {
        let eid = currentEID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard eid != "—", !eid.isEmpty else { return }

        let logical: DraftLogicalTarget
        switch fetusCount {
        case 0: logical = .empty
        case 1: logical = .single
        case 2: logical = .twin
        default: return
        }

        let position = draftSettings.gateMap.physical(for: logical)

        store.savePregDraft(
            sessionID: activeSession.id,
            eidRaw: eid,
            fetusCount: fetusCount,
            draftPosition: position
        )

        guard draftingEnabled || drafterController != nil else { return }
        guard lastDraftFiredEID != eid else { return }

        lastDraftFiredEID = eid
        currentAnimalDraftCompleted = true
        currentAnimalPregCompleted = true
        currentAnimalReleased = false

        drafterController?.draftAnimal(logical: logical, using: draftSettings.gateMap)
        playGateAudio(for: position)

        nextDraftPosition = position
        nextDraftRuleName = "Preg Test"
        bumpDraftTotals(for: position, weight: currentWeight > 0 ? currentWeight : nil)

        attemptAutoReleaseIfReady()
    }

    // =====================================================
    // MARK: - APPLY DEFAULTS
    // =====================================================

    private func resolvedAnimalClassNameForScan(eid: String, farmID: UUID) -> String? {
        let resolvedClass = store.resolvedClassForScan(
            sessionID: activeSession.id,
            farmID: farmID,
            eidRaw: eid
        )

        let raw = String(describing: resolvedClass).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let lowered = raw.lowercased()
        if lowered == "none" || lowered == "unknown" || lowered == "nil" {
            return nil
        }

        return raw
    }

    private func applyAnimalDefaults(eid: String, farmID: UUID) {
        let resolvedSex = store.resolvedSexForScan(
            sessionID: activeSession.id,
            farmID: farmID,
            eidRaw: eid
        )

        let resolvedClass = store.resolvedClassForScan(
            sessionID: activeSession.id,
            farmID: farmID,
            eidRaw: eid
        )

        let resolvedMobID = store.resolvedMobIDForScan(
            sessionID: activeSession.id,
            farmID: farmID,
            eidRaw: eid
        )

        let isMixedMobSession = store.isMixedMobSession(activeSession.id)

        let resolvedBreed = store.defaultBreed(for: activeSession.id).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBirthYear = store.defaultBirthYear(for: activeSession.id)
        let resolvedBirthMonth = store.defaultBirthMonth(for: activeSession.id)
        let resolvedStatus = store.defaultStatus(for: activeSession.id)

        if var existing = store.animalProfile(farmID: farmID, eidRaw: eid) {
            store.updateAnimalSex(farmID: farmID, eidRaw: eid, sex: resolvedSex)
            store.updateAnimalClass(farmID: farmID, eidRaw: eid, animalClass: resolvedClass)

            if !isMixedMobSession {
                let overwriteMob = store.overwriteMobEnabled(for: activeSession.id)
                let shouldApplyMob = overwriteMob || existing.mobID == nil

                if shouldApplyMob, let mobID = resolvedMobID, mobID != existing.mobID {
                    existing.mobID = mobID
                    store.upsertAnimal(existing)
                }

                if let mobID = resolvedMobID {
                    store.setSessionMob(sessionID: activeSession.id, mobID: mobID)
                }
            }

            if !resolvedBreed.isEmpty {
                store.updateAnimalBreedIfBlank(farmID: farmID, eidRaw: eid, breed: resolvedBreed)
            }

            if let y = resolvedBirthYear {
                store.updateAnimalBirthYearIfBlank(farmID: farmID, eidRaw: eid, year: y)
            }

            if let m = resolvedBirthMonth {
                store.updateAnimalBirthMonthIfBlank(farmID: farmID, eidRaw: eid, month: m)
            }

            if let resolvedStatus {
                store.updateAnimalStatusIfBlank(farmID: farmID, eidRaw: eid, status: resolvedStatus)
            }

            return
        }

        let profile = LocalDataStore.AnimalProfile(
            farmID: farmID,
            eidRaw: eid,
            mobID: isMixedMobSession ? nil : resolvedMobID,
            sex: resolvedSex,
            animalClass: resolvedClass
        )

        store.upsertAnimal(profile)

        if !resolvedBreed.isEmpty {
            store.updateAnimalBreedIfBlank(farmID: farmID, eidRaw: eid, breed: resolvedBreed)
        }
        if let y = resolvedBirthYear {
            store.updateAnimalBirthYearIfBlank(farmID: farmID, eidRaw: eid, year: y)
        }
        if let m = resolvedBirthMonth {
            store.updateAnimalBirthMonthIfBlank(farmID: farmID, eidRaw: eid, month: m)
        }
        if let resolvedStatus {
            store.updateAnimalStatusIfBlank(farmID: farmID, eidRaw: eid, status: resolvedStatus)
        }

        if !isMixedMobSession, let mobID = resolvedMobID {
            store.setSessionMob(sessionID: activeSession.id, mobID: mobID)
        }
    }

    // =====================================================
    // MARK: - Non-weighing session actions
    // =====================================================

    private func handleNonWeighingSessionActionOnScan(eid: String, wasDuplicateInSession: Bool) {
        guard let cfg = store.config(for: activeSession.id) else { return }

        switch cfg.sessionKind {
        case .general:
            return

        case .transfer:
            _ = store.applyTransfer(sessionID: activeSession.id, eidRaw: eid)
            if settings.audioEnabled { scanSpeaker.say("Transferred") }

        case .sale:
            _ = store.applySale(sessionID: activeSession.id, eidRaw: eid)
            if settings.audioEnabled { scanSpeaker.say("Sold") }
        }
    }

    // =====================================================
    // MARK: - Inferred stability logic
    // =====================================================

    private func pushWeightSample(_ w: Double) {
        let now = Date()
        weightSamples.append(.init(t: now, w: w))
        let cutoff = now.addingTimeInterval(-3.0)
        weightSamples.removeAll { $0.t < cutoff }
    }

    private func inferredStableNow() -> Bool {
        guard lastNetWeight > 0 else { return false }

        let windowSec = max(0.1, Double(settings.inferredStableWindowMs) / 1000.0)
        let cutoff = Date().addingTimeInterval(-windowSec)
        let slice = weightSamples.filter { $0.t >= cutoff }

        guard slice.count >= 2 else { return false }

        var minW = slice[0].w
        var maxW = slice[0].w

        for s in slice {
            minW = min(minW, s.w)
            maxW = max(maxW, s.w)
        }

        return (maxW - minW) <= max(0.0, settings.inferredStableMaxDeltaKg)
    }

    // =====================================================
    // MARK: - Stable hold + lock
    // =====================================================

    private func handleStableLock(stableFlag: Bool) {
        guard !isLocked else { return }
        guard currentEID != "—" else { return }
        guard lastNetWeight > 0 else { return }

        if stableFlag {
            if !lastStableFlag {
                stableSince = Date()
            }

            let hold = Double(settings.stableHoldMilliseconds) / 1000.0

            if let since = stableSince,
               Date().timeIntervalSince(since) >= hold {

                let roundedNet = (lastNetWeight * 10.0).rounded() / 10.0

                if lastLockedEID == currentEID,
                   lastLockedWeight == roundedNet {
                    return
                }

                lockWeight()
            }
        } else {
            stableSince = nil
        }

        lastStableFlag = stableFlag
    }

    // =====================================================
    // MARK: - Lock + save
    // =====================================================

    private func lockWeight() {
        let source = lastNetWeight > 0 ? lastNetWeight : currentWeight
        let locked = (source * 10.0).rounded() / 10.0

        cancelLockedDisplayRelease()

        lockedWeightSnapshot = locked
        isDisplayHoldingLockedWeight = true
        currentWeight = locked
        isStable = true
        isLocked = true

        stableSince = nil
        lastStableFlag = true

        reloadSessionTreatments()

        store.addOrOverwriteRecord(
            sessionID: activeSession.id,
            eidRaw: currentEID,
            lockedWeight: locked,
            treatments: sessionTreatments
        )

        if draftingEnabled {
            evaluateDraftDecisionForCurrentAnimal()
        }

        let lockedEID = currentEID
        let lockedDraftPosition = nextDraftPosition
        let lockedDraftRuleName = nextDraftRuleName
        let shouldDraft = draftingEnabled

        let delay = max(0, Double(settings.weightOKSpeakDelayMs) / 1000.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }

            AudioManager.shared.playTrigger(.weightRecorded, settings: self.settings)

            guard shouldDraft else { return }

            self.fireDraftIfNeeded(
                eid: lockedEID,
                position: lockedDraftPosition,
                weight: locked
            )

            self.store.applyDraftResult(
                sessionID: self.activeSession.id,
                eidRaw: lockedEID,
                draftResult: lockedDraftPosition,
                matchedRuleName: lockedDraftRuleName
            )

            self.attemptAutoReleaseIfReady()
        }

        lastLockedEID = currentEID
        lastLockedWeight = locked

        refreshCalculatedDose()
        sendCalculatedDoseToGunIfPossible(forLockedWeightKg: locked)
        scheduleLockedDisplayRelease()
    }

    private func sendCalculatedDoseToGunIfPossible(forLockedWeightKg lockedWeightKg: Double) {
        guard let tepariGun else { return }
        guard tepariGun.isEnabled else { return }

        guard currentEID != "—", !currentEID.isEmpty else { return }
        guard let treatment = selectedSessionTreatment else { return }
        guard let doseML = treatment.calculatedDose(forWeightKg: lockedWeightKg) else { return }
        guard doseML > 0 else { return }

        let tenths = Int((doseML * 10.0).rounded())
        guard tenths > 0, tenths <= 999 else { return }

        let packet = String(format: "<%03d>", tenths)

        if tepariGun.connectionMode == .listener {
            gunListener?.sendRaw(packet)
        } else {
            tepariGun.sendRawCommand(packet)
        }
    }

    // =====================================================
    // MARK: - Auto release helpers
    // =====================================================

    private func attemptAutoReleaseIfReady() {
        guard draftSettings.isAutoReleaseOn else { return }
        guard currentEID != "—", !currentEID.isEmpty else { return }
        guard currentAnimalDraftCompleted else { return }

        if traitsEnabled && !currentAnimalTraitsCompleted {
            return
        }

        if !sessionTreatments.isEmpty && !currentAnimalTreatmentCompleted {
            return
        }

        if resolvedDraftMode == .pregHistory && !currentAnimalPregCompleted {
            return
        }

        currentAnimalReleased = true
        drafterController?.releaseNow()
    }

    // =====================================================
    // MARK: - Duplicate handling
    // =====================================================

    func confirmOverwriteDuplicate() {
        allowDuplicateOverwrite = true
        pendingDuplicateEID = nil
        showDuplicatePrompt = false

        cancelLockedDisplayRelease()
        stableSince = nil
        lastStableFlag = false
        isLocked = false
        isDisplayHoldingLockedWeight = false
        lockedWeightSnapshot = nil
        weightSamples.removeAll()

        lastDraftFiredEID = nil
        currentAnimalDraftCompleted = false
        currentAnimalTraitsCompleted = false
        currentAnimalPregCompleted = false
        currentAnimalTreatmentCompleted = false
        currentAnimalReleased = false
        refreshCalculatedDose()
    }

    func cancelDuplicateFlow() {
        showDuplicatePrompt = false
        pendingDuplicateEID = nil
        allowDuplicateOverwrite = false
        clearCurrent()
        clearTraitDraft()
    }
}
