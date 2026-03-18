import Foundation
import Combine          // ✅ ADD THIS
import WatchConnectivity

@MainActor
final class WatchDraftSender: NSObject, ObservableObject, WCSessionDelegate {

    @Published private(set) var isReachable: Bool = false
    @Published private(set) var statusText: String = "Connecting…"

    override init() {
        super.init()
        activate()
        refreshStatus()
    }

    private func activate() {
        guard WCSession.isSupported() else {
            statusText = "WC not supported"
            isReachable = false
            return
        }

        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func refreshStatus() {
        let s = WCSession.default
        isReachable = s.isReachable
        statusText = isReachable ? "Phone connected" : "Phone not reachable"
    }

    // MARK: - Public send API

    func sendDraft(_ position: DraftPosition) {
        send(["type": "draft", "position": position.rawValue])
    }

    func sendCatch() {
        send(["type": "catch"])
    }

    func sendRelease() {
        send(["type": "release"])
    }

    // MARK: - Internal send

    private func send(_ message: [String: Any]) {
        let s = WCSession.default
        guard s.isReachable else {
            refreshStatus()
            return
        }

        s.sendMessage(message, replyHandler: nil) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        // Optimistically update status (feels snappy)
        refreshStatus()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession,
                            activationDidCompleteWith activationState: WCSessionActivationState,
                            error: Error?) {
        Task { @MainActor in
            self.refreshStatus()
        }
    }

    /// Called when reachability changes (e.g. phone app becomes active)
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshStatus()
        }
    }
}
