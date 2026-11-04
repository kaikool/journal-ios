import Foundation
import Combine

/// Dedicated domain store managing trades, executions, and trade filtering/reconstruction logic.
/// Part of Item 1: TradeDataStore God Object decomposition into domain stores.
@MainActor
public final class TradesDomainStore: ObservableObject {
    @Published public var trades: [Trade] = []
    @Published public var executions: [Execution] = []
    @Published public var missedTrades: [MissedTrade] = []
    @Published public var attachments: [Attachment] = []

    public init(
        trades: [Trade] = [],
        executions: [Execution] = [],
        missedTrades: [MissedTrade] = [],
        attachments: [Attachment] = []
    ) {
        self.trades = trades
        self.executions = executions
        self.missedTrades = missedTrades
        self.attachments = attachments
    }

    public func findTrade(byKey key: String) -> Trade? {
        trades.first { $0.id == key || $0.key == key }
    }

    public func filterTrades(for accountId: String, visibleAccountIds: Set<String>) -> [Trade] {
        if accountId == "all" || accountId == "default-acc" || accountId.isEmpty {
            return trades.filter { trade in
                if trade.symbol == "ACCOUNT" { return false }
                if visibleAccountIds.contains(trade.accountId) { return true }
                let clean = trade.accountId.cleanAccountId
                return visibleAccountIds.contains(clean) ||
                       visibleAccountIds.contains(trade.accountId.the5ersCanonicalId) ||
                       visibleAccountIds.contains(trade.accountId.ctraderCanonicalId) ||
                       visibleAccountIds.contains(trade.accountId.exnessCanonicalId)
            }
        } else {
            return trades.filter { trade in
                guard trade.symbol != "ACCOUNT" else { return false }
                return trade.accountId == accountId || TradeDataStore.isSameAccountId(trade.accountId, accountId)
            }
        }
    }
}
