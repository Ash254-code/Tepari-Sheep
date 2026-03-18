import Foundation
import Combine

@MainActor
final class DraftSettings: ObservableObject {

    // =====================================================
    // MARK: - Gate behaviour
    // =====================================================

    /// Time after weight lock before gate moves.
    @Published var triggerDelaySeconds: Double = 1.0 {
        didSet { triggerDelaySeconds = clamp(triggerDelaySeconds, 0.0, 5.0) }
    }

    /// Time gate takes to physically move to position.
    @Published var gateMoveDurationSeconds: Double = 0.8 {
        didSet { gateMoveDurationSeconds = clamp(gateMoveDurationSeconds, 0.1, 5.0) }
    }

    /// How long gate stays open before returning (only if autoRelease enabled).
    @Published var gateHoldSeconds: Double = 1.5 {
        didSet { gateHoldSeconds = clamp(gateHoldSeconds, 0.1, 10.0) }
    }

    /// Time to return to home position.
    @Published var gateReturnSeconds: Double = 0.8 {
        didSet { gateReturnSeconds = clamp(gateReturnSeconds, 0.1, 5.0) }
    }

    // =====================================================
    // MARK: - Release behaviour
    // =====================================================

    /// If TRUE → gate returns after animal passes.
    /// If FALSE → gate stays where it is until next draft command.
    @Published var autoReleaseEnabled: Bool = false

    /// When session stops, always return to centre/home.
    @Published var returnHomeOnSessionEnd: Bool = true

    // =====================================================
    // MARK: - Default / startup behaviour
    // =====================================================

    /// When system powers up or connects.
    @Published var startInHomePosition: Bool = true

    // =====================================================
    // MARK: - Manual test timing
    // =====================================================

    /// Extra hold time when using manual test buttons.
    @Published var manualTestHoldSeconds: Double = 2.0 {
        didSet { manualTestHoldSeconds = clamp(manualTestHoldSeconds, 0.1, 20.0) }
    }

    // =====================================================
    // MARK: - Safety
    // =====================================================

    /// Max time a movement is allowed before timeout fault.
    @Published var movementTimeoutSeconds: Double = 5.0 {
        didSet { movementTimeoutSeconds = clamp(movementTimeoutSeconds, 1.0, 30.0) }
    }

    /// Prevent new draft while gate moving.
    @Published var blockWhileMoving: Bool = true

    // =====================================================
    // MARK: - Logical → Physical Gate Mapping (MID-SESSION EDITABLE)
    // =====================================================
    /// ✅ This is the layer that lets you re-route outcomes to different gates
    /// during a session without touching rules.
    ///
    /// Example:
    /// - Preg Twins used to go Right
    /// - Change `twinGate` to `.farRight`
    /// - Next twin immediately goes Far Right
    ///
    /// This same mapping can be used for ANY draft session (not just preg).
    @Published var gateMap: DraftGateMap = DraftGateMap()

    /// ✅ Convenience presets (optional helpers)
    func setThreeGateDefault() {
        gateMap.empty = .left
        gateMap.single = .straight
        gateMap.twin = .right
        gateMap.keep = .straight
        gateMap.cull = .left
        gateMap.custom = .straight
    }

    func setFourGatePregSuggested() {
        // Suggested if you want twins isolated:
        // empty → left, single → straight, twin → farRight
        gateMap.empty = .left
        gateMap.single = .straight
        gateMap.twin = .farRight
        gateMap.keep = .straight
        gateMap.cull = .left
        gateMap.custom = .right
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func clamp(_ value: Double, _ minVal: Double, _ maxVal: Double) -> Double {
        max(minVal, min(maxVal, value))
    }
}
