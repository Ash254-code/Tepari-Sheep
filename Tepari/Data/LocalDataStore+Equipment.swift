import Foundation

extension LocalDataStore {

    enum Equipment: String, CaseIterable, Codable, Hashable, Identifiable {
        case handler = "Handler"
        case draft = "Draft"
        case scanner = "Scanner"
        case scales = "Scales"
        case stickReader = "Stick Reader"
        case fleeceScales = "Fleece Scales"
        case tepariGun = "Tepari Dosing Gun"   // ✅ add this

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .handler:      return "person.fill"
            case .draft:        return "arrow.triangle.branch"
            case .scanner:      return "qrcode.viewfinder"
            case .scales:       return "scalemass"
            case .stickReader:  return "dot.radiowaves.left.and.right"
            case .fleeceScales: return "tshirt"
            case .tepariGun:    return "g.circle"   // ✅ add this
            }
        }
    }
}
