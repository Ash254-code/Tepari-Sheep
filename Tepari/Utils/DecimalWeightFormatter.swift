import Foundation

enum DecimalWeightFormatter {
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
