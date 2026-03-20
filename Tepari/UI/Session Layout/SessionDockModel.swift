import SwiftUI
import Combine

@MainActor
final class SessionDockModel: ObservableObject {

    enum Slot: CaseIterable {
        case treat, undo, newSession, display
    }

    struct ButtonState: Equatable {
        var title: String
        var systemImage: String
        var enabled: Bool
        var isLoading: Bool
        var isActive: Bool

        init(
            title: String,
            systemImage: String,
            enabled: Bool = true,
            isLoading: Bool = false,
            isActive: Bool = false
        ) {
            self.title = title
            self.systemImage = systemImage
            self.enabled = enabled
            self.isLoading = isLoading
            self.isActive = isActive
        }
    }

    // =====================================================
    // MARK: - Public state the dock renders
    // =====================================================

    @Published var treat = ButtonState(
        title: "Treatments",
        systemImage: "cross.case.fill",
        enabled: false
    )

    @Published var undo = ButtonState(
        title: "Undo",
        systemImage: "arrow.uturn.backward",
        enabled: false
    )

    @Published var newSession = ButtonState(
        title: "New Session",
        systemImage: "plus.circle.fill",
        enabled: true
    )

    @Published var display = ButtonState(
        title: "Display",
        systemImage: "chevron.up",
        enabled: true
    )

    // =====================================================
    // MARK: - Session-scoped info
    // =====================================================

    @Published private(set) var hasConfiguredTreatments: Bool = false
    @Published private(set) var configuredTreatmentCount: Int = 0

    func setTreatmentsConfigured(_ count: Int) {
        configuredTreatmentCount = max(0, count)
        hasConfiguredTreatments = configuredTreatmentCount > 0

        if hasConfiguredTreatments {
            treat.title = "Treatments (\(configuredTreatmentCount))"
            treat.enabled = true
        } else {
            treat.title = "Treatments"
            treat.enabled = false
        }
    }

    // =====================================================
    // MARK: - Action handlers
    // =====================================================

    var onTreat: () -> Void = {
        assertionFailure("SessionDockModel.onTreat not wired")
    }

    var onUndo: () -> Void = {
        assertionFailure("SessionDockModel.onUndo not wired")
    }

    var onNewSession: () -> Void = {
        assertionFailure("SessionDockModel.onNewSession not wired")
    }

    var onDisplay: () -> Void = {
        assertionFailure("SessionDockModel.onDisplay not wired")
    }

    // =====================================================
    // MARK: - Convenience helpers
    // =====================================================

    func setEnabled(_ slot: Slot, _ enabled: Bool) {
        switch slot {
        case .treat: treat.enabled = enabled
        case .undo: undo.enabled = enabled
        case .newSession: newSession.enabled = enabled
        case .display: display.enabled = enabled
        }
    }

    func setLoading(_ slot: Slot, _ loading: Bool) {
        switch slot {
        case .treat: treat.isLoading = loading
        case .undo: undo.isLoading = loading
        case .newSession: newSession.isLoading = loading
        case .display: display.isLoading = loading
        }
    }

    func setTitle(_ slot: Slot, _ title: String) {
        switch slot {
        case .treat: treat.title = title
        case .undo: undo.title = title
        case .newSession: newSession.title = title
        case .display: display.title = title
        }
    }

    func setSystemImage(_ slot: Slot, _ systemImage: String) {
        switch slot {
        case .treat: treat.systemImage = systemImage
        case .undo: undo.systemImage = systemImage
        case .newSession: newSession.systemImage = systemImage
        case .display: display.systemImage = systemImage
        }
    }

    func setActive(_ slot: Slot, _ isActive: Bool) {
        switch slot {
        case .treat: treat.isActive = isActive
        case .undo: undo.isActive = isActive
        case .newSession: newSession.isActive = isActive
        case .display: display.isActive = isActive
        }
    }

    func resetDefaults() {
        treat = .init(title: "Treatments", systemImage: "cross.case.fill", enabled: false)
        undo = .init(title: "Undo", systemImage: "arrow.uturn.backward", enabled: false)
        newSession = .init(title: "New Session", systemImage: "plus.circle.fill", enabled: true)
        display = .init(title: "Display", systemImage: "chevron.up", enabled: true)

        hasConfiguredTreatments = false
        configuredTreatmentCount = 0
    }
}
