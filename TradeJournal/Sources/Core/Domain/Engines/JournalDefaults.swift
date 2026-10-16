import Foundation

public struct FeeRule: Codable, Equatable, Identifiable {
    public let id: String
    public let accountId: String
    public let symbol: String
    public let amount: Decimal
    public let mode: String // "execution" | "unit"
    
    public init(id: String = UUID().uuidString, accountId: String, symbol: String, amount: Decimal, mode: String = "unit") {
        self.id = id
        self.accountId = accountId
        self.symbol = symbol
        self.amount = amount
        self.mode = mode
    }
}

public struct RiskRule: Codable, Equatable, Identifiable {
    public let id: String
    public let accountId: String
    public let symbol: String
    public let stop: Decimal
    public let target: Decimal
    public let mode: String // "price" | "percent"
    
    public init(id: String = UUID().uuidString, accountId: String, symbol: String, stop: Decimal, target: Decimal, mode: String = "price") {
        self.id = id
        self.accountId = accountId
        self.symbol = symbol
        self.stop = stop
        self.target = target
        self.mode = mode
    }
}

public struct JournalDefaults: Codable, Equatable {
    public var breakeven: Decimal
    public var breakevenMode: String // "money" | "percent"
    public var feeRules: [FeeRule]
    public var riskRules: [RiskRule]
    
    public static let empty = JournalDefaults(breakeven: 0, breakevenMode: "money", feeRules: [], riskRules: [])
    
    public init(breakeven: Decimal = 0, breakevenMode: String = "money", feeRules: [FeeRule] = [], riskRules: [RiskRule] = []) {
        self.breakeven = breakeven
        self.breakevenMode = breakevenMode
        self.feeRules = feeRules
        self.riskRules = riskRules
    }
}

/// Port 1:1 từ `apps/web/src/lib/journal-defaults.ts`.
public enum JournalDefaultsEngine {
    
    public static func matchesRule(ruleAccountId: String, ruleSymbol: String, accountId: String, symbol: String) -> Bool {
        let accountMatches = ruleAccountId.isEmpty || ruleAccountId == accountId
        let symbolMatches = ruleSymbol.isEmpty || ruleSymbol.caseInsensitiveCompare(symbol) == .orderedSame
        return accountMatches && symbolMatches
    }
    
    public static func defaultFee(
        fee: Decimal,
        quantity: Decimal,
        accountId: String,
        symbol: String,
        defaults: JournalDefaults
    ) -> Decimal {
        if fee != 0 { return fee }
        let rule = defaults.feeRules.first { matchesRule(ruleAccountId: $0.accountId, ruleSymbol: $0.symbol, accountId: accountId, symbol: symbol) }
        guard let r = rule else { return fee }
        return r.amount * (r.mode == "unit" ? quantity : 1)
    }
    
    public static func defaultRisk(
        entry: Decimal,
        direction: TradeDirection,
        accountId: String,
        symbol: String,
        defaults: JournalDefaults
    ) -> (stopLoss: Decimal?, profitTarget: Decimal?) {
        let rule = defaults.riskRules.first { matchesRule(ruleAccountId: $0.accountId, ruleSymbol: $0.symbol, accountId: accountId, symbol: symbol) }
        guard let r = rule else { return (nil, nil) }
        let unit: Decimal = r.mode == "percent" ? abs(entry) / 100 : 1
        let sign: Decimal = direction == .long ? 1 : -1
        let stopLoss = entry - sign * r.stop * unit
        let profitTarget = entry + sign * r.target * unit
        return (stopLoss, profitTarget)
    }
}
