import Foundation

extension AppSettings {
    /// Determines the effective stability based on the current settings.
    ///
    /// Returns true if `forceStable` is enabled, otherwise evaluates stability
    /// according to the `stabilitySource` setting:
    /// - `.scaleOnly`: returns `scaleStable`
    /// - `.inferredOnly`: returns `inferredStable`
    /// - `.scaleOrInferred`: returns `scaleStable || inferredStable`
    ///
    /// This method centralizes the stability policy used by `SessionViewModel`.
    func effectiveStable(scaleStable: Bool, inferredStable: Bool) -> Bool {
        if forceStable {
            return true
        }
        switch stabilitySource {
        case .scaleOnly:
            return scaleStable
        case .inferredOnly:
            return inferredStable
        case .scaleOrInferred:
            return scaleStable || inferredStable
        }
    }
}
