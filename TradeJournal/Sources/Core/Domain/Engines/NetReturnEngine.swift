import Foundation

public struct ReturnInputs {
    public let netPnl: Decimal
    public let avgEntry: Decimal
    public let quantity: Decimal
    public let assetClass: String?
    public let quantityUnitsUnknown: Bool?
    public let contractMultiplier: Decimal?
    
    public init(
        netPnl: Decimal,
        avgEntry: Decimal,
        quantity: Decimal,
        assetClass: String? = nil,
        quantityUnitsUnknown: Bool? = nil,
        contractMultiplier: Decimal? = nil
    ) {
        self.netPnl = netPnl
        self.avgEntry = avgEntry
        self.quantity = quantity
        self.assetClass = assetClass
        self.quantityUnitsUnknown = quantityUnitsUnknown
        self.contractMultiplier = contractMultiplier
    }
}

/// Net return on absolute entry notional, as a ratio (not return on margin).
/// Ported 1:1 from `packages/core/src/returns.ts`.
public enum NetReturnEngine {
    
    public static func netReturnOnEntry(trade: ReturnInputs) -> Double? {
        if trade.quantityUnitsUnknown == true { return nil }
        
        let multiplier: Decimal?
        if let explicit = trade.contractMultiplier {
            multiplier = explicit
        } else {
            let derivatives: Set<String> = ["futures", "option", "forex", "cfd"]
            if let asset = trade.assetClass, derivatives.contains(asset) {
                multiplier = nil
            } else {
                multiplier = 1
            }
        }
        
        guard let mult = multiplier, mult > 0 else { return nil }
        guard trade.quantity > 0 else { return nil }
        
        let notional = abs(trade.avgEntry) * trade.quantity * mult
        guard notional > 0 else { return nil }
        
        let result = NSDecimalNumber(decimal: trade.netPnl).doubleValue / NSDecimalNumber(decimal: notional).doubleValue
        guard result.isFinite else { return nil }
        return result
    }
}
