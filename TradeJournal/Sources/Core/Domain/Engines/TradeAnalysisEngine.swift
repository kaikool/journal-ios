import Foundation

public struct AnalysisFilters: Equatable {
    public var accountIds: [String] = []
    public var fromDate: Date? = nil
    public var toDate: Date? = nil
    public var symbol: String? = nil
    public var excludeSymbol: String? = nil
    public var tag: String? = nil
    public var mistake: String? = nil
    public var playbookId: String? = nil
    public var direction: TradeDirection? = nil
    public var status: TradeStatus? = nil
    public var assetClass: AssetClass? = nil
    public var ratingMin: Int? = nil
    public var ratingMax: Int? = nil
    
    public init() {}
}

/// Engine tính toán R-Multiple, tỷ lệ Rủi ro/Lợi nhuận (Risk-to-Reward) và bộ lọc đa chiều.
/// Port 1:1 từ `packages/core/src/analysis.ts`.
public enum TradeAnalysisEngine {
    
    /// Tính toán rủi ro dự kiến theo điểm cắt lỗ (Stop Loss)
    public static func tradeRisk(trade: Trade) -> Decimal? {
        guard let stop = trade.stopLoss else { return nil }
        
        let multiplier: Decimal
        if let explicitMultiplier = trade.contractMultiplier {
            multiplier = explicitMultiplier
        } else {
            let derivatives: Set<String> = ["futures", "option", "cfd", "forex"]
            if let asset = trade.assetClass, derivatives.contains(asset) {
                return nil // Cần hệ số nhân hợp đồng rõ ràng đối với phái sinh
            }
            multiplier = 1
        }
        
        guard multiplier > 0 && trade.quantity > 0 else { return nil }
        
        let distance: Decimal
        if trade.direction == .long {
            distance = trade.avgEntry - stop
        } else {
            distance = stop - trade.avgEntry
        }
        
        return distance > 0 ? (distance * trade.quantity * multiplier) : nil
    }
    
    /// Tính toán Realized R: Net P&L chia cho số tiền rủi ro tại điểm stoploss
    public static func tradeR(trade: Trade) -> Double? {
        guard let risk = tradeRisk(trade), risk > 0, trade.status != .open else { return nil }
        return NSDecimalNumber(decimal: trade.netPnl).doubleValue / NSDecimalNumber(decimal: risk).doubleValue
    }
    
    /// Tính toán Planned R (RR kế hoạch): Tỷ lệ giữa Target và StopLoss
    public static func plannedR(trade: Trade) -> Double? {
        guard let stop = trade.stopLoss, let target = trade.profitTarget else { return nil }
        
        let sign: Decimal = trade.direction == .long ? 1 : -1
        let risk = (trade.avgEntry - stop) * sign
        let reward = (target - trade.avgEntry) * sign
        
        guard risk > 0 && reward >= 0 else { return nil }
        return NSDecimalNumber(decimal: reward).doubleValue / NSDecimalNumber(decimal: risk).doubleValue
    }
    
    /// Lọc danh sách trades theo bộ lọc đa chiều
    public static func filterTrades(_ trades: [Trade], with filters: AnalysisFilters) -> [Trade] {
        return trades.filter { trade in
            if !filters.accountIds.isEmpty && !filters.accountIds.contains(trade.accountId) {
                return false
            }
            if let from = filters.fromDate, trade.openedAt < from {
                return false
            }
            if let to = filters.toDate, trade.openedAt > to {
                return false
            }
            if let sym = filters.symbol, trade.symbol.caseInsensitiveCompare(sym) != .orderedSame {
                return false
            }
            if let exSym = filters.excludeSymbol, trade.symbol.caseInsensitiveCompare(exSym) == .orderedSame {
                return false
            }
            if let tag = filters.tag, !trade.tags.contains(tag) {
                return false
            }
            if let mistake = filters.mistake, !trade.mistakes.contains(mistake) {
                return false
            }
            if let playbook = filters.playbookId, trade.playbookId != playbook {
                return false
            }
            if let direction = filters.direction, trade.direction != direction {
                return false
            }
            if let status = filters.status, trade.status != status {
                return false
            }
            if let asset = filters.assetClass, trade.assetClass != asset {
                return false
            }
            if let rMin = filters.ratingMin, let rating = trade.rating, rating < rMin {
                return false
            }
            if let rMax = filters.ratingMax, let rating = trade.rating, rating > rMax {
                return false
            }
            return true
        }
    }
}
