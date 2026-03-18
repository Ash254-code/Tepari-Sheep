import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchDraftReceiver: NSObject, ObservableObject, WCSessionDelegate {

    private let drafter: DrafterController

    init(drafter: DrafterController) {
        self.drafter = drafter
        super.init()

        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }

            switch type {
            case "draft":
                guard let raw = message["position"] as? Int,
                      let pos = DraftPosition(rawValue: raw) else { return }
                drafter.manualTest(position: pos)

            case "catch":
                break

            case "release":
                break

            default:
                break
            }
        }
    }

    nonisolated func session(_ session: WCSession,
                            activationDidCompleteWith activationState: WCSessionActivationState,
                            error: Error?) { }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
