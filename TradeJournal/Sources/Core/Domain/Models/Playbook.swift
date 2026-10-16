import Foundation

public struct Playbook: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var rules: [String]
    public var targetWinRate: Double?
    public var color: String?
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        rules: [String] = [],
        targetWinRate: Double? = nil,
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
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

public struct PlaybookAdherenceSummary: Identifiable, Sendable {
    public var id: String { playbook.id }
    public let playbook: Playbook
    public let totalTrades: Int
    public let followedTradesCount: Int
    public let brokenTradesCount: Int
    public let unassessedTradesCount: Int
    public let overallAdherenceRate: Double?
    public let netPnlWhenFollowed: Decimal
    public let netPnlWhenBroken: Decimal
    
    public init(
        playbook: Playbook,
        totalTrades: Int,
        followedTradesCount: Int,
        brokenTradesCount: Int,
        unassessedTradesCount: Int,
        overallAdherenceRate: Double?,
        netPnlWhenFollowed: Decimal,
        netPnlWhenBroken: Decimal
    ) {
        self.playbook = playbook
        self.totalTrades = totalTrades
        self.followedTradesCount = followedTradesCount
        self.brokenTradesCount = brokenTradesCount
        self.unassessedTradesCount = unassessedTradesCount
        self.overallAdherenceRate = overallAdherenceRate
        self.netPnlWhenFollowed = netPnlWhenFollowed
        self.netPnlWhenBroken = netPnlWhenBroken
    }
}
