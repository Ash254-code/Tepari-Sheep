import SwiftUI

struct GlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            GlassTheme.backgroundGradient(scheme)
                .ignoresSafeArea()

            // Subtle “mist” overlay to add depth
            RadialGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.06 : 0.25),
                    Color.clear
                ],
                center: .top,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()
            .blendMode(.screen)
        }
        // ✅ Background must never intercept taps (fixes iPad “buttons not selectable”)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
