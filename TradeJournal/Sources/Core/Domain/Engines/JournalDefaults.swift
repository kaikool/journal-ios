import Foundation

public struct FeeRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var accountId: String
    public var symbol: String
    public var amount: Decimal
    public var mode: String // "execution" | "unit"
    
    public init(id: String = UUID().uuidString, accountId: String = "", symbol: String = "", amount: Decimal = 0, mode: String = "unit") {
        self.id = id
        self.accountId = accountId
        self.symbol = symbol
        self.amount = amount
        self.mode = mode
    }
}

public struct RiskRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var accountId: String
    public var symbol: String
    public var stop: Decimal
    public var target: Decimal
    public var mode: String // "price" | "percent"
    
    public init(id: String = UUID().uuidString, accountId: String = "", symbol: String = "", stop: Decimal = 1, target: Decimal = 2, mode: String = "price") {
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

/// Ported 1:1 from `apps/web/src/lib/journal-defaults.ts`.
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
        return defaultFeePerUnit(
            quantity: quantity,
            accountId: accountId,
            symbol: symbol,
            defaults: defaults
        )
    }
    
    /// Fee configured for one side of a fill (entry and exit are charged separately).
    /// `unit` mode scales the amount with the traded quantity, `execution` mode charges it once.
    public static func defaultFeePerUnit(
        quantity: Decimal,
        accountId: String,
        symbol: String,
        defaults: JournalDefaults
    ) -> Decimal {
        let rule = defaults.feeRules.first { matchesRule(ruleAccountId: $0.accountId, ruleSymbol: $0.symbol, accountId: accountId, symbol: symbol) }
        guard let r = rule else { return 0 }
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
    
    /// Net P&L band (in the reporting currency) inside which a closed trade counts as break-even.
    ///
    /// - `money` mode: the configured amount is used verbatim.
    /// - `percent` mode: the configured percentage is applied to the notional
    ///   (entry price x total entry quantity x contract multiplier), matching the Settings copy.
    public static func breakevenThreshold(
        defaults: JournalDefaults,
        entryPrice: Decimal,
        quantity: Decimal,
        multiplier: Decimal
    ) -> Decimal {
        let configured = abs(defaults.breakeven)
        guard configured > 0 else { return 0 }
        if defaults.breakevenMode == "percent" {
            let contractMultiplier = multiplier > 0 ? multiplier : 1
            let notional = abs(entryPrice) * abs(quantity) * contractMultiplier
            return notional * configured / 100
        }
        return configured
    }
}
