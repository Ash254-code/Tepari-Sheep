import SwiftUI

enum GlassTheme {
    // Background gradient (subtle, “Apple-ish”)
    static func backgroundGradient(_ scheme: ColorScheme) -> LinearGradient {
        let top = scheme == .dark ? Color(red: 0.06, green: 0.07, blue: 0.10) : Color(red: 0.92, green: 0.95, blue: 0.99)
        let bottom = scheme == .dark ? Color(red: 0.02, green: 0.03, blue: 0.05) : Color(red: 0.86, green: 0.90, blue: 0.97)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Text tokens
    static func textPrimary(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : .black }
    static func textSecondary(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.75) : .black.opacity(0.65) }
    static func textTertiary(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45) }

    // Glass surfaces
    static func surfaceMaterial(_ scheme: ColorScheme) -> Material {
        // A slightly stronger material in light mode helps readability outdoors.
        scheme == .dark ? .ultraThinMaterial : .thinMaterial
    }

    static func surfaceStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.35)
    }

    static func shadowOpacity(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.35 : 0.12
    }

    // Status colors
    static let connected = Color.green
    static let warning = Color.orange
    static let disconnected = Color.red
}
