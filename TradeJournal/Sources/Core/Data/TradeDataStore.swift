import SwiftUI
import Combine

/// Quản lý dữ liệu tập trung phía Client (State & Data Store)
/// Điều phối giữa bộ nhớ cục bộ, thuật toán tái dựng Trade và đồng bộ từ xa.
@MainActor
public final class TradeDataStore: ObservableObject {
    public static let shared = TradeDataStore()
    
    @Published public var accounts: [Account] = []
    @Published public var executions: [Execution] = []
    @Published public var trades: [Trade] = []
    @Published public var selectedAccountId: String = "default-acc"
    
    private var executionHashes: Set<String> = []
    
    public init() {
        seedSampleData()
    }
    
    public var selectedAccount: Account? {
        accounts.first(where: { $0.id == selectedAccountId }) ?? accounts.first
    }
    
    public var filteredTrades: [Trade] {
        guard let account = selectedAccount else { return trades }
        return trades.filter { $0.accountId == account.id }
    }
    
    public var existingHashesForSelectedAccount: Set<String> {
        Set(executions.filter { $0.accountId == selectedAccountId }.map { $0.contentHash })
    }
    
    /// Thêm một tài khoản giao dịch mới
    public func addAccount(name: String, broker: String = "", currency: String = "USD", initialBalance: Decimal = 0) {
        let newAccount = Account(
            name: name,
            broker: broker,
            currency: currency,
            initialBalance: initialBalance
        )
        accounts.append(newAccount)
        selectedAccountId = newAccount.id
        AppLogger.info("Added new account: \(name) (\(newAccount.id))")
    }
    
    public func selectAccount(id: String) {
        selectedAccountId = id
    }
    
    /// Nạp danh sách executions mới từ Import hoặc Sync và tự động kích hoạt Rebuild
    public func importExecutions(accountId: String, newExecutions: [Execution]) {
        let uniqueNew = newExecutions.filter { !executionHashes.contains($0.contentHash) }
        guard !uniqueNew.isEmpty else {
            AppLogger.info("No new unique executions to import.")
            return
        }
        
        for fill in uniqueNew {
            executionHashes.insert(fill.contentHash)
            executions.append(fill)
        }
        
        rebuildAccount(accountId: accountId)
        AppLogger.info("Imported \(uniqueNew.count) executions for account \(accountId). Rebuilt \(trades.count) trades.")
    }
    
    /// Tái dựng toàn bộ các Trades cho một account từ executions nguyên tử
    public func rebuildAccount(accountId: String) {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        
        let accountFills = executions.filter { $0.accountId == accountId }
        let reconstructed = TradeReconstructionEngine.buildRoundTrips(
            executions: accountFills,
            options: .init(method: account.profitCalcMethod)
        )
        
        // Lưu lại các annotation cũ nếu có
        var existingAnnotations: [String: (notes: String?, tags: [String], rating: Int?, stopLoss: Decimal?)] = [:]
        for t in trades where t.accountId == accountId {
            existingAnnotations[t.key] = (t.notes, t.tags, t.rating, t.stopLoss)
        }
        
        var mergedTrades = reconstructed.map { trade -> Trade in
            var t = trade
            if let ann = existingAnnotations[t.key] {
                t.notes = ann.notes
                t.tags = ann.tags
                t.rating = ann.rating
                t.stopLoss = ann.stopLoss
            }
            return t
        }
        
        // Giữ lại các trades thuộc accounts khác
        let otherTrades = trades.filter { $0.accountId != accountId }
        trades = otherTrades + mergedTrades
    }
    
    /// Cập nhật ghi chú và tag cho một Trade
    public func updateTradeAnnotations(key: String, notes: String?, tags: [String], stopLoss: Decimal?, rating: Int?) {
        guard let index = trades.firstIndex(where: { $0.key == key }) else { return }
        trades[index].notes = notes
        trades[index].tags = tags
        trades[index].stopLoss = stopLoss
        trades[index].rating = rating
        AppLogger.info("Updated trade annotations for key: \(key)")
    }
    
    private func seedSampleData() {
        let defaultAcc = Account(
            id: "default-acc",
            name: "Tài khoản Chính (Demo)",
            broker: "Interactive Brokers",
            currency: "USD",
            initialBalance: 10000
        )
        accounts = [defaultAcc]
        selectedAccountId = defaultAcc.id
        
        let now = Date()
        let sampleFills = [
            Execution(accountId: defaultAcc.id, symbol: "AAPL", side: .buy, quantity: 100, price: 150, fee: 1, executedAt: now.addingTimeInterval(-86400 * 3)),
            Execution(accountId: defaultAcc.id, symbol: "AAPL", side: .sell, quantity: 100, price: 155, fee: 1, executedAt: now.addingTimeInterval(-86400 * 3 + 3600)),
            Execution(accountId: defaultAcc.id, symbol: "TSLA", side: .sell, quantity: 50, price: 210, fee: 1.5, executedAt: now.addingTimeInterval(-86400 * 2)),
            Execution(accountId: defaultAcc.id, symbol: "TSLA", side: .buy, quantity: 50, price: 200, fee: 1.5, executedAt: now.addingTimeInterval(-86400 * 2 + 7200)),
            Execution(accountId: defaultAcc.id, symbol: "NVDA", side: .buy, quantity: 40, price: 120, fee: 1, executedAt: now.addingTimeInterval(-86400 * 1)),
            Execution(accountId: defaultAcc.id, symbol: "NVDA", side: .sell, quantity: 40, price: 115, fee: 1, executedAt: now.addingTimeInterval(-86400 * 1 + 1800))
        ]
        
        importExecutions(accountId: defaultAcc.id, newExecutions: sampleFills)
    }
}
