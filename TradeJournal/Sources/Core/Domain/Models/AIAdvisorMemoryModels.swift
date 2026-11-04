import Foundation

// MARK: - Advisor Commitment Record
/// Represents an immutable historical commitment of analysis & advice given by AI Coach to the trader.
public struct AdvisorCommitmentRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let symbol: String
    public let timestamp: Date
    public let bias: String // "BUY", "SELL", "FLAT"
    public let plannedEntry: String?
    public let invalidationSL: String?
    public let targetTP: String?
    public let takeProfit1: String?
    public let takeProfit2: String?
    public let volume: String?
    public let balance: String?
    public let riskRewardRatio: String?
    public let triggerCondition: String?
    public let thesisSummary: String
    public var linkedOrderTicket: String?
    public var linkedTradeKey: String?
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String,
        timestamp: Date = Date(),
        bias: String,
        plannedEntry: String? = nil,
        invalidationSL: String? = nil,
        targetTP: String? = nil,
        takeProfit1: String? = nil,
        takeProfit2: String? = nil,
        volume: String? = nil,
        balance: String? = nil,
        riskRewardRatio: String? = nil,
        triggerCondition: String? = nil,
        thesisSummary: String,
        linkedOrderTicket: String? = nil,
        linkedTradeKey: String? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.timestamp = timestamp
        self.bias = bias
        self.plannedEntry = plannedEntry
        self.invalidationSL = invalidationSL
        self.targetTP = targetTP
        self.takeProfit1 = takeProfit1 ?? targetTP
        self.takeProfit2 = takeProfit2
        self.volume = volume
        self.balance = balance
        self.riskRewardRatio = riskRewardRatio
        self.triggerCondition = triggerCondition
        self.thesisSummary = thesisSummary
        self.linkedOrderTicket = linkedOrderTicket
        self.linkedTradeKey = linkedTradeKey
    }
    
    /// Whether this commitment specifies an actionable execution setup (not FLAT/WAIT and has valid entry/SL parameters).
    public var hasActionableSetup: Bool {
        let b = bias.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if b.contains("FLAT") || b.contains("WAIT") || b.contains("NO_TRADE") || b.contains("STAND ASIDE") || b.contains("ĐỨNG NGOÀI") || b.isEmpty {
            return false
        }
        func isValidValue(_ val: String?) -> Bool {
            guard let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return false }
            let lower = v.lowercased()
            return lower != "<null>" && lower != "null" && lower != "none" && lower != "n/a" && lower != "nil" && lower != "không" && lower != "khong"
        }
        return isValidValue(plannedEntry) || isValidValue(invalidationSL) || isValidValue(takeProfit1) || isValidValue(targetTP)
    }
}

// MARK: - Trader AI Lesson Record
/// Persisted lessons extracted from losing trades, stopped out setups, or post-trade reviews.
public struct TraderAILesson: Codable, Identifiable, Sendable {
    public let id: String
    public let symbol: String?
    public let timestamp: Date
    public let setupType: String
    public let mistakeTag: String?
    public let lesson: String
    public let context: String?
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String? = nil,
        timestamp: Date = Date(),
        setupType: String,
        mistakeTag: String? = nil,
        lesson: String,
        context: String? = nil
    ) {
        self.id = id
        self.symbol = symbol?.uppercased()
        self.timestamp = timestamp
        self.setupType = setupType
        self.mistakeTag = mistakeTag
        self.lesson = lesson
        self.context = context
    }
}
