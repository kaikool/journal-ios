import Foundation

// MARK: - Supabase Playbook, Journal, Notebook & Progress DTOs
public struct SupabasePlaybookRecord: Codable {
    public let id: String
    public let name: String
    public let description: String
    public let rulesJson: String
    public let createdAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description
        case rulesJson = "rules_json"
        case createdAt = "created_at"
    }
    
    public init(playbook: Playbook) {
        self.id = playbook.id
        self.name = playbook.name
        self.description = playbook.description
        self.rulesJson = (try? String(data: JSONEncoder().encode(playbook.rules), encoding: .utf8)) ?? "[]"
        self.createdAt = Formatters.iso8601String(from: playbook.createdAt, fractionalSeconds: false)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Playbook"
        self.description = c.decodeString(forKeys: ["description"]) ?? ""
        if let str = c.decodeString(forKeys: ["rules_json", "rulesJson", "rules"]) {
            self.rulesJson = str
        } else if let arr = c.decodeArray(type: String.self, forKeys: ["rules_json", "rulesJson", "rules"]) {
            self.rulesJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.rulesJson = "[]"
        }
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toPlaybook() -> Playbook {
        let parsedRules = (try? JSONDecoder().decode([String].self, from: Data(rulesJson.utf8))) ?? []
        let parsedCreated = FlexibleDateParser.parse(createdAt) ?? Date()
        return Playbook(
            id: id,
            name: name,
            description: description,
            rules: parsedRules,
            createdAt: parsedCreated,
            updatedAt: parsedCreated
        )
    }
}

public struct SupabaseJournalDayRecord: Codable {
    public let date: String
    public let note: String
    public let updatedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case date
        case note
        case updatedAt = "updated_at"
    }
    
    public init(journalNote: JournalNote) {
        self.date = journalNote.date
        self.note = journalNote.content
        self.updatedAt = Formatters.iso8601String(from: journalNote.updatedAt, fractionalSeconds: false)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.date = c.decodeString(forKeys: ["date"]) ?? ""
        self.note = c.decodeString(forKeys: ["note", "content"]) ?? ""
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"]) ?? JournalIds.nowIso()
    }
    
    public func toJournalNote() -> JournalNote {
        let parsedDate = FlexibleDateParser.parse(updatedAt) ?? Date()
        return JournalNote(
            date: date,
            content: note,
            createdAt: parsedDate,
            updatedAt: parsedDate
        )
    }
}

public struct SupabaseAttachmentRecord: Codable {
    public let id: String
    public let ownerType: String
    public let ownerId: String
    public let name: String
    public let mime: String
    public let size: Int
    public let storagePath: String
    public let status: String
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, mime, size, status
        case ownerType = "owner_type"
        case ownerId = "owner_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
    
    public init(attachment: Attachment) {
        self.id = attachment.id
        self.ownerType = attachment.ownerType
        self.ownerId = attachment.ownerId
        self.name = attachment.name
        self.mime = attachment.mime
        self.size = attachment.size
        self.storagePath = attachment.storagePath
        self.status = attachment.status
        self.createdAt = attachment.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.ownerType = c.decodeString(forKeys: ["owner_type", "ownerType"]) ?? "trade"
        self.ownerId = c.decodeString(forKeys: ["owner_id", "ownerId"]) ?? ""
        self.name = c.decodeString(forKeys: ["name"]) ?? "Attachment"
        self.mime = c.decodeString(forKeys: ["mime"]) ?? "image/png"
        self.size = c.decodeInt(forKeys: ["size"]) ?? 0
        self.storagePath = c.decodeString(forKeys: ["storage_path", "storagePath"]) ?? ""
        self.status = c.decodeString(forKeys: ["status"]) ?? "ready"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func toAttachment() -> Attachment {
        return Attachment(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            name: name,
            mime: mime,
            size: size,
            storagePath: storagePath,
            status: status,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

// MARK: - Supabase Notebook Folder Record
public struct SupabaseFolderRecord: Codable {
    public let id: String
    public let name: String
    public let kind: String
    public let createdAt: String
    public let deletedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, kind
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
    
    public init(folder: NotebookFolder) {
        self.id = folder.id
        self.name = folder.name
        self.kind = folder.kind
        self.createdAt = folder.createdAt
        self.deletedAt = folder.deletedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Folder"
        self.kind = c.decodeString(forKeys: ["kind"]) ?? "user"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.deletedAt = c.decodeString(forKeys: ["deleted_at", "deletedAt"])
    }
    
    public func toFolder() -> NotebookFolder {
        NotebookFolder(
            id: id,
            name: name,
            kind: kind,
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }
}

// MARK: - Supabase Notebook Note Record
public struct SupabaseNoteRecord: Codable {
    public let id: String
    public let folderId: String
    public let title: String
    public let content: String
    public let tagsJson: String?
    public let tradeKey: String?
    public let dayDate: String?
    public let createdAt: String
    public let updatedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, title, content
        case folderId = "folder_id"
        case tagsJson = "tags_json"
        case tradeKey = "trade_key"
        case dayDate = "day_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(note: NotebookNote) {
        self.id = note.id
        self.folderId = note.folderId
        self.title = note.title
        self.content = note.content
        self.tagsJson = note.tagsJson
        self.tradeKey = note.tradeKey
        self.dayDate = note.dayDate
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.folderId = c.decodeString(forKeys: ["folder_id", "folderId"]) ?? ""
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.content = c.decodeString(forKeys: ["content"]) ?? ""
        self.tagsJson = c.decodeString(forKeys: ["tags_json", "tagsJson"])
        self.tradeKey = c.decodeString(forKeys: ["trade_key", "tradeKey"])
        self.dayDate = c.decodeString(forKeys: ["day_date", "dayDate"])
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"]) ?? JournalIds.nowIso()
    }
    
    public func toNote() -> NotebookNote {
        NotebookNote(
            id: id,
            folderId: folderId,
            title: title,
            content: content,
            tagsJson: tagsJson,
            tradeKey: tradeKey,
            dayDate: dayDate,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Supabase Progress Rule Record
public struct SupabaseProgressRuleRecord: Codable {
    public let id: String
    public let title: String
    public let stage: String
    public let weekdaysJson: String
    public let createdAt: String
    public let archivedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, title, stage
        case weekdaysJson = "weekdays_json"
        case createdAt = "created_at"
        case archivedAt = "archived_at"
    }
    
    public init(rule: ProgressRule) {
        self.id = rule.id
        self.title = rule.title
        self.stage = rule.stage
        self.weekdaysJson = rule.weekdaysJson
        self.createdAt = rule.createdAt
        self.archivedAt = rule.archivedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.stage = c.decodeString(forKeys: ["stage"]) ?? "Before trading"
        self.weekdaysJson = c.decodeString(forKeys: ["weekdays_json", "weekdaysJson"]) ?? "[1,2,3,4,5]"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.archivedAt = c.decodeString(forKeys: ["archived_at", "archivedAt"])
    }
    
    public func toRule() -> ProgressRule {
        ProgressRule(
            id: id,
            title: title,
            stage: stage,
            weekdaysJson: weekdaysJson,
            createdAt: createdAt,
            archivedAt: archivedAt
        )
    }
}

// MARK: - Supabase Progress Check Record
public struct SupabaseProgressCheckRecord: Codable {
    public let id: String
    public let ruleId: String
    public let date: String
    public let done: Bool
    
    private enum CodingKeys: String, CodingKey {
        case id, date, done
        case ruleId = "rule_id"
    }
    
    public init(check: ProgressCheck) {
        self.id = check.id
        self.ruleId = check.ruleId
        self.date = check.date
        self.done = check.done
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.ruleId = c.decodeString(forKeys: ["rule_id", "ruleId"]) ?? ""
        self.date = c.decodeString(forKeys: ["date"]) ?? ""
        self.done = c.decodeBool(forKeys: ["done"]) ?? false
    }
    
    public func toCheck() -> ProgressCheck {
        ProgressCheck(
            id: id,
            ruleId: ruleId,
            date: date,
            done: done
        )
    }
}