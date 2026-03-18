import Foundation

struct SessionCapabilities: Hashable {
    let scanningEnabled: Bool
    let weighingEnabled: Bool
    let draftingEnabled: Bool

    static func derive(from types: Set<SetupSessionType>) -> SessionCapabilities {
        let drafting = types.contains(.draft)
        let weighing = types.contains(.weigh) || types.contains(.fleeceWeigh)

        // Your derived rule: scanning enabled if scanner OR stick reader required.
        // Since equipment is locked by types, we can derive scanning from types too:
        let scanning =
            types.contains(.scan) ||
            types.contains(.draft) ||
            types.contains(.transfer) ||
            types.contains(.sale) ||
            types.contains(.treatment) ||
            types.contains(.lambMarking) ||   // stick reader
            types.contains(.fleeceWeigh)      // stick reader

        return .init(scanningEnabled: scanning,
                     weighingEnabled: weighing,
                     draftingEnabled: drafting)
    }
}
