import Foundation

public struct Playbook: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var rules: [String]
    public var targetWinRate: Double?
    public var color: String?
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
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = title ?? name
        self.description = description
        self.rules = rules
        self.targetWinRate = targetWinRate
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
