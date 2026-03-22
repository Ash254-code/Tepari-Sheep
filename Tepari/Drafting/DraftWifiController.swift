import Foundation
import SwiftUI
import Network

@MainActor
enum DraftWifiController {

    // -------------------------------------------------
    // MARK: - Discovery
    // -------------------------------------------------

    private static let serviceType = "_tepari-drafter._tcp"

    private static var browser: NWBrowser?
    private static var discoveredURL: String?

    @AppStorage("drafter_base_url") private static var baseURL: String = ""

    static func startDiscovery() {
        if browser != nil { return }

        let params = NWParameters()
        params.includePeerToPeer = false

        let newBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)
        browser = newBrowser

        newBrowser.stateUpdateHandler = { state in
            print("Drafter browser state:", state)
        }

        newBrowser.browseResultsChangedHandler = { results, _ in
            guard let first = results.first else {
                Task { @MainActor in
                    discoveredURL = nil
                    print("No drafter found")
                }
                return
            }

            let resolvedURL: String? = {
                switch first.endpoint {
                case .service(let name, _, _, _):
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty else { return nil }
                    return "http://\(trimmedName).local"

                case .hostPort(let host, let port):
                    return "http://\(host):\(port.rawValue)"

                default:
                    return nil
                }
            }()

            Task { @MainActor in
                guard let resolvedURL, !resolvedURL.isEmpty else {
                    discoveredURL = nil
                    print("No drafter found")
                    return
                }

                discoveredURL = resolvedURL
                baseURL = resolvedURL
                print("Drafter discovered:", resolvedURL)
            }
        }

        newBrowser.start(queue: .main)
    }

    static func stopDiscovery() {
        browser?.cancel()
        browser = nil
        discoveredURL = nil
    }

    static func setBaseURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = trimmed
    }

    static func hasDiscoveredDrafter() -> Bool {
        if let discoveredURL, !discoveredURL.isEmpty {
            return true
        }
        return false
    }

    private static func currentBaseURL() -> String {
        if let discoveredURL, !discoveredURL.isEmpty {
            return discoveredURL
        }
        return baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // -------------------------------------------------
    // MARK: - Control
    // -------------------------------------------------

    static func fireGate(_ gate: Int) {
        holdGate(gate)
    }

    static func holdGate(_ gate: Int) {
        guard (1...8).contains(gate) else { return }
        sendRequest(path: "/G\(gate)", label: "WiFi gate \(gate)")
    }

    static func releaseGate(_ gate: Int) {
        guard (1...8).contains(gate) else { return }
        sendRequest(path: "/OFF\(gate)", label: "WiFi gate \(gate) OFF")
    }

    static func releaseAllGates() {
        sendRequest(path: "/ALLOFF", label: "WiFi ALLOFF")
    }

    static func fetchStatus() {
        sendRequest(path: "/STATUS", label: "WiFi STATUS")
    }

    // -------------------------------------------------
    // MARK: - Catch / Release
    // -------------------------------------------------

    // Existing firmware-timed endpoints
    static func pulseCatch() {
        sendRequest(path: "/CATCH", label: "WiFi CATCH")
    }

    static func pulseRelease() {
        sendRequest(path: "/RELEASE", label: "WiFi RELEASE")
    }

    // App-timed pulse versions (no ESP reflashing needed)
    static func pulseCatchForApp(seconds: Double = 1.0) {
        holdGate(3)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            releaseGate(3)
        }
    }

    static func pulseReleaseForApp(seconds: Double = 1.0) {
        holdGate(4)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            releaseGate(4)
        }
    }

    // -------------------------------------------------
    // MARK: - Pause Relay
    // -------------------------------------------------

    private static let pauseRelayGate = 7

    static func setPauseRelay(paused: Bool) {
        if paused {
            holdGate(pauseRelayGate)
        } else {
            releaseGate(pauseRelayGate)
        }
    }

    private static func sendRequest(path: String, label: String) {
        let trimmed = currentBaseURL()

        guard !trimmed.isEmpty else {
            print("No drafter discovered yet")
            return
        }

        let full = "\(trimmed)\(path)"
        print("Firing URL:", full)

        guard let url = URL(string: full) else {
            print("Bad drafter URL:", full)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 2.0
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                print("\(label) ERROR:", err.localizedDescription)
            } else if let http = resp as? HTTPURLResponse {
                print("\(label) HTTP:", http.statusCode)
                if let data, let body = String(data: data, encoding: .utf8) {
                    print("\(label) BODY:", body)
                }
            } else {
                print("\(label) OK")
            }
        }.resume()
    }
}
