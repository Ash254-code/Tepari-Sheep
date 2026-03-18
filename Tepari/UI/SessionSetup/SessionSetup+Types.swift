import Foundation

extension SessionSetupView {

    enum SessionType: String, CaseIterable, Identifiable, Hashable {
        case scan = "Scan"
        case weigh = "Weigh"
        case fleeceWeigh = "Fleece Weigh"
        case traitInput = "Trait Input"
        case draft = "Draft"
        case treatment = "Treatment"
        case lambMarking = "Lamb Marking"
        case pregTesting = "Preg Testing"

        // ✅ New session types
        case transfer = "Transfer"
        case sale = "Sale"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .scan: return "qrcode.viewfinder"
            case .weigh: return "scalemass"
            case .fleeceWeigh: return "tshirt"
            case .traitInput: return "list.bullet.rectangle"
            case .draft: return "arrow.triangle.branch"
            case .treatment: return "syringe"
            case .lambMarking: return "tag"
            case .pregTesting: return "waveform.path.ecg"

            // ✅ Transfer / Sale icons
            case .transfer: return "arrow.left.arrow.right"
            case .sale: return "cart.fill"
            }
        }
    }
}
