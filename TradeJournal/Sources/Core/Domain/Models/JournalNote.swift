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
