import Foundation

/// 1:1 port from table `progress_rules` in `schema.pg.ts`
public struct ProgressRule: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var stage: String
    public var weekdaysJson: String // JSON array e.g. "[1,2,3,4,5]"
    public let createdAt: String
    public var archivedAt: String?
    
    public init(
        id: String = JournalIds.newId(),
        title: String,
        stage: String,
        weekdaysJson: String = "[1,2,3,4,5]",
        createdAt: String = JournalIds.nowIso(),
        archivedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.stage = stage
        self.weekdaysJson = weekdaysJson
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

/// 1:1 port from table `progress_checks` in `schema.pg.ts`
public struct ProgressCheck: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let ruleId: String
    public let date: String // YYYY-MM-DD
    public var done: Bool
    
    public init(
        id: String = JournalIds.newId(),
        ruleId: String,
        date: String,
        done: Bool
    ) {
        self.id = id
        self.ruleId = ruleId
        self.date = date
        self.done = done
    }
}
