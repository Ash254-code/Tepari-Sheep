import SwiftUI

struct SessionListView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator

    @State private var showNewSessionWizard = false
    @State private var newSessionID: UUID? = nil

    @State private var sessionToRestart: Session? = nil
    @State private var showRestartAlert: Bool = false

    // =========================================================
    // MARK: - Recent session helpers
    // =========================================================

    private var mostRecentSession: Session? {
        store.sessions.sorted { $0.createdAt > $1.createdAt }.first
    }

    private var recentSessionsTop3: [Session] {
        Array(store.sessions.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }

    private func farmName(for farmID: UUID?) -> String {
        guard let id = farmID,
              let f = store.farms.first(where: { $0.id == id }) else {
            return "No farm"
        }
        return f.name
    }

    private func farmNameForSession(_ s: Session) -> String {
        let cfg = store.config(for: s.id)

        if let farmID = cfg?.farmID,
           let f = store.farms.first(where: { $0.id == farmID }) {
            return f.name
        }

        let manual = (cfg?.farmName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return manual }

        return farmName(for: s.farmID)
    }

    private func yardsNameForSession(_ session: Session) -> String {
        let cfg = store.config(for: session.id)
        return yardsNameTextFor(session, cfg: cfg)
    }

    private func sessionSummaryTitle(for session: Session) -> String {
        let farmName = farmNameForSession(session)
        let sessionTypeText = sessionTypeTextFor(session, cfg: store.config(for: session.id))
        let mobText = mobNameTextFor(session, cfg: store.config(for: session.id))
        let totalAnimals = store.records(for: session.id).count

        return "\(farmName) - \(sessionTypeText) - \(mobText) - \(totalAnimals)"
    }

    private var recentSessionTitle: String? {
        guard let s = mostRecentSession else { return nil }
        return sessionSummaryTitle(for: s)
    }

    // =========================================================
    // MARK: - Body
    // =========================================================

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(spacing: 14) {

                        if coordinator.activeSessionID == nil {

                            landingCard
                                .padding(.top, 8)

                            if !store.sessions.isEmpty {
                                recentSessionsCard
                            } else {
                                emptyStateCard
                            }

                        } else {

                            headerCard

                            if store.sessions.isEmpty {
                                emptyStateCard
                            } else {
                                sessionsList
                            }
                        }

                        Spacer(minLength: 10)
                    }
                    .padding(.horizontal, 16)
                    .safeAreaPadding(.bottom, 12)
                    .padding(.bottom, 56)
                }
            }
            .sheet(isPresented: $showNewSessionWizard, onDismiss: {
                newSessionID = nil
            }) {
                if let id = newSessionID {
                    SessionSetupView(sessionID: id) {
                        coordinator.activeSessionID = id
                    }
                } else {
                    GlassBackground()
                        .overlay(
                            GlassCard {
                                Text("No session selected.")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        )
                }
            }
            .alert("Restart Session?", isPresented: $showRestartAlert, presenting: sessionToRestart) { session in
                Button("Cancel", role: .cancel) { }

                Button("Yes") {
                    coordinator.restartSessionFromHistory(session.id)
                }
            } message: { _ in
                Text("Would you like to restart this session?")
            }
        }
    }

    // =========================================================
    // MARK: - Landing Card
    // =========================================================

    private var landingCard: some View {
        SessionLandingCardView(
            recentTitle: recentSessionTitle,
            onContinueRecent: mostRecentSession == nil ? nil : {
                sessionToRestart = mostRecentSession
                showRestartAlert = true
            },
            onStartNew: {
                let created = store.createSession(named: "New Session")
                newSessionID = created.id
                showNewSessionWizard = true
            },
            scannerConnected: nil,
            scalesConnected: nil,
            draftConnected: nil,
            minCardHeight: 520
        )
    }

    // =========================================================
    // MARK: - Recent Sessions Card
    // =========================================================

    private var recentSessionsCard: some View {
        GlassCard {
            VStack(spacing: 10) {

                HStack {
                    Text("Recent Sessions")
                        .font(.headline)

                    Spacer()

                    NavigationLink {
                        SessionHistoryView(
                            store: store,
                            coordinator: coordinator,
                            onNewSession: {
                                let created = store.createSession(named: "New Session")
                                newSessionID = created.id
                                showNewSessionWizard = true
                            },
                            onDeleteSession: { session in
                                store.deleteSession(session)
                                if coordinator.activeSessionID == session.id {
                                    coordinator.activeSessionID = nil
                                }
                            },
                            onRestartSession: { session in
                                coordinator.restartSessionFromHistory(session.id)
                            },
                            farmNameForSession: farmNameForSession(_:),
                            yardsNameForSession: yardsNameForSession(_:),
                            sessionTypeTextForSession: { s in
                                sessionTypeTextFor(s, cfg: store.config(for: s.id))
                            },
                            mobNameTextForSession: { s in
                                mobNameTextFor(s, cfg: store.config(for: s.id))
                            },
                            reflectedString: reflectedString(_:keys:),
                            unwrapOptional: unwrapOptional(_:)
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Text("More")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.18)

                VStack(spacing: 6) {
                    ForEach(recentSessionsTop3) { s in
                        recentSessionRow(s)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func recentSessionRow(_ session: Session) -> some View {
        let title = sessionSummaryTitle(for: session)

        return Button {
            sessionToRestart = session
            showRestartAlert = true
        } label: {
            HStack(spacing: 12) {

                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text("Tap to restart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // =========================================================
    // MARK: - Header
    // =========================================================

    private var headerCard: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.title3.weight(.bold))

                    Text("Your sessions are stored on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let created = store.createSession(named: "New Session")
                    newSessionID = created.id
                    showNewSessionWizard = true
                } label: {
                    Label("New Session", systemImage: "plus")
                }
                .glassButton(.compact)
            }
        }
        .padding(.top, 6)
    }

    // =========================================================
    // MARK: - Empty
    // =========================================================

    private var emptyStateCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("No sessions yet")
                    .font(.headline)

                Text("Tap “New Session” to start.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // =========================================================
    // MARK: - Sessions List
    // =========================================================

    private var sessionsList: some View {
        VStack(spacing: 10) {
            ForEach(store.sessions) { s in
                sessionRow(s)
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        let cfg = store.config(for: session.id)

        let farmName: String = {
            if let farmID = cfg?.farmID,
               let farm = store.farms.first(where: { $0.id == farmID }) {
                return farm.name
            }
            let n = (cfg?.farmName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "—" : n
        }()

        let _: String = yardsNameTextFor(session, cfg: cfg)
        let sessionTypeText: String = sessionTypeTextFor(session, cfg: cfg)
        let mobText: String = mobNameTextFor(session, cfg: cfg)
        let totalAnimals: Int = store.records(for: session.id).count
        let dateText: String = session.createdAt.formatted(date: .abbreviated, time: .shortened)

        return Button {
            sessionToRestart = session
            showRestartAlert = true
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {

                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {

                        Text("\(farmName) - \(sessionTypeText) - \(mobText) - \(totalAnimals)")
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: coordinator.activeSessionID == session.id ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(coordinator.activeSessionID == session.id ? .green : .secondary)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.deleteSession(session)
                if coordinator.activeSessionID == session.id {
                    coordinator.activeSessionID = nil
                }
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
    }

    // =========================================================
    // MARK: - Session Type + Mob + Yards helpers
    // =========================================================

    private func sessionTypeTextFor(_ session: Session, cfg: Any?) -> String {
        let raw = [
            reflectedString(cfg as Any, keys: [
                "sessionType", "type", "mode", "kind", "sessionKind", "sessionTypeRaw", "sessionTypeName"
            ]) ?? "",
            reflectedString(session, keys: [
                "sessionType", "type", "mode", "kind", "sessionKind", "sessionTypeRaw", "sessionTypeName"
            ]) ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        var parts: [String] = []
        if raw.contains("weigh") { parts.append("Weigh") }
        if raw.contains("draft") { parts.append("Draft") }
        if raw.contains("treat") { parts.append("Treat") }

        return parts.isEmpty ? "General" : parts.joined(separator: "/")
    }

    private func mobNameTextFor(_ session: Session, cfg: Any?) -> String {
        if let cfg, let id = reflectedUUID(cfg, keys: ["mobID", "selectedMobID", "mobId"]) {
            if let m = store.mobs.first(where: { $0.id == id }) {
                let n = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { return n }
            }
        }

        if let cfg, let s = reflectedString(cfg, keys: ["mobName", "selectedMobName", "mob", "mobTitle"]) {
            if let uuid = UUID(uuidString: s),
               let m = store.mobs.first(where: { $0.id == uuid }) {
                let n = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { return n }
            }
            return s
        }

        if let s = reflectedString(session, keys: ["mobName", "selectedMobName", "mob", "mobTitle"]) {
            if let uuid = UUID(uuidString: s),
               let m = store.mobs.first(where: { $0.id == uuid }) {
                let n = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { return n }
            }
            return s
        }

        return "—"
    }

    private func yardsNameTextFor(_ session: Session, cfg: Any?) -> String {
        if let cfg, let s = reflectedString(cfg, keys: [
            "yardsName", "yardName", "selectedYardsName", "selectedYardName",
            "yards", "yard", "locationName", "selectedLocationName"
        ]) {
            return s
        }

        if let s = reflectedString(session, keys: [
            "yardsName", "yardName", "selectedYardsName", "selectedYardName",
            "yards", "yard", "locationName", "selectedLocationName"
        ]) {
            return s
        }

        return "—"
    }

    // =========================================================
    // MARK: - Reflection helper
    // =========================================================

    private func reflectedString(_ value: Any, keys: [String]) -> String? {
        let mirror = Mirror(reflecting: value)

        for child in mirror.children {
            guard let label = child.label else { continue }
            guard keys.contains(label) else { continue }

            let v = child.value

            if let s = v as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            if let s = unwrapOptional(v) as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            let desc = String(describing: unwrapOptional(v) ?? v)
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "nil" {
                return trimmed
            }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedStringFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func reflectedStringFromMirror(_ mirror: Mirror, keys: [String]) -> String? {
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard keys.contains(label) else { continue }

            let v = child.value

            if let s = v as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            if let s = unwrapOptional(v) as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            let desc = String(describing: unwrapOptional(v) ?? v)
            let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "nil" {
                return trimmed
            }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedStringFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func reflectedUUID(_ value: Any, keys: [String]) -> UUID? {
        let mirror = Mirror(reflecting: value)

        for child in mirror.children {
            guard let label = child.label else { continue }
            guard keys.contains(label) else { continue }

            let v = unwrapOptional(child.value) ?? child.value

            if let u = v as? UUID { return u }
            if let s = v as? String, let u = UUID(uuidString: s) { return u }

            let desc = String(describing: v)
            if let u = UUID(uuidString: desc) { return u }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedUUIDFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func reflectedUUIDFromMirror(_ mirror: Mirror, keys: [String]) -> UUID? {
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard keys.contains(label) else { continue }

            let v = unwrapOptional(child.value) ?? child.value

            if let u = v as? UUID { return u }
            if let s = v as? String, let u = UUID(uuidString: s) { return u }

            let desc = String(describing: v)
            if let u = UUID(uuidString: desc) { return u }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedUUIDFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func unwrapOptional(_ any: Any) -> Any? {
        let m = Mirror(reflecting: any)
        guard m.displayStyle == .optional else { return any }
        return m.children.first?.value
    }
}

// =========================================================
// MARK: - Full History Screen
// =========================================================

private struct SessionHistoryView: View {

    let store: LocalDataStore
    let coordinator: ActiveSessionCoordinator
    let onNewSession: () -> Void
    let onDeleteSession: (Session) -> Void
    let onRestartSession: (Session) -> Void

    let farmNameForSession: (Session) -> String
    let yardsNameForSession: (Session) -> String
    let sessionTypeTextForSession: (Session) -> String
    let mobNameTextForSession: (Session) -> String
    let reflectedString: (Any, [String]) -> String?
    let unwrapOptional: (Any) -> Any?

    @State private var isEditing: Bool = false
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var showDeleteSelectedConfirm: Bool = false

    @State private var sessionToRestart: Session? = nil
    @State private var showRestartAlert: Bool = false

    private var sessionCount: Int {
        store.sessions.count
    }

    private var allSessionIDs: Set<UUID> {
        Set(store.sessions.map(\.id))
    }

    private var hasSelection: Bool {
        !selectedSessionIDs.isEmpty
    }

    private var allSelected: Bool {
        !store.sessions.isEmpty && selectedSessionIDs == allSessionIDs
    }

    var body: some View {
        ZStack {
            GlassBackground()

            ScrollView {
                VStack(spacing: 14) {

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("History")
                                        .font(.title3.weight(.bold))

                                    Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s") stored on this device.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    Button(action: toggleEditMode) {
                                        Text(isEditing ? "Done" : "Edit")
                                    }
                                    .glassButton(.compact)

                                    Button(action: onNewSession) {
                                        Label("New Session", systemImage: "plus")
                                    }
                                    .glassButton(.compact)
                                }
                            }

                            if isEditing {
                                Divider().opacity(0.18)

                                HStack(spacing: 8) {
                                    Button(allSelected ? "Clear Selection" : "Select All") {
                                        if allSelected {
                                            selectedSessionIDs.removeAll()
                                        } else {
                                            selectedSessionIDs = allSessionIDs
                                        }
                                    }
                                    .glassButton(.compact)

                                    Spacer()

                                    Button(role: .destructive) {
                                        showDeleteSelectedConfirm = true
                                    } label: {
                                        Label(
                                            hasSelection
                                            ? "Delete Selected (\(selectedSessionIDs.count))"
                                            : "Delete Selected",
                                            systemImage: "trash"
                                        )
                                    }
                                    .glassButton(.compact)
                                    .disabled(!hasSelection)
                                    .opacity(hasSelection ? 1 : 0.45)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)

                    if store.sessions.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No sessions yet")
                                    .font(.headline)

                                Text("Tap “New Session” to start.")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.sessions) { s in
                                historyRow(s)
                            }
                        }
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .safeAreaPadding(.bottom, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete selected sessions?",
            isPresented: $showDeleteSelectedConfirm
        ) {
            Button("Cancel", role: .cancel) { }

            Button("Delete", role: .destructive) {
                deleteSelectedSessions()
            }
        } message: {
            Text(
                "This will permanently delete \(selectedSessionIDs.count) session\(selectedSessionIDs.count == 1 ? "" : "s")."
            )
        }
        .alert("Restart Session?", isPresented: $showRestartAlert, presenting: sessionToRestart) { session in
            Button("Cancel", role: .cancel) { }

            Button("Yes") {
                onRestartSession(session)
            }
        } message: { _ in
            Text("Would you like to restart this session?")
        }
        .onChange(of: store.sessions.map(\.id)) { _, ids in
            let live = Set(ids)
            selectedSessionIDs = selectedSessionIDs.intersection(live)
            if live.isEmpty {
                isEditing = false
            }
        }
    }

    private func toggleEditMode() {
        isEditing.toggle()
        if !isEditing {
            selectedSessionIDs.removeAll()
        }
    }

    private func toggleSelection(for sessionID: UUID) {
        if selectedSessionIDs.contains(sessionID) {
            selectedSessionIDs.remove(sessionID)
        } else {
            selectedSessionIDs.insert(sessionID)
        }
    }

    private func deleteSelectedSessions() {
        let ids = selectedSessionIDs
        let sessionsToDelete = store.sessions.filter { ids.contains($0.id) }

        for session in sessionsToDelete {
            onDeleteSession(session)
        }

        selectedSessionIDs.removeAll()
        isEditing = false
    }

    private func historyRow(_ session: Session) -> some View {
        let farmName = farmNameForSession(session)
        _ = yardsNameForSession(session)
        let sessionTypeText = sessionTypeTextForSession(session)
        let mobText = mobNameTextForSession(session)
        let totalAnimals = store.records(for: session.id).count
        let dateText = session.createdAt.formatted(date: .abbreviated, time: .shortened)
        let isSelected = selectedSessionIDs.contains(session.id)

        return Button {
            if isEditing {
                toggleSelection(for: session.id)
            } else {
                sessionToRestart = session
                showRestartAlert = true
            }
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {

                    if isEditing {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            .frame(width: 28)
                    } else {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                    }

                    VStack(alignment: .leading, spacing: 6) {

                        Text("\(farmName) - \(sessionTypeText) - \(mobText) - \(totalAnimals)")
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isEditing {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            .padding(.top, 2)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isEditing {
                Button(role: .destructive) {
                    onDeleteSession(session)
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
            }
        }
    }
}
