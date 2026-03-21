import SwiftUI

struct RootTabView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var transport: TransportManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tepariGun: TepariGunManager
    @EnvironmentObject private var gunListener: GunListener

    @StateObject private var draftSettings: DraftSettings
    @StateObject private var drafter: DrafterController
    @StateObject private var watchReceiver: WatchDraftReceiver
    @StateObject private var sessionVM: SessionViewModel

    @StateObject private var sessionCoordinator = ActiveSessionCoordinator()

    @StateObject private var racewell = RacewellManager()
    @StateObject private var stickReader = StickReaderManager()
    @StateObject private var xrp2i = XRP2iManager()

    @State private var iPadTab: AppTab = .session
    @State private var phoneTab: AppTab = .session

    // ✅ Hard reset tokens for More tab root
    @State private var morePhoneResetID = UUID()
    @State private var moreIPadResetID = UUID()

    private let iPadTabBarHeight: CGFloat = 58
    private let iPadTabBarBottomPad: CGFloat = 8

    @StateObject private var sessionDock = SessionDockModel()

    private let iPadDockHeight: CGFloat = 100
    private let iPadDockGapAbovePill: CGFloat = 10

    private let parser = TepariMessageParser()

    private var iPadReservedBottomBase: CGFloat {
        iPadTabBarHeight + iPadTabBarBottomPad + 18
    }

    private var iPadReservedBottom: CGFloat {
        if iPadTab == .session && sessionCoordinator.activeSessionID != nil {
            return iPadReservedBottomBase + iPadDockHeight + iPadDockGapAbovePill + 12
        } else {
            return iPadReservedBottomBase
        }
    }

    init() {
        let sharedDraftSettings = DraftSettings()
        _draftSettings = StateObject(wrappedValue: sharedDraftSettings)

        let sharedDrafter = DrafterController(settings: sharedDraftSettings)
        _drafter = StateObject(wrappedValue: sharedDrafter)

        _watchReceiver = StateObject(wrappedValue: WatchDraftReceiver(drafter: sharedDrafter))

        let sharedDraftEngine = DraftRuleEngine()
        sharedDraftEngine.gateMap = sharedDraftSettings.gateMap

        let vm = SessionViewModel(
            store: LocalDataStore(),
            settings: AppSettings(),
            draftSettings: sharedDraftSettings,
            initialSession: Session(name: "Loading…"),
            draftEngine: sharedDraftEngine,
            drafterController: sharedDrafter
        )
        _sessionVM = StateObject(wrappedValue: vm)
    }

    private var draftState: ConnectionState { racewell.state }
    private var stickState: ConnectionState { stickReader.state }

    private var handlerState: ConnectionState {
        transport.method == .demo ? .connected : transport.state
    }

    private func resetMoreStack(isPhone: Bool) {
        if isPhone {
            morePhoneResetID = UUID()
        } else {
            moreIPadResetID = UUID()
        }
    }

    private func goToDraftTab() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            if Device.isPhone {
                phoneTab = .drafting
            } else {
                iPadTab = .drafting
            }
        }
    }

    private func goToSessionTab() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            if Device.isPhone {
                phoneTab = .session
            } else {
                iPadTab = .session
            }
        }
    }

    private func goToIndividualTab() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            if Device.isPhone {
                phoneTab = .individual
            } else {
                iPadTab = .individual
            }
        }
    }

    private func openAnimalInIndividualTab(_ animal: LocalDataStore.AnimalProfile) {
        sessionCoordinator.openIndividualAnimal(
            eidRaw: animal.eidRaw,
            farmID: animal.farmID
        )
        goToIndividualTab()
    }

    private func goHome() {
        sessionCoordinator.endSession()
        goToSessionTab()
    }

    private func installTransportLineHandler() {
        transport.onReceiveLine = { line in
            if line.hasPrefix("[DBG-]") ||
                line.hasPrefix("[DBG-") ||
                line.hasPrefix("[STATE]") ||
                line.hasPrefix("[INFO]") ||
                line.hasPrefix("[WATCHDOG]") {
                return
            }

            let events = parser.parseLine(line)
            guard !events.isEmpty else { return }
            guard sessionCoordinator.activeSessionID != nil else { return }

            sessionVM.ingest(events: events)
            sessionCoordinator.push(
                eid: sessionVM.currentEID,
                weight: sessionVM.currentWeight,
                stable: sessionVM.isStable,
                locked: sessionVM.isLocked
            )
        }
    }

    private func ensureTransportConnectedIfNeeded() {
        if transport.method == .tcp && transport.state == .disconnected {
            transport.connect()
        }
    }

    var body: some View {
        Group {
            if Device.isPhone {
                TabView(selection: $phoneTab) {

                    NavigationStack {
                        SessionView(
                            store: store,
                            settings: settings,
                            onGoToDraftTab: { goToDraftTab() }
                        )
                        .applyGlobalNavPills(
                            handlerState: handlerState,
                            draftState: draftState,
                            stickState: stickState,
                            activeTypes: sessionCoordinator.activeSessionTypes,
                            onTapHome: { goHome() }
                        )
                    }
                    .tabItem {
                        Image(systemName: "scalemass.fill")
                        Text("Session")
                    }
                    .tag(AppTab.session)

                    NavigationStack {
                        IndividualAnimalView()
                            .applyGlobalNavPills(
                                handlerState: handlerState,
                                draftState: draftState,
                                stickState: stickState,
                                onTapHome: { goHome() }
                            )
                    }
                    .tabItem {
                        Image(systemName: "document")
                        Text("Individual")
                    }
                    .tag(AppTab.individual)

                    NavigationStack {
                        DraftDashboardView()
                            .applyGlobalNavPills(
                                handlerState: handlerState,
                                draftState: draftState,
                                stickState: stickState,
                                onTapHome: { goHome() }
                            )
                    }
                    .tabItem {
                        Image(systemName: "arrow.trianglehead.branch")
                        Text("Drafting")
                    }
                    .tag(AppTab.drafting)

                    NavigationStack {
                        SessionSummaryView()
                            .applyGlobalNavPills(
                                handlerState: handlerState,
                                draftState: draftState,
                                stickState: stickState,
                                onTapHome: { goHome() }
                            )
                    }
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("Summary")
                    }
                    .tag(AppTab.summary)

                    NavigationStack {
                        SessionListView()
                            .applyGlobalNavPills(
                                handlerState: handlerState,
                                draftState: draftState,
                                stickState: stickState,
                                onTapHome: { goHome() }
                            )
                    }
                    .tabItem {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
                    .tag(AppTab.history)

                    MoreTabRoot(
                        resetID: morePhoneResetID,
                        handlerState: handlerState,
                        draftState: draftState,
                        stickState: stickState,
                        onTapHome: { goHome() }
                    )
                    .tabItem {
                        Image(systemName: "ellipsis.circle")
                        Text("More")
                    }
                    .tag(AppTab.more)
                }
                .toolbar(.visible, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)

            } else {
                ZStack(alignment: .bottom) {

                    iPadContent(for: iPadTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, iPadReservedBottom)

                    if iPadTab == .session && sessionCoordinator.activeSessionID != nil {
                        SessionControlDock(
                            model: sessionDock
                        )
                        .padding(.bottom, iPadTabBarHeight + iPadTabBarBottomPad + iPadDockGapAbovePill)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .transition(.opacity)
                    }

                    GlassPillTabBar(
                        selection: $iPadTab,
                        onReselectMore: {
                            resetMoreStack(isPhone: false)
                        }
                    )
                    .frame(height: iPadTabBarHeight)
                    .padding(.horizontal, 18)
                    .padding(.bottom, iPadTabBarBottomPad)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
        }
        .buttonStyle(HapticButtonStyle())
        .environmentObject(drafter)
        .environmentObject(draftSettings)
        .environmentObject(sessionCoordinator)
        .environmentObject(racewell)
        .environmentObject(stickReader)
        .environmentObject(xrp2i)
        .environmentObject(tepariGun)
        .environmentObject(gunListener)
        .environmentObject(sessionVM)
        .onAppear {
            _ = watchReceiver

            sessionVM.rebind(
                store: store,
                settings: settings,
                draftSettings: draftSettings,
                tepariGun: tepariGun,
                gunListener: gunListener
            )
            sessionVM.drafterController = drafter
            sessionVM.draftEngine?.gateMap = draftSettings.gateMap

            installTransportLineHandler()
            ensureTransportConnectedIfNeeded()
            syncDemoFeed()

            sessionDock.resetDefaults()
            sessionDock.setTreatmentsConfigured(0)

            DraftWifiController.startDiscovery()
            racewell.refreshStatus()

            if sessionCoordinator.activeSessionID != nil {
                goToSessionTab()
            }
        }
        .onChange(of: transport.method) { _, _ in
            installTransportLineHandler()
            syncDemoFeed()
            ensureTransportConnectedIfNeeded()
        }
        .onChange(of: transport.state) { _, _ in
            installTransportLineHandler()
        }
        .onChange(of: sessionCoordinator.activeSessionID) { _, newID in
            installTransportLineHandler()
            syncDemoFeed()

            sessionDock.resetDefaults()
            sessionDock.setTreatmentsConfigured(0)

            if newID != nil {
                goToSessionTab()
            }
        }
        .onChange(of: draftSettings.gateMap) { _, newMap in
            sessionVM.draftEngine?.gateMap = newMap
        }
        .onChange(of: phoneTab) { oldValue, newValue in
            if newValue == .more && oldValue != .more {
                resetMoreStack(isPhone: true)
            }
        }
        .onChange(of: iPadTab) { oldValue, newValue in
            if newValue == .more && oldValue != .more {
                resetMoreStack(isPhone: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            installTransportLineHandler()
            ensureTransportConnectedIfNeeded()
            DraftWifiController.startDiscovery()
            racewell.refreshStatus()
        }
    }

    private func syncDemoFeed() {
        if transport.method == .demo && sessionCoordinator.hasActiveSession {
            sessionCoordinator.startDemoFeed(store: store)
        } else {
            sessionCoordinator.stopDemoFeed()
        }
    }

    @ViewBuilder
    private func iPadContent(for tab: AppTab) -> some View {
        switch tab {

        case .session:
            NavigationStack {
                SessionView(
                    store: store,
                    settings: settings,
                    onGoToDraftTab: { goToDraftTab() }
                )
                .applyGlobalNavPills(
                    handlerState: handlerState,
                    draftState: draftState,
                    stickState: stickState,
                    activeTypes: sessionCoordinator.activeSessionTypes,
                    onTapHome: { goHome() }
                )
                .environmentObject(sessionDock)
            }

        case .individual:
            NavigationStack {
                IndividualAnimalView()
                    .applyGlobalNavPills(
                        handlerState: handlerState,
                        draftState: draftState,
                        stickState: stickState,
                        onTapHome: { goHome() }
                    )
            }

        case .drafting:
            NavigationStack {
                DraftDashboardView()
                    .applyGlobalNavPills(
                        handlerState: handlerState,
                        draftState: draftState,
                        stickState: stickState,
                        onTapHome: { goHome() }
                    )
            }

        case .summary:
            NavigationStack {
                SessionSummaryView()
                    .applyGlobalNavPills(
                        handlerState: handlerState,
                        draftState: draftState,
                        stickState: stickState,
                        onTapHome: { goHome() }
                    )
            }

        case .history:
            NavigationStack {
                SessionListView()
                    .applyGlobalNavPills(
                        handlerState: handlerState,
                        draftState: draftState,
                        stickState: stickState,
                        onTapHome: { goHome() }
                    )
            }

        case .more:
            MoreTabRoot(
                resetID: moreIPadResetID,
                handlerState: handlerState,
                draftState: draftState,
                stickState: stickState,
                onTapHome: { goHome() }
            )
        }
    }
}

private extension View {
    func applyGlobalNavPills(
        handlerState: ConnectionState,
        draftState: ConnectionState,
        stickState: ConnectionState,
        activeTypes: Set<SetupSessionType>? = nil,
        onTapHome: @escaping () -> Void
    ) -> some View {
        self.modifier(
            GlobalNavPillsModifier(
                handlerState: handlerState,
                draftState: draftState,
                stickState: stickState,
                activeTypes: activeTypes,
                onTapHome: onTapHome
            )
        )
    }
}

private struct GlobalNavPillsModifier: ViewModifier {
    let handlerState: ConnectionState
    let draftState: ConnectionState
    let stickState: ConnectionState
    let activeTypes: Set<SetupSessionType>?
    let onTapHome: () -> Void

    @State private var showConnectivity = false
    @EnvironmentObject private var gunListener: GunListener

    private var gunConnectionState: ConnectionState {
        switch gunListener.state {
        case .error:
            return .error("Gun listener error")
        case .starting:
            return .connecting
        case .listening:
            return gunListener.lastPeer == "—" ? .connecting : .connected
        case .stopped:
            return .disconnected
        }
    }

    func body(content: Content) -> some View {
        let usage: (h: Bool, d: Bool, s: Bool, x: Bool, g: Bool)

        if let activeTypes, !activeTypes.isEmpty {
            usage = connectionPillUsage(for: activeTypes)
        } else {
            usage = (h: true, d: true, s: true, x: true, g: true)
        }

        return content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onTapHome) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Home")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConnectivity = true
                    } label: {
                        GlobalConnectionOverlay(
                            handlerState: handlerState,
                            draftState: draftState,
                            stickState: stickState,
                            xrp2iState: .disconnected,
                            gunState: gunConnectionState,
                            useHandler: usage.h,
                            useDraft: usage.d,
                            useStick: usage.s,
                            useXrp2i: usage.x,
                            useGun: usage.g
                        )
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Connectivity")
                }
            }
            .sheet(isPresented: $showConnectivity) {
                NavigationStack { ConnectivityView() }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.thinMaterial, for: .navigationBar)
    }
}

private enum AppTab: Hashable {
    case session, individual, drafting, summary, history, more

    var title: String {
        switch self {
        case .session: return "Session"
        case .individual: return "Individual"
        case .drafting: return "Drafting"
        case .summary: return "Summary"
        case .history: return "History"
        case .more: return "More"
        }
    }

    var icon: String {
        switch self {
        case .session: return "scalemass.fill"
        case .individual: return "person.text.rectangle"
        case .drafting: return "arrow.trianglehead.branch"
        case .summary: return "chart.bar.fill"
        case .history: return "clock.arrow.circlepath"
        case .more: return "ellipsis.circle"
        }
    }
}

private struct MoreTabRoot: View {
    let resetID: UUID
    let handlerState: ConnectionState
    let draftState: ConnectionState
    let stickState: ConnectionState
    let onTapHome: () -> Void

    var body: some View {
        NavigationStack {
            SettingsMenuView()
                .applyGlobalNavPills(
                    handlerState: handlerState,
                    draftState: draftState,
                    stickState: stickState,
                    onTapHome: onTapHome
                )
        }
        .id(resetID)
    }
}

private struct GlassPillTabBar: View {

    @Binding var selection: AppTab
    var onReselectMore: (() -> Void)? = nil

    private let tabs: [AppTab] = [.session, .individual, .drafting, .summary, .more]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(radius: 14)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = (selection == tab)

        return Button {
            if tab == .more && selection == .more {
                onReselectMore?()
            } else {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background(
                Group {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}
