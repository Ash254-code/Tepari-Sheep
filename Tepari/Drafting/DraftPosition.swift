import Foundation

// =========================================================
// MARK: - Draft Position (PHYSICAL GATE)
// =========================================================
/// ✅ Physical draft output (actual gate fired).
/// Keep this enum representing hardware reality.
enum DraftPosition: Int, CaseIterable, Identifiable, Codable {

    /// Gate numbers are kept as raw values for hardware protocols.
    case left = 1
    case straight = 2     // all gates home
    case right = 3
    case farRight = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .left: return "Left"
        case .straight: return "Straight"
        case .right: return "Right"
        case .farRight: return "Far Right"
        }
    }

    // -----------------------------------------------------
    // MARK: - Convenience
    // -----------------------------------------------------

    /// ✅ Useful for UI / config screens
    var shortLabel: String {
        switch self {
        case .left: return "L"
        case .straight: return "S"
        case .right: return "R"
        case .farRight: return "FR"
        }
    }

    /// ✅ Stable ordering for UI pickers
    static var ordered: [DraftPosition] {
        [.left, .straight, .right, .farRight]
    }

    /// ✅ True if this requires an "extra" 4th lane
    var requiresFourGates: Bool {
        self == .farRight
    }
}
