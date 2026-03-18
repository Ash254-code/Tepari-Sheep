import SwiftUI

struct WatchDraftRemoteView: View {

    @StateObject private var sender = WatchDraftSender()

    private let cols = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                Text("Draft Remote")
                    .font(.headline)

                Text(sender.statusText)
                    .font(.caption2)
                    .foregroundColor(sender.isReachable ? .secondary : .red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)

                LazyVGrid(columns: cols, spacing: 10) {

                    // Row 1
                    solidBtn("Left", "arrow.left", .blue) { sender.sendDraft(.left) }
                    solidBtn("Right", "arrow.right", .purple) { sender.sendDraft(.right) }

                    // Row 2
                    solidBtn("Straight", "arrow.up", .green) { sender.sendDraft(.straight) }
                    solidBtn("Far Right", "arrow.up.right", .orange) { sender.sendDraft(.farRight) }

                    // Row 3
                    solidBtn("Catch", "hand.raised", .red) { sender.sendCatch() }
                    solidBtn("Release", "hand.raised.slash", .green) { sender.sendRelease() }
                }
                .disabled(!sender.isReachable)
                .opacity(sender.isReachable ? 1.0 : 0.55)
            }
            .padding(.top, 8)
        }
        .onAppear { sender.refreshStatus() }
    }

    // MARK: - Solid colored button (watchOS-safe)

    private func solidBtn(
        _ title: String,
        _ systemImage: String,
        _ color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color)
            )
        }
        .buttonStyle(.plain) // ✅ prevents watchOS from overriding color
    }
}
