import Foundation
import Combine

@MainActor
final class DraftSettings: ObservableObject {

    // =====================================================
    // MARK: - Release mode
    // =====================================================

    enum AutoReleaseMode: String, Codable, CaseIterable, Identifiable {
        case off
        case timed
        case whenJobsComplete

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off:
                return "Off"
            case .timed:
                return "Timed"
            case .whenJobsComplete:
                return "Jobs Complete"
            }
        }
    }

    // =====================================================
    // MARK: - Gate behaviour
    // =====================================================

    /// Time after trigger/weight lock before gate moves.
    @Published var triggerDelaySeconds: Double = 1.0 {
        didSet { triggerDelaySeconds = clamp(triggerDelaySeconds, 0.0, 5.0) }
    }

    /// Time gate takes to physically move to target position.
    @Published var gateMoveDurationSeconds: Double = 0.8 {
        didSet { gateMoveDurationSeconds = clamp(gateMoveDurationSeconds, 0.1, 5.0) }
    }

    /// Used only when autoReleaseMode == .timed
    /// How long the gate stays in drafted position before release.
    @Published var gateHoldSeconds: Double = 0.0 {
        didSet { gateHoldSeconds = clamp(gateHoldSeconds, 0.0, 10.0) }
    }

    /// Time to return to home position after release.
    /// Kept for calibration/UI clarity even if the current controller
    /// flow returns using gateMoveDurationSeconds.
    @Published var gateReturnSeconds: Double = 0.8 {
        didSet { gateReturnSeconds = clamp(gateReturnSeconds, 0.1, 5.0) }
    }

    // =====================================================
    // MARK: - Release behaviour
    // =====================================================

    /// Master control for release behaviour.
    /// - off: animal stays held until another command or manual release
    /// - timed: release automatically after `gateHoldSeconds`
    /// - whenJobsComplete: release only after required session jobs are done
    @Published var autoReleaseMode: AutoReleaseMode = .timed

    var isTimedAutoRelease: Bool {
        autoReleaseMode == .timed
    }

    var isJobsCompleteAutoRelease: Bool {
        autoReleaseMode == .whenJobsComplete
    }

    /// Kept for compatibility, but real animal release now uses the release relay.
    @Published var releaseToHomePosition: Bool = true

    /// Optional delay before release happens after manual/explicit release call.
    @Published var releaseDelaySeconds: Double = 0.0 {
        didSet { releaseDelaySeconds = clamp(releaseDelaySeconds, 0.0, 5.0) }
    }

    /// When session stops, always return to centre/home.
    @Published var returnHomeOnSessionEnd: Bool = true

    // =====================================================
    // MARK: - Default / startup behaviour
    // =====================================================

    @Published var startInHomePosition: Bool = true

    // =====================================================
    // MARK: - Manual test timing
    // =====================================================

    /// Extra hold time when using manual test buttons.
    /// Manual tests should pulse and return regardless of auto release mode.
    @Published var manualTestHoldSeconds: Double = 2.0 {
        didSet { manualTestHoldSeconds = clamp(manualTestHoldSeconds, 0.1, 20.0) }
    }

    // =====================================================
    // MARK: - Safety
    // =====================================================

    @Published var movementTimeoutSeconds: Double = 5.0 {
        didSet { movementTimeoutSeconds = clamp(movementTimeoutSeconds, 1.0, 30.0) }
    }

    @Published var blockWhileMoving: Bool = true

    // =====================================================
    // MARK: - Logical → Physical Gate Mapping
    // =====================================================

    @Published var gateMap: DraftGateMap = DraftGateMap()

    func setThreeGateDefault() {
        gateMap.empty = .left
        gateMap.single = .straight
        gateMap.twin = .right
        gateMap.keep = .straight
        gateMap.cull = .left
        gateMap.custom = .straight
    }

    func setFourGatePregSuggested() {
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
