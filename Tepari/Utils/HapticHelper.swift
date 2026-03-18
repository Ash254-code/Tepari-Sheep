import UIKit

/// Central haptics helper (respects AppSettings toggles + strength).
enum HapticHelper {

    // MARK: - Public

    static func tap(using settings: AppSettings?) {
        guard let settings, settings.hapticsEnabled else { return }
        impact(style: settings.hapticStrength.uiStyle)
    }

    static func success(using settings: AppSettings?) {
        guard let settings, settings.hapticsEnabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }

    static func warning(using settings: AppSettings?) {
        guard let settings, settings.hapticsEnabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.warning)
    }

    static func error(using settings: AppSettings?) {
        guard let settings, settings.hapticsEnabled else { return }
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
    }

    // MARK: - Private

    private static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }
}
