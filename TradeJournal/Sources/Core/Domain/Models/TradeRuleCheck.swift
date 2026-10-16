import Foundation

/// 1:1 port từ bảng `trade_rule_checks` trong `schema.pg.ts`
public struct TradeRuleCheck: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let tradeKey: String
    public let playbookId: String
    public let rule: String
    public let followed: Bool
    
    public init(
        id: String = JournalIds.newId(),
        tradeKey: String,
        playbookId: String,
        rule: String,
        followed: Bool
    ) {
        self.id = id
        self.tradeKey = tradeKey
        self.playbookId = playbookId
        self.rule = rule
        self.followed = followed
    }
}

public typealias RuleCheck = PlaybookRuleAssessment
