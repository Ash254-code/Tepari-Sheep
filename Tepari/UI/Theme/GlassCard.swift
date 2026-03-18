import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 12, x: 0, y: 4)
    }

    // MARK: - Styling

    private var cardFill: Color {
        scheme == .dark
            ? Color(.secondarySystemBackground)
            : Color(.systemBackground)
    }

    private var cardStroke: Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        Color.black.opacity(scheme == .dark ? 0.4 : 0.12)
    }
}
