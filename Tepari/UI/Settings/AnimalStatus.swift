import Foundation

enum AnimalStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case dry
    case pregnant
    case sold
    case dead
    case missing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dry: return "Dry"
        case .pregnant: return "Pregnant"
        case .sold: return "Sold"
        case .dead: return "Dead"
        case .missing: return "Missing"
        }
    }
}
