import Foundation

struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var farmID: UUID?
    var mobID: UUID?
    var createdAt: Date

    // =========================================================
    // MARK: Session Types (high-level purpose)
    // =========================================================

    /// Main purpose of the session.
    /// Used by the UI and data layer to apply special behaviors
    /// (e.g. Transfer between PICs, Sale removal).
    var kind: Kind = .general

    /// Extra details for specific session kinds.
    /// (Kept optional so existing sessions decode safely.)
    var transfer: TransferInfo? = nil
    var sale: SaleInfo? = nil

    // =========================================================
    // MARK: Nested Types
    // =========================================================

    enum Kind: String, Codable, CaseIterable, Equatable {
        /// Normal sessions (scan/weigh/draft/treat/traits etc.)
        case general

        /// Transfer animals between PICs (Greenwood Park ↔︎ Mahanewo).
        case transfer

        /// Confirm sold animals; remove from current animals.
        case sale
    }

    struct TransferInfo: Codable, Equatable {
        /// Source PIC the animals are currently registered under.
        var fromPIC: String
        /// Destination PIC to move animals to.
        var toPIC: String
    }

    struct SaleInfo: Codable, Equatable {
        /// Optional free text reference (agent, sale yard, buyer, invoice, etc.)
        var reference: String?
        /// Optional sale date (defaults to createdAt if nil).
        var saleDate: Date?
    }

    // =========================================================
    // MARK: Init
    // =========================================================

    init(
        id: UUID = UUID(),
        name: String,
        farmID: UUID? = nil,
        mobID: UUID? = nil,
        createdAt: Date = Date(),
        kind: Kind = .general,
        transfer: TransferInfo? = nil,
        sale: SaleInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.farmID = farmID
        self.mobID = mobID
        self.createdAt = createdAt
        self.kind = kind
        self.transfer = transfer
        self.sale = sale
    }
}
