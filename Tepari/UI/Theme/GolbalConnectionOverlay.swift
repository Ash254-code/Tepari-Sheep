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
            if useHandler {
                ConnectionMiniPill(title: "H", state: handlerState, compact: isCompact, isActive: true)
            }
            if useDraft {
                ConnectionMiniPill(title: "D", state: draftState, compact: isCompact, isActive: true)
            }
            if useStick {
                ConnectionMiniPill(title: "S", state: stickState, compact: isCompact, isActive: true)
            }
            if useXrp2i {
                ConnectionMiniPill(title: "X", state: xrp2iState, compact: isCompact, isActive: true)
            }
            if useGun {
                ConnectionMiniPill(title: "G", state: gunState, compact: isCompact, isActive: true)
            }
        }
    }
}

func connectionPillUsage(for activeTypes: Set<SetupSessionType>) -> (h: Bool, d: Bool, s: Bool, x: Bool, g: Bool) {

    let h =
        activeTypes.contains(.weigh) ||
        activeTypes.contains(.fleeceWeigh)

    let d =
        activeTypes.contains(.draft) ||
        activeTypes.contains(.pregTesting) ||
        activeTypes.contains(.sale) ||
        activeTypes.contains(.transfer)

    let g =
        activeTypes.contains(.treatment) ||
        activeTypes.contains(.lambMarking)

    let scanRelated =
        activeTypes.contains(.scan) ||
        activeTypes.contains(.traitInput) ||
        activeTypes.contains(.treatment) ||
        activeTypes.contains(.pregTesting) ||
        activeTypes.contains(.sale) ||
        activeTypes.contains(.transfer)

    return (
        h: h,
        d: d,
        s: scanRelated,
        x: scanRelated,
        g: g
    )
}
