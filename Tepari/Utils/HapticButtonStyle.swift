import SwiftUI

/// Global haptics that never steals the Button action.
/// Fires on press-down via configuration.isPressed (no gestures).
struct HapticButtonStyle: ButtonStyle {

    @EnvironmentObject private var settings: AppSettings

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }   // only on press-down
                HapticHelper.tap(using: settings)
            }
    }
}
