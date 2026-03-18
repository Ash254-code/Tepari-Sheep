import Foundation
import Combine

@MainActor
final class ActiveSessionCoordinator: ObservableObject {

    // =========================================================
    // MARK: - Persistence
    // =========================================================

    private let persistedTypesKey = "ActiveSessionCoordinator.typesBySessionID.v1"

    // =========================================================
    // MARK: - Active Session Identity
    // =========================================================

    /// Canonical value the app reads/writes.
    @Published var activeSessionID: UUID? = nil {
        didSet {
            // Only reset if the session actually changed (prevents flicker).
            guard oldValue != activeSessionID else { return }

            if let id = activeSessionID {
                restorePersistedSessionTypesIfNeeded(for: id)
            }

            resetLiveAnimalState()
        }
    }

    /// Alias so older code using activeSessionId keeps working
    var activeSessionId: UUID? {
        get { activeSessionID }
        set { activeSessionID = newValue }
    }

    /// Convenience flag for UI logic
    var hasActiveSession: Bool {
        activeSessionID != nil
    }

    // =========================================================
    // MARK: - Session Types (Layout / Mode Selection)
    // =========================================================

    /// Selected session types per session ID (filled by SessionSetup wizard).
    @Published private var typesBySessionID: [UUID: Set<SetupSessionType>] = [:]

    init() {
        loadPersistedSessionTypes()
    }

    /// ✅ SessionView reads this (never a Binding)
    var activeSessionTypes: Set<SetupSessionType> {
        guard let id = activeSessionID else { return [] }
        return typesBySessionID[id] ?? []
    }

    /// ✅ Call when the wizard changes / completes
    func setSessionTypes(_ types: Set<SetupSessionType>, for sessionID: UUID) {
        typesBySessionID[sessionID] = types
        persistSessionTypes()
        objectWillChange.send() // ensures router updates immediately
    }

    /// Optional: clear stored types for a session (if you delete session, etc.)
    func clearSessionTypes(for sessionID: UUID) {
        typesBySessionID.removeValue(forKey: sessionID)
        persistSessionTypes()
        objectWillChange.send()
    }

    /// Lets callers force a restore if needed after app launch / history reopen.
    func restoreSessionTypesIfNeeded(for sessionID: UUID) {
        restorePersistedSessionTypesIfNeeded(for: sessionID)
        objectWillChange.send()
    }

    // =========================================================
    // MARK: - Individual Animal Navigation / Focus
    // =========================================================

    /// If set, Individual view should show this animal (e.g. search result / history tap),
    /// otherwise it shows the live scanned EID.
    @Published var focusedEID: String? = nil

    /// Set when user taps an animal anywhere and app should jump to IndividualAnimalView.
    @Published var showIndividualAnimalView: Bool = false
    @Published var selectedIndividualAnimalEID: String? = nil
    @Published var selectedIndividualAnimalFarmID: UUID? = nil

    /// Individual view uses this (focused overrides live).
    var displayEID: String {
        if let f = focusedEID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !f.isEmpty {
            return f
        }
        return eid
    }

    func setFocusedEID(_ eid: String?) {
        let cleaned = Self.cleanedEID(eid)
        focusedEID = cleaned

        // If user sets focus, make UI immediately reflect that
        if let cleaned {
            self.eid = cleaned
            self.lastUpdate = Date()
        }
    }

    /// Call from history rows, search results, recent scans, etc.
    func openIndividualAnimal(eidRaw: String, farmID: UUID? = nil) {
        guard let cleaned = Self.cleanedEID(eidRaw) else { return }

        selectedIndividualAnimalEID = cleaned
        selectedIndividualAnimalFarmID = farmID

        // Keep existing IndividualAnimalView behaviour working
        setFocusedEID(cleaned)

        // Triggers navigation/presentation in parent view
        showIndividualAnimalView = true
    }

    func closeIndividualAnimal() {
        showIndividualAnimalView = false
        selectedIndividualAnimalEID = nil
        selectedIndividualAnimalFarmID = nil
    }

    // =========================================================
    // MARK: - Live Animal State (for weighing / drafting)
    // =========================================================

    @Published var eid: String = "—"
    @Published var weight: Double = 0
    @Published var stable: Bool = false
    @Published var locked: Bool = false
    @Published var lastUpdate: Date = .distantPast

    // =========================================================
    // MARK: - Restart / Resume State
    // =========================================================

    /// Used by live session views to know a history session was intentionally restarted
    /// and should reopen in scan-ready mode instead of restoring old UI state.
    @Published private(set) var restartedSessionIDs: Set<UUID> = []

    func restartSessionFromHistory(_ sessionID: UUID) {
        // Make sure the layout/session-type info exists before switching active session.
        restorePersistedSessionTypesIfNeeded(for: sessionID)

        // Clear any current focus / live state first so the session opens clean.
        resetLiveAnimalState()

        // Mark as restarted so SessionView / individual screens can react onAppear if needed.
        restartedSessionIDs.insert(sessionID)

        // Make this the active session.
        activeSessionID = sessionID

        // Extra notify in case a live screen is already mounted and watching coordinator state.
        objectWillChange.send()
    }

    func wasJustRestarted(_ sessionID: UUID) -> Bool {
        restartedSessionIDs.contains(sessionID)
    }

    func consumeRestartFlag(for sessionID: UUID) {
        restartedSessionIDs.remove(sessionID)
    }

    // =========================================================
    // MARK: - Demo Feed (global, drives Individual tab)
    // =========================================================

    @Published private(set) var demoRunning: Bool = false

    private var demoTask: Task<Void, Never>?
    private var demoIndex: Int = 0

    /// Start a global demo feed so tabs (esp. Individual) always show animals.
    /// - Uses real seeded animals if available (best), otherwise falls back to a fake EID.
    /// - Does NOT override manual focus (focusedEID).
    func startDemoFeed(store: LocalDataStore, tickSeconds: Double = 1.0) {
        stopDemoFeed()

        demoRunning = true
        demoIndex = 0

        demoTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(max(0.2, tickSeconds) * 1_000_000_000))

                // Don't stomp the UI if user is focused on a search result / selected animal
                if self.focusedEID != nil { continue }

                let animals = store.animals
                let nextEID: String
                if animals.isEmpty {
                    nextEID = "982 123456789"
                } else {
                    self.demoIndex = (self.demoIndex + 1) % animals.count
                    nextEID = animals[self.demoIndex].eidRaw
                }

                let base = 52.0
                let jitter = Double.random(in: -1.2...1.2)

                self.push(
                    eid: nextEID,
                    weight: base + jitter,
                    stable: true,
                    locked: false
                )
            }
        }
    }

    func stopDemoFeed() {
        demoTask?.cancel()
        demoTask = nil
        demoRunning = false
    }

    // =========================================================
    // MARK: - Session Lifecycle
    // =========================================================

    /// Call when a session officially begins (after wizard completes)
    func startSession(id: UUID) {
        restorePersistedSessionTypesIfNeeded(for: id)
        activeSessionID = id
    }

    /// Semantic helper when user taps a different session in History
    func switchSession(to id: UUID) {
        restorePersistedSessionTypesIfNeeded(for: id)
        activeSessionID = id
    }

    /// Call when a session ends (manual stop, crash recovery, etc)
    func endSession() {
        activeSessionID = nil
        restartedSessionIDs.removeAll()
        resetLiveAnimalState()
        closeIndividualAnimal()
    }

    // =========================================================
    // MARK: - Live Data Feed
    // =========================================================

    func push(eid: String, weight: Double, stable: Bool, locked: Bool) {
        let cleaned = Self.cleanedEID(eid) ?? "—"
        self.eid = cleaned
        self.weight = weight
        self.stable = stable
        self.locked = locked
        self.lastUpdate = Date()
    }

    // =========================================================
    // MARK: - Reset Helpers
    // =========================================================

    private func resetLiveAnimalState() {
        // Don’t automatically kill the demo task here; Root decides.
        focusedEID = nil
        eid = "—"
        weight = 0
        stable = false
        locked = false
        lastUpdate = .distantPast
    }

    private static func cleanedEID(_ raw: String?) -> String? {
        let cleaned = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // =========================================================
    // MARK: - Session Type Persistence
    // =========================================================

    private func restorePersistedSessionTypesIfNeeded(for sessionID: UUID) {
        if let existing = typesBySessionID[sessionID], !existing.isEmpty {
            return
        }

        loadPersistedSessionTypes()
    }

    private func persistSessionTypes() {
        let payload: [String: [String]] = typesBySessionID.reduce(into: [:]) { result, pair in
            result[pair.key.uuidString] = pair.value.map(\.rawValue).sorted()
        }

        UserDefaults.standard.set(payload, forKey: persistedTypesKey)
    }

    private func loadPersistedSessionTypes() {
        guard let payload = UserDefaults.standard.dictionary(forKey: persistedTypesKey) as? [String: [String]] else {
            return
        }

        var restored: [UUID: Set<SetupSessionType>] = [:]

        for (key, rawValues) in payload {
            guard let id = UUID(uuidString: key) else { continue }

            let resolved = Set(rawValues.compactMap { SetupSessionType(rawValue: $0) })
            if !resolved.isEmpty {
                restored[id] = resolved
            }
        }

        if !restored.isEmpty {
            typesBySessionID.merge(restored) { current, restored in
                current.isEmpty ? restored : current
            }
        }
    }
}
