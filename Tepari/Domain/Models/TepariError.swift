import Foundation

/// Represents parsed data coming from the Te Pari handler.
/// One incoming line may generate multiple events.
enum TepariEvent: Equatable {

    /// Raw EID tag string (must preserve leading zeros)
    case eid(String)

    /// Live weight reading (kg, not yet locked)
    case weight(Double)

    /// Stable flag from scales
    case stable(Bool)
}
