import Foundation

/// Deduplication of raw executions and reconstructed trades.
///
/// Executions are matched by id, content hash and a semantic signature
/// (account, instrument, side, quantity, price and second of the fill).
///
/// Trades are matched by their key and a semantic signature
/// (account, instrument, direction, open second, quantity and entry price).
/// The signature keeps a one second tolerance so that slight timestamp differences between
/// two syncs of the same trade still collapse into one entry, while two distinct scalps
/// opened in the same second are kept apart by their entry price.
public enum TradeDeduplicator {
    
    // MARK: - Executions
    
    public static func executionSemanticKey(for fill: Execution) -> String {
        let cleanAcc = fill.accountId.cleanAccountId
        let fillSec = Int64(fill.executedAt.timeIntervalSince1970.rounded())
        let symbol = AssetContractEngine.canonicalSymbol(fill.symbol)
        return "\(cleanAcc)|\(symbol)|\(fill.side.rawValue)|\(fill.quantity)|\(fill.price)|\(fillSec)"
    }
    
    /// Removes duplicate executions (same id, same content hash or same semantic signature).
    public static func deduplicate(_ executions: [Execution]) -> [Execution] {
        var seenIds = Set<String>()
        var seenHashes = Set<String>()
        var seenSemantics = Set<String>()
        var cleaned: [Execution] = []
        
        for fill in executions {
            if seenIds.contains(fill.id) || seenHashes.contains(fill.contentHash) {
                continue
            }
            let semantic = executionSemanticKey(for: fill)
            if seenSemantics.contains(semantic) {
                continue
            }
            seenIds.insert(fill.id)
            seenHashes.insert(fill.contentHash)
            seenSemantics.insert(semantic)
            cleaned.append(fill)
        }
        return cleaned
    }
    
    // MARK: - Trades
    
    public static func tradeSemanticKey(for trade: Trade) -> String {
        let cleanAcc = trade.accountId.cleanAccountId
        let openSec = Int64(trade.openedAt.timeIntervalSince1970.rounded())
        let qtyStr = NSDecimalNumber(decimal: trade.quantity).stringValue
        let entryStr = NSDecimalNumber(decimal: trade.avgEntry).stringValue
        let symbol = AssetContractEngine.canonicalSymbol(trade.symbol)
        return "\(cleanAcc)|\(symbol)|\(trade.direction.rawValue)|\(openSec)|\(qtyStr)|\(entryStr)"
    }
    
    /// Removes duplicate trades. Trades carrying annotations win over bare ones.
    public static func deduplicate(_ trades: [Trade]) -> [Trade] {
        // Prioritize trades that contain notes, tags, executionIds, or non-zero P&L
        let sorted = trades.sorted { a, b in
            score(a) > score(b)
        }
        
        var seenKeys = Set<String>()
        var seenSemantics = Set<String>()
        var cleaned: [Trade] = []
        
        for trade in sorted {
            if seenKeys.contains(trade.key) {
                continue
            }
            let semantic = tradeSemanticKey(for: trade)
            if seenSemantics.contains(semantic) {
                continue
            }
            seenKeys.insert(trade.key)
            seenSemantics.insert(semantic)
            cleaned.append(trade)
        }
        
        return cleaned.sorted { $0.openedAt < $1.openedAt }
    }
    
    private static func score(_ trade: Trade) -> Int {
        (trade.notes != nil ? 1 : 0) + (!trade.tags.isEmpty ? 1 : 0) + (trade.netPnl != 0 ? 2 : 0) + trade.executionCount
    }
}
