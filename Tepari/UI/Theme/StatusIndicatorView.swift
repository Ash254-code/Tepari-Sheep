import SwiftUI

struct StatusIndicatorView: View {
    let title: String
    let state: ConnectionState

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {

            Circle()
                .frame(width: 10, height: 10)
                .foregroundStyle(state.dotColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(state.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(GlassTheme.surfaceMaterial(scheme))
        .overlay(
            Capsule(style: .continuous)
                .stroke(GlassTheme.surfaceStroke(scheme), lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
    }
}
