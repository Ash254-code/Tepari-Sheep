import Foundation

extension SessionSetupView {

    /// Builds TreatmentTemplate from preset legacy dose string.
    func parseLegacyDose(_ s: String, fallbackUnit: DoseUnit) -> (value: String, unit: DoseUnit) {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return ("", fallbackUnit) }

        if raw.contains("/") { return (raw, fallbackUnit) }

        let parts = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count >= 2 {
            let maybeUnit = parts.last!.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = DoseUnit(rawValue: maybeUnit) {
                let v = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                return (v, u)
            }
        }

        for u in DoseUnit.allCases {
            if raw.hasSuffix(u.rawValue) {
                let v = raw.replacingOccurrences(of: u.rawValue, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (v, u)
            }
        }

        return (raw, fallbackUnit)
    }
}
