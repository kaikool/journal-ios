import SwiftUI
import Combine

/// Quản lý dữ liệu thực tế của ứng dụng, hỗ trợ lưu trữ cục bộ (Offline persistence)
/// và đồng bộ hai chiều với Supabase PostgreSQL.
/// Thuật toán tái dựng và băm dedup tuân thủ 100% `rebuild.ts` và `ids.ts`.
@MainActor
public final class TradeDataStore: ObservableObject {
    public static let shared = TradeDataStore()
    
    @Published public var accounts: [Account] = []
    @Published public var executions: [Execution] = []
    @Published public var trades: [Trade] = []
    @Published public var selectedAccountId: String = "default-acc"
    @Published public var defaults: JournalDefaults = .empty
    @Published public var multipliers: [String: Decimal] = [:]
    @Published public var folders: [NotebookFolder] = []
    @Published public var notebookNotes: [NotebookNote] = []
    @Published public var journalDays: [String: String] = [:]
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncError: String? = nil
    
    private var executionHashes: Set<String> = []
    
    private var persistenceUrl: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("trade_journal_store_v1.json")
    }
    
    public init() {
        loadFromDisk()
        if accounts.isEmpty {
            createInitialDefaultAccount()
        }
        if folders.isEmpty {
            folders = NotebookEngine.defaultSystemFolders
        }
        rebuildAllAccounts()
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
    
    public func selectAccount(id: String) {
        selectedAccountId = id
    }
    
    public func addAccount(name: String, broker: String = "", currency: String = "USD", initialBalance: Decimal = 0) {
        let newAccount = Account(
            name: name,
            broker: broker,
            currency: currency,
            initialBalance: initialBalance
        )
        accounts.append(newAccount)
        selectedAccountId = newAccount.id
        saveToDisk()
        AppLogger.info("Added account: \(name) (\(newAccount.id))")
    }
    
    /// Nạp danh sách executions mới từ Import hoặc Sync
    /// Chống ghi trùng tuyệt đối theo `executionHash` chuẩn SHA-256 từ `ids.ts`
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
        saveToDisk()
        AppLogger.info("Imported \(uniqueNew.count) executions for account \(accountId). Rebuilt \(trades.count) trades.")
    }
    
    /// Tái dựng toàn bộ các Trades cho một account từ executions nguyên tử
    /// Port 1:1 từ `source-repo/apps/web/src/server/rebuild.ts`
    public func rebuildAccount(accountId: String) {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        
        let accountFills = executions.filter { $0.accountId == accountId }
        let reconstructed = TradeReconstructionEngine.buildRoundTrips(
            executions: accountFills,
            options: .init(method: account.profitCalcMethod, multipliers: multipliers)
        )
        
        // Lưu lại các annotation người dùng đã ghi chú để bảo toàn khi rebuild
        var existingAnnotations: [String: (notes: String?, tags: [String], mistakes: [String], rating: Int?, stopLoss: Decimal?, profitTarget: Decimal?, reviewedAt: Date?, playbookId: String?)] = [:]
        for t in trades where t.accountId == accountId {
            existingAnnotations[t.key] = (t.notes, t.tags, t.mistakes, t.rating, t.stopLoss, t.profitTarget, t.reviewedAt, t.playbookId)
        }
        
        let mergedTrades = reconstructed.map { trade -> Trade in
            var t = trade
            if let ann = existingAnnotations[t.key] {
                t.notes = ann.notes
                t.tags = ann.tags
                t.mistakes = ann.mistakes
                t.rating = ann.rating
                t.stopLoss = ann.stopLoss
                t.profitTarget = ann.profitTarget
                t.reviewedAt = ann.reviewedAt
                t.playbookId = ann.playbookId
            } else {
                // Áp dụng defaultRisk nếu chưa có annotation
                let defaultRisk = JournalDefaultsEngine.defaultRisk(
                    entry: t.avgEntry,
                    direction: t.direction,
                    accountId: accountId,
                    symbol: t.symbol,
                    defaults: defaults
                )
                if t.stopLoss == nil { t.stopLoss = defaultRisk.stopLoss }
                if t.profitTarget == nil { t.profitTarget = defaultRisk.profitTarget }
            }
            return t
        }
        
        let otherTrades = trades.filter { $0.accountId != accountId }
        trades = otherTrades + mergedTrades
    }
    
    public func rebuildAllAccounts() {
        for acc in accounts {
            rebuildAccount(accountId: acc.id)
        }
    }
    
    public func updateTradeAnnotations(
        key: String,
        notes: String?,
        tags: [String],
        mistakes: [String] = [],
        stopLoss: Decimal?,
        profitTarget: Decimal? = nil,
        rating: Int?,
        playbookId: String? = nil,
        reviewedAt: Date? = nil
    ) {
        guard let index = trades.firstIndex(where: { $0.key == key }) else { return }
        trades[index].notes = notes
        trades[index].tags = tags
        trades[index].mistakes = mistakes
        trades[index].stopLoss = stopLoss
        trades[index].profitTarget = profitTarget
        trades[index].rating = rating
        trades[index].playbookId = playbookId
        trades[index].reviewedAt = reviewedAt
        saveToDisk()
        AppLogger.info("Updated trade annotations for key: \(key)")
    }
    
    // MARK: - Supabase Synchronization
    
    public func syncWithSupabase() async {
        guard SupabaseService.shared.isConfigured else {
            AppLogger.info("Supabase credentials not configured in settings, running in local-first mode.")
            return
        }
        
        isSyncing = true
        lastSyncError = nil
        
        do {
            // 1. Fetch remote accounts
            let remoteAccounts = try await SupabaseService.shared.fetchAccounts()
            if !remoteAccounts.isEmpty {
                for rAcc in remoteAccounts {
                    if !accounts.contains(where: { $0.id == rAcc.id }) {
                        accounts.append(rAcc)
                    }
                }
            }
            
            // 2. Fetch remote executions for selected account
            let remoteExecutions = try await SupabaseService.shared.fetchExecutions(accountId: selectedAccountId)
            if !remoteExecutions.isEmpty {
                importExecutions(accountId: selectedAccountId, newExecutions: remoteExecutions)
            }
            
            // 2b. Push local executions for selected account to Supabase
            let localAccountFills = executions.filter { $0.accountId == selectedAccountId }
            if !localAccountFills.isEmpty {
                try await SupabaseService.shared.upsertExecutions(localAccountFills)
            }
            
            // 3. Push local trades to Supabase
            try await SupabaseService.shared.upsertTrades(filteredTrades)
            
            saveToDisk()
            AppLogger.info("Supabase sync completed successfully.")
        } catch {
            lastSyncError = error.localizedDescription
            AppLogger.error("Supabase sync failed: \(error.localizedDescription)")
        }
        
        isSyncing = false
    }
    
    // MARK: - Notebook & Journal Operations (1:1 port từ source-repo)
    
    public func createFolder(name: String) throws -> NotebookFolder {
        let (folder, updated) = try NotebookEngine.createFolder(name: name, existingFolders: folders)
        self.folders = updated
        saveToDisk()
        return folder
    }
    
    public func deleteFolder(id: String) throws {
        let (updatedFolders, updatedNotes) = try NotebookEngine.deleteFolder(id: id, folders: folders, notes: notebookNotes)
        self.folders = updatedFolders
        self.notebookNotes = updatedNotes
        saveToDisk()
    }
    
    public func createNote(
        folderId: String? = nil,
        title: String = "",
        content: String = "",
        tags: [String] = [],
        tradeKey: String? = nil,
        dayDate: String? = nil
    ) throws -> NotebookNote {
        let (note, updated) = try NotebookEngine.createNote(
            folderId: folderId,
            title: title,
            content: content,
            tags: tags,
            tradeKey: tradeKey,
            dayDate: dayDate,
            folders: folders,
            existingNotes: notebookNotes
        )
        self.notebookNotes = updated
        saveToDisk()
        return note
    }
    
    public func patchNote(
        id: String,
        title: String? = nil,
        content: String? = nil,
        tags: [String]? = nil,
        folderId: String? = nil
    ) throws -> NotebookNote {
        let (note, updated) = try NotebookEngine.patchNote(
            id: id,
            title: title,
            content: content,
            tags: tags,
            folderId: folderId,
            folders: folders,
            notes: notebookNotes
        )
        self.notebookNotes = updated
        saveToDisk()
        return note
    }
    
    public func deleteNote(id: String) {
        self.notebookNotes = NotebookEngine.deleteNote(id: id, notes: notebookNotes)
        saveToDisk()
    }
    
    public func saveJournalDayNote(date: String, note: String) {
        self.journalDays[date] = note
        saveToDisk()
    }
    
    public func getJournalDayNote(date: String) -> String {
        self.journalDays[date] ?? ""
    }
    
    public func filteredNotes(
        folderId: String? = nil,
        searchQuery: String? = nil,
        tag: String? = nil,
        sort: NoteSortOrder = .updated
    ) -> (notes: [NotebookNote], folders: [NotebookFolder]) {
        NotebookEngine.filterNotes(
            notes: notebookNotes,
            folders: folders,
            folderId: folderId,
            searchQuery: searchQuery,
            tag: tag,
            sort: sort
        )
    }
    
    // MARK: - Local Persistence
    
    private struct PersistedStore: Codable {
        let accounts: [Account]
        let executions: [Execution]
        let trades: [Trade]
        let selectedAccountId: String
        let defaults: JournalDefaults
        let multipliers: [String: Decimal]?
        let folders: [NotebookFolder]?
        let notebookNotes: [NotebookNote]?
        let journalDays: [String: String]?
    }
    
    private func saveToDisk() {
        let store = PersistedStore(
            accounts: accounts,
            executions: executions,
            trades: trades,
            selectedAccountId: selectedAccountId,
            defaults: defaults,
            multipliers: multipliers,
            folders: folders,
            notebookNotes: notebookNotes,
            journalDays: journalDays
        )
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: persistenceUrl, options: .atomic)
        } catch {
            AppLogger.error("Failed to save store to disk: \(error.localizedDescription)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceUrl.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceUrl)
            let store = try JSONDecoder().decode(PersistedStore.self, from: data)
            self.accounts = store.accounts
            self.executions = store.executions
            self.trades = store.trades
            self.selectedAccountId = store.selectedAccountId
            self.defaults = store.defaults
            self.multipliers = store.multipliers ?? [:]
            self.folders = store.folders ?? NotebookEngine.defaultSystemFolders
            self.notebookNotes = store.notebookNotes ?? []
            self.journalDays = store.journalDays ?? [:]
            self.executionHashes = Set(store.executions.map { $0.contentHash })
            AppLogger.info("Loaded \(store.accounts.count) accounts, \(store.executions.count) executions, \(self.notebookNotes.count) notes from persistent disk.")
        } catch {
            AppLogger.error("Failed to load store from disk: \(error.localizedDescription)")
        }
    }
    
    private func createInitialDefaultAccount() {
        let defaultAcc = Account(
            id: "default-acc",
            name: "Main Trading Account",
            broker: "Interactive Brokers",
            currency: "USD",
            initialBalance: 10000
        )
        accounts = [defaultAcc]
        selectedAccountId = defaultAcc.id
        saveToDisk()
    }
}
