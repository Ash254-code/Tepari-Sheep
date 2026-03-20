import Foundation

enum EIDValidator {

    static func cleanedRaw(_ s: String) -> String {
        let digits = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        // If too short, just return cleaned digits
        guard digits.count > 3 else { return digits }

        let prefix = digits.prefix(3)
        let rest = digits.dropFirst(3)

        return "\(prefix) \(rest)"
    }
}
