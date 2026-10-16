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
    @Published public var propAccounts: [PropAccountItem] = []
    @Published public var propEntries: [PropEntryItem] = []
    @Published public var propReceipts: [PropReceiptItem] = []
    @Published public var propAudits: [PropAuditItem] = []
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
        
        await MainActor.run {
            self.isSyncing = true
            self.lastSyncError = nil
        }
        
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
            
            // 4. Đồng bộ Quỹ (Prop Firm Subsystem 2-way Sync)
            // 4a. Prop Accounts Sync
            let remotePropAccounts = try await SupabaseService.shared.fetchPropAccounts()
            for rAcc in remotePropAccounts {
                if let idx = propAccounts.firstIndex(where: { $0.id == rAcc.id }) {
                    if rAcc.revision >= propAccounts[idx].revision {
                        propAccounts[idx] = rAcc
                    }
                } else {
                    propAccounts.append(rAcc)
                }
            }
            if !propAccounts.isEmpty {
                try await SupabaseService.shared.upsertPropAccounts(propAccounts)
            }
            
            // 4b. Prop Entries Sync
            let remotePropEntries = try await SupabaseService.shared.fetchPropEntries()
            for rEntry in remotePropEntries {
                if let idx = propEntries.firstIndex(where: { $0.id == rEntry.id }) {
                    if rEntry.revision >= propEntries[idx].revision {
                        propEntries[idx] = rEntry
                    }
                } else {
                    propEntries.append(rEntry)
                }
            }
            if !propEntries.isEmpty {
                try await SupabaseService.shared.upsertPropEntries(propEntries)
            }
            
            // 4c. Prop Receipts Sync
            let remotePropReceipts = try await SupabaseService.shared.fetchPropReceipts()
            for rRcpt in remotePropReceipts {
                if let idx = propReceipts.firstIndex(where: { $0.id == rRcpt.id }) {
                    propReceipts[idx] = rRcpt
                } else {
                    propReceipts.append(rRcpt)
                }
            }
            if !propReceipts.isEmpty {
                try await SupabaseService.shared.upsertPropReceipts(propReceipts)
            }
            
            // 4d. Prop Audits Sync
            let remotePropAudits = try await SupabaseService.shared.fetchPropAudits()
            for rAudit in remotePropAudits {
                if !propAudits.contains(where: { $0.id == rAudit.id }) {
                    propAudits.append(rAudit)
                }
            }
            if !propAudits.isEmpty {
                try await SupabaseService.shared.upsertPropAudits(propAudits)
            }
            
            saveToDisk()
            AppLogger.info("Supabase sync (Trades + Prop Firm) completed successfully.")
        } catch {
            await MainActor.run {
                self.lastSyncError = error.localizedDescription
            }
            AppLogger.error("Supabase sync failed: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            self.isSyncing = false
        }
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
    
    // MARK: - Prop Firm Management
    
    public func savePropAccount(item: PropAccountItem, reason: String = "User update") {
        let now = JournalIds.nowIso()
        var updated = item
        updated.updatedAt = now
        if let idx = propAccounts.firstIndex(where: { $0.id == item.id }) {
            let old = propAccounts[idx]
            updated.revision = old.revision + 1
            propAccounts[idx] = updated
            let audit = PropAuditItem(
                entityType: "account",
                entityId: item.id,
                beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: reason
            )
            propAudits.append(audit)
        } else {
            propAccounts.append(updated)
            let audit = PropAuditItem(
                entityType: "account",
                entityId: item.id,
                beforeJson: nil,
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: "Created"
            )
            propAudits.append(audit)
        }
        saveToDisk()
    }
    
    public func archivePropAccount(id: String, archived: Bool, reason: String = "User archive") {
        guard let idx = propAccounts.firstIndex(where: { $0.id == id }) else { return }
        let old = propAccounts[idx]
        var updated = old
        updated.archived = archived
        updated.revision = old.revision + 1
        updated.updatedAt = JournalIds.nowIso()
        propAccounts[idx] = updated
        let audit = PropAuditItem(
            entityType: "account",
            entityId: id,
            beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
            afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func savePropEntry(item: PropEntryItem, reason: String = "User update") {
        let now = JournalIds.nowIso()
        var updated = item
        updated.updatedAt = now
        if let idx = propEntries.firstIndex(where: { $0.id == item.id }) {
            let old = propEntries[idx]
            updated.revision = old.revision + 1
            propEntries[idx] = updated
            let audit = PropAuditItem(
                entityType: "entry",
                entityId: item.id,
                beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: reason
            )
            propAudits.append(audit)
        } else {
            propEntries.append(updated)
            let audit = PropAuditItem(
                entityType: "entry",
                entityId: item.id,
                beforeJson: nil,
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: "Created"
            )
            propAudits.append(audit)
        }
        saveToDisk()
    }
    
    public func voidPropEntry(id: String, voided: Bool, reason: String = "User void") throws {
        guard let idx = propEntries.firstIndex(where: { $0.id == id }) else {
            throw PropFirmError.notFound("Entry not found.")
        }
        let old = propEntries[idx]
        if voided {
            let activeRefunds = propEntries.filter { $0.parentId == id && !$0.voided }
            if !activeRefunds.isEmpty {
                throw PropFirmError.validation("Void linked refunds before voiding their expense.")
            }
        }
        var updated = old
        updated.voided = voided
        updated.revision = old.revision + 1
        updated.updatedAt = JournalIds.nowIso()
        propEntries[idx] = updated
        let audit = PropAuditItem(
            entityType: "entry",
            entityId: id,
            beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
            afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func addPropReceipt(item: PropReceiptItem, reason: String = "User receipt") throws {
        guard let payoutIdx = propEntries.firstIndex(where: { $0.id == item.payoutId }) else {
            throw PropFirmError.notFound("Payout not found.")
        }
        let payout = propEntries[payoutIdx]
        guard !payout.voided else {
            throw PropFirmError.validation("Cannot add receipt to voided payout.")
        }
        guard item.amountMinor > 0 else {
            throw PropFirmError.validation("Enter a positive receipt amount.")
        }
        
        propReceipts.append(item)
        
        // Cập nhật trạng thái Payout nếu đủ số tiền hoặc cần chuyển sang approved/completed
        let allReceiptsForPayout = propReceipts.filter { $0.payoutId == item.payoutId && !$0.voided }
        let totalNetReceived = allReceiptsForPayout.reduce(0) { sum, r in
            sum + (r.kind == "reversal" ? -r.amountMinor : r.amountMinor)
        }
        var updatedPayout = payout
        updatedPayout.revision = payout.revision + 1
        updatedPayout.updatedAt = JournalIds.nowIso()
        if totalNetReceived > 0 && updatedPayout.status == .requested {
            updatedPayout.status = .approved
        }
        propEntries[payoutIdx] = updatedPayout
        
        let audit = PropAuditItem(
            entityType: "receipt",
            entityId: item.id,
            beforeJson: nil,
            afterJson: (try? String(data: JSONEncoder().encode(item), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func voidPropReceipt(id: String, payoutId: String, voided: Bool, reason: String = "User void receipt") throws {
        guard let rIdx = propReceipts.firstIndex(where: { $0.id == id && $0.payoutId == payoutId }) else {
            throw PropFirmError.notFound("Receipt not found.")
        }
        let old = propReceipts[rIdx]
        var updated = old
        updated.voided = voided
        propReceipts[rIdx] = updated
        
        // Kiểm tra sau khi void, số dư không bao giờ âm
        let receiptsForPayout = propReceipts.filter { $0.payoutId == payoutId && !$0.voided }
        let totalNet = receiptsForPayout.reduce(0) { $0 + ($1.kind == "reversal" ? -$1.amountMinor : $1.amountMinor) }
        if totalNet < 0 {
            propReceipts[rIdx] = old
            throw PropFirmError.validation("A reversal cannot exceed the money received by that date.")
        }
        
        if let pIdx = propEntries.firstIndex(where: { $0.id == payoutId }) {
            var payout = propEntries[pIdx]
            payout.revision += 1
            payout.updatedAt = JournalIds.nowIso()
            if totalNet == 0 && payout.status == .completed {
                payout.status = .approved
            }
            propEntries[pIdx] = payout
        }
        
        let audit = PropAuditItem(
            entityType: "receipt",
            entityId: id,
            beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
            afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func importPropCsvData(csvText: String, preview: Bool = false) throws -> PropCsvImportResult {
        let (res, newEntries, newReceipts, newAudits) = try PropFirmEngine.importPropCsv(
            csvText: csvText,
            preview: preview,
            existingAccounts: propAccounts,
            existingEntries: propEntries,
            existingReceipts: propReceipts,
            existingAudits: propAudits
        )
        if !preview {
            self.propEntries = newEntries
            self.propReceipts = newReceipts
            self.propAudits = newAudits
            saveToDisk()
        }
        return res
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
        let propAccounts: [PropAccountItem]?
        let propEntries: [PropEntryItem]?
        let propReceipts: [PropReceiptItem]?
        let propAudits: [PropAuditItem]?
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
            journalDays: journalDays,
            propAccounts: propAccounts,
            propEntries: propEntries,
            propReceipts: propReceipts,
            propAudits: propAudits
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
            self.propAccounts = store.propAccounts ?? []
            self.propEntries = store.propEntries ?? []
            self.propReceipts = store.propReceipts ?? []
            self.propAudits = store.propAudits ?? []
            self.executionHashes = Set(store.executions.map { $0.contentHash })
            
            if self.propAccounts.isEmpty {
                createInitialPropDemoData()
            }
            
            AppLogger.info("Loaded \(store.accounts.count) accounts, \(store.executions.count) executions, \(self.notebookNotes.count) notes, \(self.propAccounts.count) prop accounts from persistent disk.")
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
    
    private func createInitialPropDemoData() {
        let acc1 = PropAccountItem(
            id: "prop-topstep-50k",
            firm: "Topstep",
            name: "Topstep 50K Express Funded",
            program: .funded,
            status: .active,
            currency: "USD",
            sizeMinor: 5_000_000,
            openedOn: "2026-09-01",
            notes: "Tài khoản Live Funded, tuân thủ giới hạn daily loss 1,000 USD."
        )
        let acc2 = PropAccountItem(
            id: "prop-ftmo-100k",
            firm: "FTMO",
            name: "FTMO 100K Normal Challenge",
            program: .evaluation,
            status: .passed,
            currency: "USD",
            sizeMinor: 10_000_000,
            openedOn: "2026-08-15",
            closedOn: "2026-09-01",
            notes: "Đã đỗ vòng 1 với lợi nhuận +10.2%."
        )
        let acc3 = PropAccountItem(
            id: "prop-ftmo-100k-v2",
            firm: "FTMO",
            name: "FTMO 100K Verification (Vòng 2)",
            program: .verification,
            status: .active,
            currency: "USD",
            sizeMinor: 10_000_000,
            parentId: "prop-ftmo-100k",
            openedOn: "2026-09-02",
            notes: "Đang thi vòng 2 Verification."
        )
        let e1 = PropEntryItem(
            id: "prop-entry-topstep-act",
            accountId: "prop-topstep-50k",
            firm: "Topstep",
            kind: "expense",
            category: "activation",
            currency: "USD",
            amountMinor: 14900,
            occurredOn: "2026-09-01",
            notes: "Phí kích hoạt tài khoản Express Funded"
        )
        let e2 = PropEntryItem(
            id: "prop-entry-ftmo-eval",
            accountId: "prop-ftmo-100k",
            firm: "FTMO",
            kind: "expense",
            category: "evaluation",
            currency: "USD",
            amountMinor: 54000,
            occurredOn: "2026-08-15",
            notes: "Phí thi gói Challenge 100k"
        )
        let e3 = PropEntryItem(
            id: "prop-entry-topstep-payout-1",
            accountId: "prop-topstep-50k",
            firm: "Topstep",
            kind: "payout",
            category: "payout",
            currency: "USD",
            amountMinor: 250000,
            splitBps: 9000,
            feeMinor: 2500,
            occurredOn: "2026-10-01",
            status: .completed,
            notes: "Kỳ payout đầu tiên sau 30 ngày funded"
        )
        let r1 = PropReceiptItem(
            id: "prop-rcpt-topstep-1",
            payoutId: "prop-entry-topstep-payout-1",
            kind: "receipt",
            amountMinor: 222500,
            occurredOn: "2026-10-03",
            reference: "DEEL-PAY-98124",
            notes: "Đã nhận tiền vào tài khoản ngân hàng"
        )
        self.propAccounts = [acc1, acc2, acc3]
        self.propEntries = [e1, e2, e3]
        self.propReceipts = [r1]
        saveToDisk()
    }
}
