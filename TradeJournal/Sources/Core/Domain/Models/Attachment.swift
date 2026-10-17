import Foundation

/// 1:1 port from table `attachments` in `schema.pg.ts`
public struct Attachment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let ownerType: String
    public let ownerId: String
    public var name: String
    public var mime: String
    public var size: Int
    public var storagePath: String
    public var status: String // "pending" | "ready"
    public let createdAt: String
    
    public init(
        id: String = JournalIds.newId(),
        ownerType: String,
        ownerId: String,
        name: String,
        mime: String,
        size: Int,
        storagePath: String,
        status: String = "ready",
        createdAt: String = JournalIds.nowIso()
    ) {
        self.id = id
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.name = name
        self.mime = mime
        self.size = size
        self.storagePath = storagePath
        self.status = status
        self.createdAt = createdAt
    }
}
