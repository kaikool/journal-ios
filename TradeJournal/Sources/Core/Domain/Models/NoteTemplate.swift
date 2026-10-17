import Foundation

/// 1:1 port from table `note_templates` in `schema.pg.ts`
public struct NoteTemplate: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var content: String
    
    public init(id: String = JournalIds.newId(), name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
    }
}
