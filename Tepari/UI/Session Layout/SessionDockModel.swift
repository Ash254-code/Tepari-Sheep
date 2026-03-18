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

        init(title: String, systemImage: String, enabled: Bool = true, isLoading: Bool = false) {
            self.title = title
            self.systemImage = systemImage
            self.enabled = enabled
            self.isLoading = isLoading
        }
    }

    // =====================================================
    // MARK: - Public state the dock renders
    // =====================================================

    /// ✅ INFO ONLY: opens a read-only treatments sheet
    @Published var treat = ButtonState(
        title: "Treatments",
        systemImage: "cross.case.fill",
        enabled: false
    )

    // ✅ This slot is now repurposed by SessionView as "ReWeigh" (title/icon updated at runtime)
    @Published var undo = ButtonState(title: "Undo", systemImage: "arrow.uturn.backward", enabled: false)
    @Published var newSession = ButtonState(title: "New Session", systemImage: "plus.circle.fill", enabled: true)
    @Published var display = ButtonState(title: "Display", systemImage: "chevron.up", enabled: true)

    // =====================================================
    // MARK: - Session-scoped info
    // =====================================================

    /// ✅ Whether this session has treatments configured (wizard selection)
    @Published private(set) var hasConfiguredTreatments: Bool = false

    /// Optional: show count in the button title
    @Published private(set) var configuredTreatmentCount: Int = 0

    /// Call this when session starts OR when wizard selection changes before start.
    /// The dock uses this to enable/disable the Treatments button.
    func setTreatmentsConfigured(_ count: Int) {
        configuredTreatmentCount = max(0, count)
        hasConfiguredTreatments = configuredTreatmentCount > 0

        // Keep label stable, optionally include count (nice on iPad)
        if hasConfiguredTreatments {
            treat.title = "Treatments (\(configuredTreatmentCount))"
            treat.enabled = true
        } else {
            treat.title = "Treatments"
            treat.enabled = false
        }
    }

    // =====================================================
    // MARK: - Action handlers (set by Session root)
    // =====================================================

    /// ✅ Non-optional handlers to avoid "dead" buttons when wiring happens late
    /// In DEBUG, these will assert so you immediately see if wiring is missing.
    var onTreat: () -> Void = {
        assertionFailure("SessionDockModel.onTreat not wired")
    }

    // ✅ Repurposed as ReWeigh by SessionView
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

    // ✅ Convenience for retitling a slot (keeps SessionView wiring cleaner)
    func setTitle(_ slot: Slot, _ title: String) {
        switch slot {
        case .treat: treat.title = title
        case .undo: undo.title = title
        case .newSession: newSession.title = title
        case .display: display.title = title
        }
    }

    // ✅ Convenience for changing the SF Symbol (keeps SessionView wiring cleaner)
    func setSystemImage(_ slot: Slot, _ systemImage: String) {
        switch slot {
        case .treat: treat.systemImage = systemImage
        case .undo: undo.systemImage = systemImage
        case .newSession: newSession.systemImage = systemImage
        case .display: display.systemImage = systemImage
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
