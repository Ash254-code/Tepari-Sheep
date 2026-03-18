import SwiftUI

struct ConnectionMiniPill: View {
    let title: String
    let state: ConnectionState
    var compact: Bool = false

    // ✅ NEW
    var isActive: Bool = true

    // iPad-only tuning
    private var dotSize: CGFloat { compact ? 6 : 8 }
    private var hPad: CGFloat { compact ? 6 : 10 }
    private var vPad: CGFloat { compact ? 4 : 7 }
    private var minWidth: CGFloat { compact ? 0 : 34 }

    private var dotColor: Color {
        guard isActive else { return .secondary.opacity(0.45) }

        switch state {
        case .connected: return .green
        case .connecting, .reconnecting, .scanning: return .orange
        case .disconnected, .error: return .red
        }
    }

    private var textOpacity: Double { isActive ? 1.0 : 0.55 }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .opacity(textOpacity)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .frame(minWidth: minWidth)
        .fixedSize(horizontal: true, vertical: false)
        .background(.ultraThinMaterial)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .opacity(isActive ? 1.0 : 0.80)
    }
}
