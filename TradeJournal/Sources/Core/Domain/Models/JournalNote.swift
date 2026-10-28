import Foundation

public struct JournalNote: Identifiable, Codable, Equatable, Sendable {
    public var id: String { date } // "YYYY-MM-DD"
    public let date: String
    public var content: String
    public var rating: Int? // 1-5 scale
    public var mood: String?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        date: String,
        content: String = "",
        rating: Int? = nil,
        mood: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.date = date
        self.content = content
        self.rating = rating
        self.mood = mood
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 1:1 port from table `folders` in `schema.pg.ts`
public struct NotebookFolder: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: String // "system" | "user"
    public let createdAt: String
    public var deletedAt: String?
    
    public init(
        id: String = JournalIds.newId(),
        name: String,
        kind: String = "user",
        createdAt: String = JournalIds.nowIso(),
        deletedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

/// 1:1 port from table `notes` in `schema.pg.ts`
public struct NotebookNote: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var folderId: String
    public var title: String
    public var content: String
    public var tagsJson: String?
    public var tradeKey: String?
    public var dayDate: String?
    public let createdAt: String
    public var updatedAt: String
    
    public init(
        id: String = JournalIds.newId(),
        folderId: String,
        title: String = "",
        content: String = "",
        tagsJson: String? = nil,
        tradeKey: String? = nil,
        dayDate: String? = nil,
        createdAt: String = JournalIds.nowIso(),
        updatedAt: String = JournalIds.nowIso()
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.content = content
        self.tagsJson = tagsJson
        self.tradeKey = tradeKey
        self.dayDate = dayDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

