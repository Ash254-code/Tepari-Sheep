import SwiftUI
import UIKit

private let kEnableStapleMeasureKey = "enable_staple_measure"

struct SessionView: View {
    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var sessionCoordinator: ActiveSessionCoordinator
    @EnvironmentObject private var drafter: DrafterController
    @EnvironmentObject private var draftSettings: DraftSettings
    @EnvironmentObject private var dock: SessionDockModel
    @EnvironmentObject private var gunListener: GunListener
    @EnvironmentObject private var tepariGun: TepariGunManager
    @EnvironmentObject private var presetStore: TreatmentPresetStore
    @EnvironmentObject private var vm: SessionViewModel

    @StateObject private var phoneFallbackDock = SessionDockModel()

    let store: LocalDataStore
    let settings: AppSettings
    let onGoToDraftTab: () -> Void

    @State private var showWeighMode = false
    @State private var showZeroConfirmation = false
    @State private var showDetails = false
    @State private var showHistory = false
    @State private var showTreatmentSetup = false
    @State private var showTreatmentsEditor = false
    @State private var heroPulse = false
    @State private var showStapleTest = false
    @State private var showRestartAlert = false
    @State private var sessionToRestart: Session? = nil

    @State private var editorRecordTreatments: Bool = true
    @State private var editorSelectedTreatmentIDs: Set<UUID> = []
    @State private var editorDoseOverrides: [UUID: DoseValue] = [:]
    @State private var editorTepariGunEnabled: Bool = false
    @State private var editorTepariTreatmentID: UUID? = nil

    @State private var showRecentAnimalsFullScreen = false

    @AppStorage(kEnableStapleMeasureKey) private var enableStapleMeasure = false
    @AppStorage("drafter_pause_relay_latched") private var isDraftPaused = false

    init(
        store: LocalDataStore,
        settings: AppSettings,
        onGoToDraftTab: @escaping () -> Void = {}
    ) {
        self.store = store
        self.settings = settings
        self.onGoToDraftTab = onGoToDraftTab
    }

    private var isPhone: Bool { Device.isPhone }

    private var activeDockModel: SessionDockModel {
        isPhone ? phoneFallbackDock : dock
    }

    private var isTCPConnected: Bool {
        transport.method == .tcp && transport.state == .connected
    }

    private var scannerConnected: Bool {
        transport.method == .ble && transport.state == .connected
    }

    private var scaleConnected: Bool {
        transport.method == .tcp && transport.state == .connected
    }

    private var scannedCount: Int {
        store.records(for: vm.activeSession.id).count
    }

    private var sessionsSortedNewestFirst: [Session] {
        store.sessions.sorted { $0.createdAt > $1.createdAt }
    }

    private var recentSessions: [Session] {
        Array(sessionsSortedNewestFirst.prefix(3))
    }

    private var lastSession: Session? {
        sessionsSortedNewestFirst.first
    }

    private var activeTypes: Set<SetupSessionType> {
        let live = sessionCoordinator.activeSessionTypes
        if !live.isEmpty {
            return live
        }

        guard sessionCoordinator.hasActiveSession else { return [] }
        return inferredTypes(from: store.config(for: vm.activeSession.id))
    }

    private var layoutKind: SessionLayoutKind {
        SessionLayoutKind.from(types: activeTypes)
    }

    private var configuredTreatmentCount: Int {
        guard sessionCoordinator.hasActiveSession else { return 0 }
        return store.treatments(for: vm.activeSession.id).count
    }

    private var hasActiveSession: Bool {
        sessionCoordinator.activeSessionID != nil
    }

    private var canReweigh: Bool {
        hasActiveSession && isTCPConnected && vm.currentEID != "—"
    }

    private var currentSessionHasTreatments: Bool {
        configuredTreatmentCount > 0
    }

    private var layoutSupportsPauseRelay: Bool {
        switch layoutKind {
        case .weighDraft, .scanWeighDraft, .scanWeighTreatDraft, .draftOnly, .scanDraft, .pregTestDraft:
            return true
        default:
            return false
        }
    }

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

    private func updateTraitsEnabledState() {
        guard sessionCoordinator.hasActiveSession else {
            vm.setTraitsEnabled(false)
            vm.setDraftingEnabled(false)
            vm.setWeighingEnabled(false)
            return
        }

        let cfg = store.config(for: vm.activeSession.id)

        let anyTraitFieldsEnabled =
        (cfg?.recordMicron ?? false) ||
        (cfg?.recordStapleLength ?? false) ||
        (cfg?.recordCustom1 ?? false) ||
        (cfg?.recordCustom2 ?? false)

        vm.setTraitsEnabled(
            activeTypes.contains(.traitInput) || anyTraitFieldsEnabled
        )

        vm.setDraftingEnabled(
            activeTypes.contains(.draft)
        )

        vm.setWeighingEnabled(
            (cfg?.weighingEnabled ?? false) ||
            activeTypes.contains(.weigh) ||
            activeTypes.contains(.fleeceWeigh)
        )
    }

    var body: some View {
        let baseContent =
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            if sessionCoordinator.activeSessionID == nil {
                GeometryReader { _ in
                    noActiveSessionCard
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                switch layoutKind {

                case .weighDraft:
                    SessionLayoutWeighDraftView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showWeighMode: $showWeighMode,
                        showZeroConfirmation: $showZeroConfirmation,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        isTCPConnected: isTCPConnected,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() },
                        onGoToDraftTab: { onGoToDraftTab() }
                    )

                case .scanWeigh:
                    SessionLayoutScanWeighView(
                        vm: vm,
                        showWeighMode: $showWeighMode,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount
                    )

                case .scanWeighTreat:
                    SessionLayoutScanWeighTreatView(
                        vm: vm,
                        showWeighMode: $showWeighMode,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onOpenTreatments: { showTreatmentsEditor = true }
                    )

                case .scanWeighDraft:
                    SessionLayoutScanWeighDraftView(
                        vm: vm,
                        showWeighMode: $showWeighMode,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onGoToDraftTab: { onGoToDraftTab() }
                    )

                case .scanWeighTreatDraft:
                    if let draftEngine = vm.draftEngine {
                        SessionLayoutScanWeighTreatDraftView(
                            vm: vm,
                            activeTypes: activeTypes,
                            showWeighMode: $showWeighMode,
                            showZeroConfirmation: $showZeroConfirmation,
                            showDetails: $showDetails,
                            isPhone: isPhone,
                            isTCPConnected: isTCPConnected,
                            scannedCount: scannedCount,
                            onStartNewSession: { startNewSession() },
                            onSyncCoordinator: { syncCoordinator() },
                            onOpenTreatments: { showTreatmentsEditor = true },
                            onGoToDraftTab: { onGoToDraftTab() }
                        )
                        .environmentObject(draftEngine)
                    } else {
                        SessionLayoutScanWeighTreatDraftView(
                            vm: vm,
                            activeTypes: activeTypes,
                            showWeighMode: $showWeighMode,
                            showZeroConfirmation: $showZeroConfirmation,
                            showDetails: $showDetails,
                            isPhone: isPhone,
                            isTCPConnected: isTCPConnected,
                            scannedCount: scannedCount,
                            onStartNewSession: { startNewSession() },
                            onSyncCoordinator: { syncCoordinator() },
                            onOpenTreatments: { showTreatmentsEditor = true },
                            onGoToDraftTab: { onGoToDraftTab() }
                        )
                    }

                case .draftOnly:
                    SessionLayoutWeighDraftView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showWeighMode: $showWeighMode,
                        showZeroConfirmation: $showZeroConfirmation,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        isTCPConnected: isTCPConnected,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() },
                        onGoToDraftTab: { onGoToDraftTab() }
                    )

                case .scanDraft:
                    SessionLayoutScanDraftView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() }
                    )

                case .scanTraits:
                    SessionLayoutTraitInputView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        onStartNewSession: { startNewSession() }
                    )

                case .scanTreat:
                    SessionLayoutScanTreatView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showZeroConfirmation: $showZeroConfirmation,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() },
                        onOpenTreatments: { showTreatmentsEditor = true }
                    )

                case .scanOnly:
                    SessionLayoutScanView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() }
                    )

                case .treatOnly:
                    SessionLayoutTreatmentView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() }
                    )

                case .transferSaleForm:
                    SessionLayoutTransferSaleView(
                        vm: vm,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() }
                    )

                case .pregTestDraft:
                    SessionLayoutPregTestDraftView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() },
                        onOpenTreatments: { showTreatmentsEditor = true }
                    )

                case .fleeceWeigh:
                    SessionLayoutFleeceWeighView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() },
                        onCaptureFleeceWeight: { eidRaw, kg in
                            store.upsertRecord(
                                sessionID: vm.activeSession.id,
                                eidRaw: eidRaw,
                                defaultLockedWeight: 0,
                                defaultTreatments: [],
                                updateRecordedAt: true
                            ) { rec in
                                rec.customTraits = (rec.customTraits ?? [:])
                                    .merging(["fleeceKg": String(format: "%.2f", kg)]) { _, new in new }
                            }
                        },
                        onOpenTreatments: { showTreatmentsEditor = true }
                    )

                case .lambMarking, .lambMarkingTreatTrait:
                    SessionLayoutLambMarkingTreatTraitView(
                        vm: vm,
                        activeTypes: activeTypes,
                        showDetails: $showDetails,
                        isPhone: isPhone,
                        scannedCount: scannedCount,
                        onStartNewSession: { startNewSession() },
                        onSyncCoordinator: { syncCoordinator() },
                        onOpenTreatments: { showTreatmentsEditor = true }
                    )
                }
            }
        }

        let decorated =
        baseContent
            .overlay(alignment: .topTrailing) {
                if enableStapleMeasure {
                    Button {
                        showStapleTest = true
                    } label: {
                        Image(systemName: "ruler")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.82))
                            .clipShape(Circle())
                            .shadow(radius: 6)
                    }
                    .padding(.trailing, 14)
                    .padding(.top, 14)
                    .opacity(0.95)
                }
            }
            .overlay(alignment: .top) {
                if showZeroConfirmation {
                    Text("Scale zeroed")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation { showZeroConfirmation = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showStapleTest) {
                NavigationStack {
                    StapleLengthTestView()
                        .navigationTitle("Staple Test")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showStapleTest = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $sessionCoordinator.showIndividualAnimalView, onDismiss: {
                sessionCoordinator.closeIndividualAnimal()
            }) {
                IndividualAnimalView()
                    .environmentObject(store)
                    .environmentObject(sessionCoordinator)
            }
            .fullScreenCover(isPresented: $showTreatmentSetup) {
                SessionSetupView(sessionID: vm.activeSession.id) {
                    sessionCoordinator.startSession(id: vm.activeSession.id)
                    syncCoordinator()
                }
            }
            .fullScreenCover(isPresented: $showWeighMode) {
                WeighModeView(
                    eid: vm.currentEID,
                    weight: Decimal(vm.currentWeight),
                    locked: vm.isLocked,
                    stable: vm.isStable
                )
            }
            .fullScreenCover(isPresented: $showRecentAnimalsFullScreen) {
                SessionRecentAnimalsFullScreenView()
                    .environmentObject(store)
                    .environmentObject(sessionCoordinator)
            }
            .onAppear {
                vm.rebind(
                    store: store,
                    settings: settings,
                    draftSettings: draftSettings,
                    tepariGun: tepariGun,
                    gunListener: gunListener
                )
                vm.drafterController = drafter
                vm.draftEngine?.gateMap = draftSettings.gateMap

                if let activeID = sessionCoordinator.activeSessionID,
                   let existing = store.sessions.first(where: { $0.id == activeID }),
                   vm.activeSession.id != existing.id {
                    vm.setSession(existing)

                    if sessionCoordinator.wasJustRestarted(activeID) {
                        resetForRestartedSession()
                        sessionCoordinator.consumeRestartFlag(for: activeID)
                    }

                    syncCoordinator()
                }

                updateTraitsEnabledState()

                if transport.method == .demo {
                    vm.startDemoIfNeeded()
                } else {
                    vm.stopDemo()
                }


                configureDockIfNeeded()
                updateDockState()
            }
            .onChange(of: transport.method) { _, m in
                if m == .demo {
                    vm.startDemoIfNeeded()
                } else {
                    vm.stopDemo()
                }
                updateDockState()
            }
            .onChange(of: sessionCoordinator.activeSessionTypes) { _, _ in
                updateTraitsEnabledState()
                updateDockState()
            }
            .onChange(of: sessionCoordinator.activeSessionID) { oldID, newID in
                if oldID != nil && newID == nil {
                    endDraftHardwareState()
                }

                updateTraitsEnabledState()
                updateDockState()

                if let newID,
                   let existing = store.sessions.first(where: { $0.id == newID }) {
                    vm.setSession(existing)

                    if sessionCoordinator.wasJustRestarted(newID) {
                        resetForRestartedSession()
                        sessionCoordinator.consumeRestartFlag(for: newID)
                    }

                    syncCoordinator()
                }

            }
            .onChange(of: scannedCount) { _, _ in
                updateDockState()
            }
            .onChange(of: showDetails) { _, _ in
                updateDockState()
            }
            .onChange(of: draftSettings.gateMap) { _, newMap in
                vm.draftEngine?.gateMap = newMap
            }
            .onChange(of: isDraftPaused) { _, _ in
                updateDockState()
            }
            .alert("Duplicate EID Detected", isPresented: $vm.showDuplicatePrompt) {
                Button("Overwrite") { vm.confirmOverwriteDuplicate() }
                Button("Cancel", role: .cancel) { vm.cancelDuplicateFlow() }
            } message: {
                Text("This animal has already been scanned in this session. Overwrite the previous record?")
            }
            .alert("Restart Session?", isPresented: $showRestartAlert, presenting: sessionToRestart) { session in
                Button("Cancel", role: .cancel) { }

                Button("Yes") {
                    performRestart(session)
                }
            } message: { _ in
                Text("Would you like to restart this session?")
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    SessionHistoryListView(
                        sessions: sessionsSortedNewestFirst,
                        onSelect: { s in
                            promptRestart(s)
                        },
                        onNewSession: { startNewSession() },
                        onDelete: { s in
                            store.deleteSession(s)
                            if sessionCoordinator.activeSessionID == s.id {
                                sessionCoordinator.activeSessionID = nil
                            }
                        }
                    )
                    .navigationTitle("Recent Sessions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showHistory = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showTreatmentsEditor, onDismiss: {
                vm.reloadSessionTreatments()
                updateDockState()
            }) {
                NavigationStack {
                    SessionSetupTreatmentsStepView(
                        tepariGunEnabled: $editorTepariGunEnabled,
                        tepariTreatmentID: $editorTepariTreatmentID,
                        onTepariChanged: { _ in },
                        recordTreatments: $editorRecordTreatments,
                        treatmentLibrary: treatmentLibrary,
                        selectedTreatmentIDs: $editorSelectedTreatmentIDs,
                        doseOverrides: $editorDoseOverrides,
                        onAddTreatmentTemplate: { _ in },
                        onSelectionChanged: {}
                    )
                    .navigationTitle("Treatments")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showTreatmentsEditor = false
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                saveTreatmentEditorChanges()
                                showTreatmentsEditor = false
                            }
                        }
                    }
                    .onAppear {
                        loadTreatmentEditorState()
                    }
                }
            }

        return Group {
            if isPhone {
                decorated.environmentObject(phoneFallbackDock)
            } else {
                decorated
            }
        }
    }

    private struct SessionLayoutLambMarkingPlaceholderView: View {
        @Binding var showDetails: Bool
        let isPhone: Bool
        let scannedCount: Int
        let onStartNewSession: () -> Void

        var body: some View {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Lamb Marking", systemImage: "tag")
                        .font(.headline)

                    Text("Placeholder layout. Next step is lamb-mark fields + optional treatments/traits.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Display") { showDetails = true }
                            .buttonStyle(.bordered)

                        Button("New Session") { onStartNewSession() }
                            .buttonStyle(.borderedProminent)

                        Spacer()

                        Text("Tally: \(scannedCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    private func toggleDraftPause() {
        guard layoutSupportsPauseRelay else { return }

        isDraftPaused.toggle()
        DraftWifiController.setPauseRelay(paused: isDraftPaused)
        updateDockState()
    }

    private func endDraftHardwareState() {
        if isDraftPaused {
            isDraftPaused = false
            DraftWifiController.setPauseRelay(paused: false)
        }

        drafter.sessionEnded()
        updateDockState()
    }

    private func configureDockIfNeeded() {
        let model = activeDockModel
        model.resetDefaults()

        model.onTreat = { dockPrimaryTapped() }
        model.onUndo = { dockSecondaryTapped() }
        model.onNewSession = { dockNewSessionTapped() }
        model.onDisplay = { dockDisplayTapped() }

        updateDockState()
    }

    private func updateDockState() {
        let model = activeDockModel

        model.setEnabled(.newSession, true)
        model.setTitle(.newSession, "New Session")
        model.setSystemImage(.newSession, "plus.circle.fill")
        model.setActive(.newSession, false)

        model.setEnabled(.display, hasActiveSession)
        model.setTitle(.display, "Display")
        model.setSystemImage(.display, "list.bullet.rectangle")
        model.setActive(.display, false)

        guard hasActiveSession else {
            model.setTitle(.treat, "Treatments")
            model.setSystemImage(.treat, "cross.case.fill")
            model.setEnabled(.treat, false)
            model.setActive(.treat, false)

            model.setTitle(.undo, "ReWeigh")
            model.setSystemImage(.undo, "arrow.clockwise")
            model.setEnabled(.undo, false)
            model.setActive(.undo, false)
            return
        }

        switch layoutKind {

        case .weighDraft, .scanWeighDraft:
            model.setTitle(.treat, "Reweigh")
            model.setSystemImage(.treat, "arrow.clockwise")
            model.setEnabled(.treat, canReweigh)
            model.setActive(.treat, false)

            model.setTitle(.undo, "Pause")
            model.setSystemImage(.undo, "pause.circle.fill")
            model.setEnabled(.undo, true)
            model.setActive(.undo, isDraftPaused)

        case .lambMarking, .lambMarkingTreatTrait:
            model.setTitle(.treat, "Treatments")
            model.setSystemImage(.treat, "cross.case.fill")
            model.setEnabled(.treat, currentSessionHasTreatments)
            model.setActive(.treat, false)

            model.setTitle(.undo, "History")
            model.setSystemImage(.undo, "clock.arrow.circlepath")
            model.setEnabled(.undo, !sessionsSortedNewestFirst.isEmpty)
            model.setActive(.undo, false)

        case .scanWeigh:
            model.setTitle(.treat, "Weights")
            model.setSystemImage(.treat, "scalemass.fill")
            model.setEnabled(.treat, false)
            model.setActive(.treat, false)

            model.setTitle(.undo, "ReWeigh")
            model.setSystemImage(.undo, "arrow.clockwise")
            model.setEnabled(.undo, canReweigh)
            model.setActive(.undo, false)

        case .scanWeighTreat:
            model.setTitle(.treat, currentSessionHasTreatments ? "Treatments (\(configuredTreatmentCount))" : "Treatments")
            model.setSystemImage(.treat, "cross.case.fill")
            model.setEnabled(.treat, true)
            model.setActive(.treat, false)

            model.setTitle(.undo, "ReWeigh")
            model.setSystemImage(.undo, "arrow.clockwise")
            model.setEnabled(.undo, canReweigh)
            model.setActive(.undo, false)

        case .scanWeighTreatDraft:
            model.setTitle(.treat, "Reweigh")
            model.setSystemImage(.treat, "arrow.clockwise")
            model.setEnabled(.treat, canReweigh)
            model.setActive(.treat, false)

            model.setTitle(.undo, "Pause")
            model.setSystemImage(.undo, "pause.circle.fill")
            model.setEnabled(.undo, true)
            model.setActive(.undo, isDraftPaused)

        case .draftOnly, .scanDraft:
            model.setTitle(.treat, "Draft")
            model.setSystemImage(.treat, "arrow.triangle.branch")
            model.setEnabled(.treat, true)
            model.setActive(.treat, false)

            model.setTitle(.undo, "Pause")
            model.setSystemImage(.undo, "pause.circle.fill")
            model.setEnabled(.undo, true)
            model.setActive(.undo, isDraftPaused)

        case .scanTreat, .treatOnly:
            model.setTitle(.treat, currentSessionHasTreatments ? "Treatments (\(configuredTreatmentCount))" : "Treatments")
            model.setSystemImage(.treat, "cross.case.fill")
            model.setEnabled(.treat, true)
            model.setActive(.treat, false)

            model.setTitle(.undo, "History")
            model.setSystemImage(.undo, "clock.arrow.circlepath")
            model.setEnabled(.undo, !sessionsSortedNewestFirst.isEmpty)
            model.setActive(.undo, false)

        case .scanTraits:
            model.setTitle(.treat, "Traits")
            model.setSystemImage(.treat, "slider.horizontal.3")
            model.setEnabled(.treat, false)
            model.setActive(.treat, false)

            model.setTitle(.undo, "History")
            model.setSystemImage(.undo, "clock.arrow.circlepath")
            model.setEnabled(.undo, !sessionsSortedNewestFirst.isEmpty)
            model.setActive(.undo, false)

        case .scanOnly:
            model.setTitle(.treat, "Scanner")
            model.setSystemImage(.treat, "qrcode.viewfinder")
            model.setEnabled(.treat, false)
            model.setActive(.treat, false)

            model.setTitle(.undo, "History")
            model.setSystemImage(.undo, "clock.arrow.circlepath")
            model.setEnabled(.undo, !sessionsSortedNewestFirst.isEmpty)
            model.setActive(.undo, false)

        case .transferSaleForm:
            model.setTitle(.treat, "History")
            model.setSystemImage(.treat, "clock.arrow.circlepath")
            model.setEnabled(.treat, !sessionsSortedNewestFirst.isEmpty)
            model.setActive(.treat, false)

            model.setTitle(.undo, "Resume")
            model.setSystemImage(.undo, "arrow.uturn.backward.circle")
            model.setEnabled(.undo, false)
            model.setActive(.undo, false)

        case .pregTestDraft:
            model.setTitle(.treat, currentSessionHasTreatments ? "Treatments (\(configuredTreatmentCount))" : "Treatments")
            model.setSystemImage(.treat, "cross.case.fill")
            model.setEnabled(.treat, true)
            model.setActive(.treat, false)

            model.setTitle(.undo, "Pause")
            model.setSystemImage(.undo, "pause.circle.fill")
            model.setEnabled(.undo, true)
            model.setActive(.undo, isDraftPaused)

        case .fleeceWeigh:
            model.setTitle(.treat, currentSessionHasTreatments ? "Treatments (\(configuredTreatmentCount))" : "Treatments")
            model.setSystemImage(.treat, "cross.case.fill")
            model.setEnabled(.treat, true)
            model.setActive(.treat, false)

            model.setTitle(.undo, "ReWeigh")
            model.setSystemImage(.undo, "arrow.clockwise")
            model.setEnabled(.undo, canReweigh)
            model.setActive(.undo, false)
        }
    }

    private func dockPrimaryTapped() {
        guard hasActiveSession else { return }

        switch layoutKind {
        case .weighDraft, .scanWeighDraft:
            guard canReweigh else { return }
            vm.reweigh()
            syncCoordinator()

        case .scanWeighTreatDraft:
            guard canReweigh else { return }
            vm.reweigh()
            syncCoordinator()

        case .draftOnly, .scanDraft, .pregTestDraft:
            onGoToDraftTab()

        case .scanTreat, .treatOnly, .fleeceWeigh, .scanWeighTreat, .lambMarkingTreatTrait:
            showTreatmentsEditor = true

        case .transferSaleForm:
            showHistory = true

        case .scanTraits, .scanOnly, .scanWeigh, .lambMarking:
            break
        }
    }

    private func dockSecondaryTapped() {
        guard hasActiveSession else { return }

        switch layoutKind {
        case .weighDraft, .scanWeighDraft, .scanWeighTreatDraft, .draftOnly, .scanDraft, .pregTestDraft:
            toggleDraftPause()

        case .fleeceWeigh, .scanWeigh, .scanWeighTreat:
            guard canReweigh else { return }
            vm.reweigh()
            syncCoordinator()

        case .scanTreat, .treatOnly, .scanTraits, .scanOnly, .lambMarking, .lambMarkingTreatTrait:
            showHistory = true

        case .transferSaleForm:
            break
        }
    }

    private func dockNewSessionTapped() {
        startNewSession()
    }

    private func dockDisplayTapped() {
        guard hasActiveSession else { return }
        showRecentAnimalsFullScreen = true
    }

    private func loadTreatmentEditorState() {
        editorRecordTreatments = true
        editorTepariGunEnabled = store.config(for: vm.activeSession.id)?.tepariGunEnabled ?? false
        editorTepariTreatmentID = nil

        let current = store.treatments(for: vm.activeSession.id)
        guard !current.isEmpty else {
            editorSelectedTreatmentIDs = []
            editorDoseOverrides = [:]
            return
        }

        var ids: Set<UUID> = []
        var overrides: [UUID: DoseValue] = [:]

        for s in current {
            if let match = treatmentLibrary.first(where: {
                $0.product.caseInsensitiveCompare(s.product) == .orderedSame
            }) {
                ids.insert(match.id)

                if let override = doseValueFromSessionTreatment(s, fallbackUnit: match.doseUnit) {
                    overrides[match.id] = override
                }
            }
        }

        editorSelectedTreatmentIDs = ids
        editorDoseOverrides = overrides
    }

    private func saveTreatmentEditorChanges() {
        guard editorRecordTreatments else {
            store.clearTreatments(sessionID: vm.activeSession.id)
            vm.reloadSessionTreatments()
            updateDockState()
            return
        }

        let picked = treatmentLibrary
            .filter { editorSelectedTreatmentIDs.contains($0.id) }
            .sorted { $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending }

        let mapped: [SessionTreatment] = picked.map { t in
            let ov = editorDoseOverrides[t.id]

            let value = (ov?.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? ov?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            : t.doseValue

            let unit = ov?.unit ?? t.doseUnit
            let basis = ov?.basis ?? t.doseBasis
            let perKg = (ov?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? ov?.perKg?.trimmingCharacters(in: .whitespacesAndNewlines)
            : {
                let trimmed = t.dosePerKg?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed?.isEmpty == true) ? nil : trimmed
            }()

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
                doseValue: {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }(),
                doseUnit: unit,
                doseBasis: basis,
                dosePerKg: basis == .perBodyWeight ? perKg : nil,
                minimumDose: nil,
                maximumDose: nil,
                doseStep: nil,
                requiresStableWeight: true
            )
        }

        store.setSessionTreatments(mapped, for: vm.activeSession.id)
        vm.reloadSessionTreatments()
        updateDockState()
    }

    private func doseValueFromSessionTreatment(
        _ treatment: SessionTreatment,
        fallbackUnit: DoseUnit
    ) -> DoseValue? {
        if let rawValue = treatment.doseValue {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                let unit = treatment.doseUnit ?? fallbackUnit
                let basis = treatment.doseBasis ?? .perAnimal
                let perKg = basis == .perBodyWeight ? treatment.dosePerKg : nil
                return DoseValue(value: value, unit: unit, basis: basis, perKg: perKg)
            }
        }

        let legacy = treatment.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else { return nil }
        return parseDoseValueFromLegacyString(legacy, fallbackUnit: fallbackUnit)
    }

    private func parseDoseValueFromLegacyString(
        _ s: String,
        fallbackUnit: DoseUnit
    ) -> DoseValue {
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

    private func parseAmountAndUnit(
        _ raw: String,
        fallbackUnit: DoseUnit
    ) -> (String, DoseUnit) {
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

    private func inferredTypes(from cfg: Any?) -> Set<SetupSessionType> {
        guard let cfg else { return [] }

        var types: Set<SetupSessionType> = []

        let weighingEnabled =
        reflectedBool(cfg, keys: [
            "weighingEnabled", "recordWeight", "weighEnabled", "enableWeigh", "isWeighingEnabled"
        ]) ?? false

        let draftingEnabled =
        reflectedBool(cfg, keys: [
            "draftingEnabled", "draftEnabled", "recordDraft", "enableDraft", "isDraftingEnabled"
        ]) ?? false

        let traitEnabled =
        (reflectedBool(cfg, keys: ["recordMicron"]) ?? false) ||
        (reflectedBool(cfg, keys: ["recordStapleLength"]) ?? false) ||
        (reflectedBool(cfg, keys: ["recordCustom1"]) ?? false) ||
        (reflectedBool(cfg, keys: ["recordCustom2"]) ?? false)

        if weighingEnabled {
            types.insert(.weigh)
        }

        if traitEnabled {
            types.insert(.traitInput)
        }

        if draftingEnabled {
            types.insert(.draft)
        }

        if !store.treatments(for: vm.activeSession.id).isEmpty {
            types.insert(.treatment)
        }

        if types.isEmpty {
            types.insert(.scan)
        }

        return types
    }

    private func syncCoordinator() {
        sessionCoordinator.push(
            eid: vm.currentEID,
            weight: vm.currentWeight,
            stable: vm.isStable,
            locked: vm.isLocked
        )
    }

    private func reflectedBool(_ value: Any, keys: [String]) -> Bool? {
        let mirror = Mirror(reflecting: value)

        for child in mirror.children {
            guard let label = child.label, keys.contains(label) else { continue }

            let v = unwrapOptional(child.value) ?? child.value

            if let b = v as? Bool { return b }

            if let s = v as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed == "true" || trimmed == "yes" || trimmed == "1" { return true }
                if trimmed == "false" || trimmed == "no" || trimmed == "0" { return false }
            }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedBoolFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func reflectedBoolFromMirror(_ mirror: Mirror, keys: [String]) -> Bool? {
        for child in mirror.children {
            guard let label = child.label, keys.contains(label) else { continue }

            let v = unwrapOptional(child.value) ?? child.value

            if let b = v as? Bool { return b }

            if let s = v as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed == "true" || trimmed == "yes" || trimmed == "1" { return true }
                if trimmed == "false" || trimmed == "no" || trimmed == "0" { return false }
            }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedBoolFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func unwrapOptional(_ any: Any) -> Any? {
        let mirror = Mirror(reflecting: any)
        guard mirror.displayStyle == .optional else { return any }
        return mirror.children.first?.value
    }

    private func promptRestart(_ session: Session) {
        sessionToRestart = session
        showRestartAlert = true
    }

    private func performRestart(_ session: Session) {
        endDraftHardwareState()
        resetForRestartedSession()
        sessionCoordinator.restartSessionFromHistory(session.id)
        vm.setSession(session)
        syncCoordinator()
        updateDockState()
    }

    private func resetForRestartedSession() {
        showWeighMode = false
        showZeroConfirmation = false
        showDetails = false
        showHistory = false
        showTreatmentSetup = false
        showTreatmentsEditor = false
        showRecentAnimalsFullScreen = false
        sessionToRestart = nil
    }

    private var noActiveSessionCard: some View {
        GeometryReader { proxy in
            let isPadLandscape = !Device.isPhone && proxy.size.width > proxy.size.height
            let heroCircleSize: CGFloat = Device.isPhone ? (isPadLandscape ? 220 : 270) : (isPadLandscape ? 300 : 360)
            let verticalSpacing: CGFloat = Device.isPhone ? (isPadLandscape ? 22 : 30) : (isPadLandscape ? 28 : 36)
            let buttonSpacing: CGFloat = isPadLandscape ? 14 : 16
            let buttonVerticalPadding: CGFloat = isPadLandscape ? 16 : 18

            GlassCard {
                VStack(spacing: 0) {
                    Spacer(minLength: isPadLandscape ? 34 : 24)

                    VStack(spacing: verticalSpacing + 14) {
                        TimelineView(.animation) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            let pulse = (sin(t * 1.05) + 1.0) * 0.5
                            let breatheScale = 1.00 + (0.045 * pulse)

                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 5)
                                .scaleEffect(breatheScale)
                                .frame(width: heroCircleSize * 1.30, height: heroCircleSize * 1.30)
                                .frame(width: heroCircleSize + 40, height: heroCircleSize + 40)
                                .compositingGroup()
                        }

                        VStack(spacing: 6) {
                            Text("Ready to work")
                                .font(Device.isPhone ? .title2.weight(.bold) : .largeTitle.weight(.bold))

                            Text("Start a new session, or open recent sessions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }

                        VStack(spacing: buttonSpacing) {
                            Button {
                                startNewSession()
                            } label: {
                                Label("Start New Session", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, buttonVerticalPadding)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.gray.opacity(0.95),
                                                Color.gray.opacity(0.75)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                            Button {
                                showHistory = true
                            } label: {
                                Label("Recent Sessions", systemImage: "clock.arrow.circlepath")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, buttonVerticalPadding)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.gray.opacity(0.75),
                                                Color.gray.opacity(0.58)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .frame(maxWidth: Device.isPhone ? 520 : 560)
                        .padding(.top, isPadLandscape ? 8 : 2)
                    }

                    Spacer(minLength: isPadLandscape ? 14 : 22)

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusPill(_ title: String, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func startNewSession() {
        endDraftHardwareState()
        let s = store.createSession(named: "Session \(store.sessions.count + 1)")
        vm.setSession(s)
        sessionCoordinator.activeSessionID = s.id
        syncCoordinator()
        updateDockState()
        showTreatmentSetup = true
    }

    private struct SessionHistoryListView: View {
        let sessions: [Session]
        let onSelect: (Session) -> Void
        let onNewSession: () -> Void
        let onDelete: (Session) -> Void

        var body: some View {
            List {
                Section("All Sessions") {
                    ForEach(sessions) { s in
                        Button {
                            onSelect(s)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)

                                Text(s.name)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(s)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
