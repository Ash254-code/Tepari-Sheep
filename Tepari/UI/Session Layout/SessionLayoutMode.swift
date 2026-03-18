import Foundation

enum SessionLayoutMode: String, Codable, Hashable {
    case scan
    case scanWeigh
    case scanDraft
    case scanWeighDraft

    // NEW layouts (scan is top-of-screen so tiles are weigh/draft/treat)
    case scanWeighTreat
    case scanWeighTreatDraft

    case stickReader
    case transferSale
    case treat
    case traitInput
    case unknown
}
