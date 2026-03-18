import Foundation

enum EIDValidator {
    // For now: store exact; no normalization besides trimming trailing newlines if they appear.
    static func cleanedRaw(_ s: String) -> String {
        s.trimmingCharacters(in: .newlines)
    }
}
