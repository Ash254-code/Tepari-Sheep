import Foundation

final class T1HTTPTransport: TransportProtocol {

    var onReceiveLine: ((String) -> Void)?
    var onStateChange: ((ConnectionState) -> Void)?

    var isConnected: Bool {
        state == .connected
    }

    private let host: String
    private let port: UInt16

    private var pollTask: Task<Void, Never>?
    private var state: ConnectionState = .disconnected {
        didSet {
            DispatchQueue.main.async { [onStateChange] in
                onStateChange?(self.state)
            }
        }
    }

    private var lastWeightLine: String?
    private var lastCombinedLine: String?
    private var lastEID: String?

    private let pollInterval: TimeInterval = 0.75

    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 6

    private let candidatePaths = ["/", "/data", "/json", "/status", "/live"]
    private var lockedPath: String?

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func connect() {
        disconnect()

        state = .connecting
        consecutiveFailures = 0
        lastWeightLine = nil
        lastCombinedLine = nil
        lastEID = nil
        lockedPath = nil

        pollTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        state = .disconnected
    }

    private func pollOnce() async {
        let pathsToTry = lockedPath.map { [$0] } ?? candidatePaths

        for path in pathsToTry {
            guard let url = URL(string: "http://\(host):\(port)\(path)") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 6.0
                request.cachePolicy = .reloadIgnoringLocalCacheData

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    continue
                }

                guard (200...299).contains(http.statusCode) else {
                    continue
                }

                let payload = try JSONDecoder().decode(T1Payload.self, from: data)

                lockedPath = path
                consecutiveFailures = 0

                emitDebug("[DBG-HTTP] OK \(path)")

                emitLines(from: payload)

                if state != .connected {
                    state = .connected
                }
                return

            } catch {
                emitDebug("[DBG-HTTP] FAIL \(path) \(error.localizedDescription)")
                continue
            }
        }

        registerFailure("No valid HTTP JSON endpoint responded")
    }

    private func registerFailure(_ message: String) {
        consecutiveFailures += 1

        if consecutiveFailures == 1, state == .connected {
            state = .reconnecting
        }

        if consecutiveFailures >= maxConsecutiveFailures {
            state = .error(message)
        }
    }

    private func emitLines(from payload: T1Payload) {
        let weightValue = payload.weight ?? parseWeight(from: payload.weightRaw) ?? 0
        let weightLine = formatWeight(weightValue)

        if weightLine != lastWeightLine {
            lastWeightLine = weightLine
            emitLine(weightLine)
        }

        let eid = cleanedEID(payload.eid) ?? cleanedEID(payload.eidRaw)

        if let eid, !eid.isEmpty {
            let combined = "\(formatWeight(weightValue)),\(eid)"

            if combined != lastCombinedLine {
                lastCombinedLine = combined
                emitLine(combined)
            }

            if eid != lastEID {
                lastEID = eid
            }
        }
    }

    private func emitLine(_ line: String) {
        DispatchQueue.main.async { [onReceiveLine] in
            onReceiveLine?(line)
        }
    }

    private func emitDebug(_ line: String) {
        DispatchQueue.main.async { [onReceiveLine] in
            onReceiveLine?(line)
        }
    }

    private func formatWeight(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func cleanedEID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    private func parseWeight(from raw: String?) -> Double? {
        guard let raw else { return nil }

        if let direct = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return direct
        }

        let pattern = #"(-?\d{1,5}(?:\.\d{1,3})?)"#
        if let range = raw.range(of: pattern, options: .regularExpression) {
            return Double(String(raw[range]))
        }

        return nil
    }
}

private struct T1Payload: Decodable {
    let weight: Double?
    let eid: String?
    let weightRaw: String?
    let eidRaw: String?
    let wifi: String?
    let ip: String?
}
