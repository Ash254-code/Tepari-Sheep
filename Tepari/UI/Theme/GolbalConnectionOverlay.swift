import SwiftUI

struct GlobalConnectionOverlay: View {
    let handlerState: ConnectionState
    let draftState: ConnectionState
    let stickState: ConnectionState
    let xrp2iState: ConnectionState
    let gunState: ConnectionState

    // ✅ which are used for the current context (session types)
    let useHandler: Bool
    let useDraft: Bool
    let useStick: Bool
    let useXrp2i: Bool
    let useGun: Bool

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        HStack(spacing: isCompact ? 8 : 10) {
            ConnectionMiniPill(title: "H", state: handlerState, compact: isCompact, isActive: useHandler)
            ConnectionMiniPill(title: "D", state: draftState, compact: isCompact, isActive: useDraft)
            ConnectionMiniPill(title: "S", state: stickState, compact: isCompact, isActive: useStick)
            ConnectionMiniPill(title: "X", state: xrp2iState, compact: isCompact, isActive: useXrp2i)
            ConnectionMiniPill(title: "G", state: gunState, compact: isCompact, isActive: useGun)
        }
    }
}

func connectionPillUsage(for activeTypes: Set<SetupSessionType>) -> (h: Bool, d: Bool, s: Bool, x: Bool, g: Bool) {

    // Handler / scale
    let h = activeTypes.contains(.weigh) || activeTypes.contains(.fleeceWeigh)

    // Drafter
    let d = true
        activeTypes.contains(.draft) ||
        activeTypes.contains(.pregTesting) ||
        activeTypes.contains(.sale) ||
        activeTypes.contains(.transfer)

    // Dosing gun
    let g = activeTypes.contains(.treatment) || activeTypes.contains(.lambMarking)

    // Readers should be visible when scan-related workflows are active.
    let s = activeTypes.contains(.scan)
    let x = activeTypes.contains(.scan)

    return (h: h, d: d, s: s, x: x, g: g)
}
