import Foundation

struct RawLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let line: String
}
