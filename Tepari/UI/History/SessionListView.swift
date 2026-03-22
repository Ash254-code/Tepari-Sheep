import SwiftUI

struct SessionListView: View {

    @EnvironmentObject private var store: LocalDataStore
    @EnvironmentObject private var coordinator: ActiveSessionCoordinator

    @State private var sessionToRestart: Session? = nil
    @State private var showRestartAlert: Bool = false

    @State private var isSelecting: Bool = false
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var showBulkDeleteAlert: Bool = false

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
        let totalAnimals = store.records(for: session.id).count

        return "\(farmName) - \(sessionTypeText) - \(totalAnimals)"
    }

    private func toggleSelection(for sessionID: UUID) {
        if selectedSessionIDs.contains(sessionID) {
            selectedSessionIDs.remove(sessionID)
        } else {
            selectedSessionIDs.insert(sessionID)
        }
    }

    private func selectAllSessions() {
        selectedSessionIDs = Set(store.sessions.map(\.id))
    }

    private func clearSelection() {
        selectedSessionIDs.removeAll()
    }

    private func deleteSelectedSessions() {
        let sessionsToDelete = store.sessions.filter { selectedSessionIDs.contains($0.id) }

        for session in sessionsToDelete {
            store.deleteSession(session)
            if coordinator.activeSessionID == session.id {
                coordinator.activeSessionID = nil
            }
        }

        selectedSessionIDs.removeAll()
        isSelecting = false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        headerCard

                        if store.sessions.isEmpty {
                            emptyStateCard
                        } else {
                            sessionsList
                        }

                        Spacer(minLength: 10)
                    }
                    .padding(.horizontal, 16)
                    .safeAreaPadding(.bottom, 12)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(selectedSessionIDs.count == store.sessions.count && !store.sessions.isEmpty ? "Clear All" : "Select All") {
                            if selectedSessionIDs.count == store.sessions.count && !store.sessions.isEmpty {
                                clearSelection()
                            } else {
                                selectAllSessions()
                            }
                        }

                        Button("Done") {
                            isSelecting = false
                            clearSelection()
                        }

                        if !selectedSessionIDs.isEmpty {
                            Button(role: .destructive) {
                                showBulkDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    } else {
                        Button("Select") {
                            isSelecting = true
                            clearSelection()
                        }
                    }
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
            .alert("Delete selected sessions?", isPresented: $showBulkDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedSessions()
                }
            } message: {
                Text("This will delete \(selectedSessionIDs.count) selected session(s).")
            }
        }
    }

    // =========================================================
    // MARK: - Header
    // =========================================================

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.title3.weight(.bold))

                Text("Previous sessions stored on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

                Text("Completed or saved sessions will appear here.")
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
        let sorted = store.sessions.sorted { $0.createdAt > $1.createdAt }

        return VStack(spacing: 10) {
            ForEach(sorted) { s in
                sessionRow(s)
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        let cfg = store.config(for: session.id)

        let sessionFarmName: String = {
            if let farmID = cfg?.farmID,
               let farm = store.farms.first(where: { $0.id == farmID }) {
                return farm.name
            }
            let n = (cfg?.farmName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? farmName(for: session.farmID) : n
        }()

        let sessionTypeText: String = sessionTypeTextFor(session, cfg: cfg)
        let totalAnimals: Int = store.records(for: session.id).count
        let dateText: String = session.createdAt.formatted(date: .abbreviated, time: .omitted)
        let timeText: String = session.createdAt.formatted(date: .omitted, time: .shortened)
        let isSelected = selectedSessionIDs.contains(session.id)

        return Button {
            if isSelecting {
                toggleSelection(for: session.id)
            } else {
                sessionToRestart = session
                showRestartAlert = true
            }
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: 12) {

                    Image(systemName: isSelecting
                          ? (isSelected ? "checkmark.circle.fill" : "circle")
                          : "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            isSelecting
                            ? (isSelected ? .blue : .secondary)
                            : .secondary
                        )
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(sessionFarmName) - \(sessionTypeText) - \(totalAnimals)")
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(dateText)
                            Text("•")
                            Text(timeText)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !isSelecting {
                        Image(systemName: coordinator.activeSessionID == session.id ? "checkmark.circle.fill" : "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(coordinator.activeSessionID == session.id ? .green : .secondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isSelecting {
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
    }

    // =========================================================
    // MARK: - Session Type + Mob + Yards helpers
    // =========================================================

    private func sessionTypeTextFor(_ session: Session, cfg: Any?) -> String {
        guard let cfg = cfg as? LocalDataStore.SessionConfig else {
            return "General"
        }

        var parts: [String] = []

        if cfg.weighingEnabled {
            parts.append("Weigh")
        }

        if cfg.recordTreatments {
            parts.append("Treat")
        }

        if cfg.equipment.contains(.draft) {
            parts.append("Draft")
        }

        return parts.isEmpty ? "General" : parts.joined(separator: " ")
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
    private func reflectedBool(_ value: Any, keys: [String]) -> Bool? {
        let mirror = Mirror(reflecting: value)

        for child in mirror.children {
            guard let label = child.label else { continue }
            guard keys.contains(label) else { continue }

            let v = unwrapOptional(child.value) ?? child.value

            if let b = v as? Bool { return b }

            if let s = v as? String {
                switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1", "on":
                    return true
                case "false", "no", "0", "off":
                    return false
                default:
                    break
                }
            }

            let desc = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch desc {
            case "true", "yes", "1", "on":
                return true
            case "false", "no", "0", "off":
                return false
            default:
                break
            }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedBoolFromMirror(superclass, keys: keys)
        }

        return nil
    }

    private func reflectedBoolFromMirror(_ mirror: Mirror, keys: [String]) -> Bool? {
        for child in mirror.children {
            guard let label = child.label else { continue }
            guard keys.contains(label) else { continue }

            let v = unwrapOptional(child.value) ?? child.value

            if let b = v as? Bool { return b }

            if let s = v as? String {
                switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1", "on":
                    return true
                case "false", "no", "0", "off":
                    return false
                default:
                    break
                }
            }

            let desc = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch desc {
            case "true", "yes", "1", "on":
                return true
            case "false", "no", "0", "off":
                return false
            default:
                break
            }
        }

        if let superclass = mirror.superclassMirror {
            return reflectedBoolFromMirror(superclass, keys: keys)
        }

        return nil
    }
    private func unwrapOptional(_ any: Any) -> Any? {
        let m = Mirror(reflecting: any)
        guard m.displayStyle == .optional else { return any }
        return m.children.first?.value
    }
}
