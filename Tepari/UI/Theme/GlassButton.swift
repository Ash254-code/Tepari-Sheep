import SwiftUI
import UIKit

// =========================================================
// MARK: - Glass Button Style
// =========================================================

struct GlassButtonStyle: ButtonStyle {
    enum Size {
        case fullWidth
        case compact
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @EnvironmentObject private var settings: AppSettings

    var size: Size = .fullWidth

    /// Explicit tint for this button (don’t rely on EnvironmentValues.tint/accentColor)
    var tint: Color = .blue

    /// ✅ Optional min height so the GLASS background can actually grow
    var minHeight: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {

        let corner: CGFloat = (size == .compact ? 14 : 16)

        return configuration.label
            .font(size == .compact ? .subheadline.weight(.semibold) : .headline)

            // Keep your “compact” padding feel, but allow growth
            .padding(.vertical, size == .compact ? 9 : 12)
            .padding(.horizontal, size == .compact ? 12 : 14)

            // ✅ This is the key: apply minHeight INSIDE the style
            .frame(
                maxWidth: size == .fullWidth ? .infinity : nil,
                minHeight: minHeight,
                alignment: .center
            )

            // ✅ Tint behavior
            .foregroundStyle(isEnabled ? tint : Color.secondary)

            // ✅ Glass background (now stretches with minHeight)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(GlassTheme.surfaceMaterial(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(tint.opacity(isEnabled ? 0.10 : 0.0))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        isEnabled ? tint.opacity(0.45) : GlassTheme.surfaceStroke(scheme),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            // Press feedback
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : (isEnabled ? 1.0 : 0.55))

            // Haptics (press-down only)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                Haptics.tap(settings: settings)
            }
    }
}

// =========================================================
// MARK: - Haptics helper (centralised)
// =========================================================

enum Haptics {
    static func tap(settings: AppSettings) {
        guard settings.hapticsEnabled else { return }

        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch settings.hapticStrength {
        case .light:  style = .light
        case .medium: style = .medium
        case .heavy:  style = .heavy
        }

        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }
}

// =========================================================
// MARK: - Convenience modifier
// =========================================================

extension View {
    func glassButton(
        _ size: GlassButtonStyle.Size = .fullWidth,
        tint: Color = .blue,
        minHeight: CGFloat? = nil
    ) -> some View {
        buttonStyle(GlassButtonStyle(size: size, tint: tint, minHeight: minHeight))
    }
}
