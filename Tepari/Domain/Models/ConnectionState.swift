import SwiftUI

enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case reconnecting
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var dotColor: Color {
        switch self {
        case .connected: return GlassTheme.connected
        case .scanning, .connecting, .reconnecting: return GlassTheme.warning
        case .disconnected, .error: return GlassTheme.disconnected
        }
    }
}
