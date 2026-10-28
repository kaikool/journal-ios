import Foundation

public struct Playbook: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var rules: [String]
    public var targetWinRate: Double?
    public var color: String?
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date
    
    public var title: String {
        get { name }
        set { name = newValue }
    }
    
    public init(
        id: String = JournalIds.newId(),
        name: String = "",
        title: String? = nil,
        description: String = "",
        rules: [String] = [],
        targetWinRate: Double? = nil,
        color: String? = nil,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = title ?? name
        self.description = description
        self.rules = rules
        self.targetWinRate = targetWinRate
        self.color = color
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description, rules, targetWinRate, color, isDefault, createdAt, updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.rules = try container.decodeIfPresent([String].self, forKey: .rules) ?? []
        self.targetWinRate = try container.decodeIfPresent(Double.self, forKey: .targetWinRate)
        self.color = try container.decodeIfPresent(String.self, forKey: .color)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(rules, forKey: .rules)
        try container.encodeIfPresent(targetWinRate, forKey: .targetWinRate)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct PlaybookRuleAssessment: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(playbookId)-\(tradeKey)-\(rule)" }
    public let tradeKey: String
    public let playbookId: String
    public let rule: String
    public let followed: Bool
    
    public init(tradeKey: String, playbookId: String, rule: String, followed: Bool) {
        self.tradeKey = tradeKey
        self.playbookId = playbookId
        self.rule = rule
        self.followed = followed
    }
}

/// Equivalent to `{ id: string; rules: string[] }` in `packages/core/src/adherence.ts` `{ id: string; rules: string[] }` trong `packages/core/src/adherence.ts`
public struct PlaybookRuleSet: Identifiable, Sendable, Equatable {
    public let id: String
    public let rules: [String]
    
    public init(id: String, rules: [String]) {
        self.id = id
        self.rules = rules
    }
}
