import Foundation

/// 1:1 port from table `missed_trades` in `schema.pg.ts`
public struct MissedTrade: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var symbol: String
    public var direction: String // "long" | "short"
    public var observedAt: String
    public var playbookId: String?
    public var entry: Decimal?
    public var stop: Decimal?
    public var target: Decimal?
    public var notes: String
    public let createdAt: String
    public var archivedAt: String?
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String,
        direction: String,
        observedAt: String = JournalIds.nowIso(),
        playbookId: String? = nil,
        entry: Decimal? = nil,
        stop: Decimal? = nil,
        target: Decimal? = nil,
        notes: String = "",
        createdAt: String = JournalIds.nowIso(),
        archivedAt: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.direction = direction
        self.observedAt = observedAt
        self.playbookId = playbookId
        self.entry = entry
        self.stop = stop
        self.target = target
        self.notes = notes
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}
