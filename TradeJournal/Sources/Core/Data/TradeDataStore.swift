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
    @Published public var attachments: [Attachment] = []
    @Published public var playbooks: [Playbook] = []
    @Published public var playbookAssessments: [PlaybookRuleAssessment] = []
    @Published public var calendarNotes: [String: JournalNote] = [:]
    @Published public var generalSettings: GeneralSettingsConfig = .default
    @Published public var currencyConversion: CurrencyConversion = .default
    @Published public var marketConnections: MarketConnectionConfig = .default
    @Published public var aiSettings: AiSettingsConfig = .default
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncError: String? = nil
    @Published public var lastSyncSummary: String? = nil
    
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
        if selectedAccountId == "all" {
            return trades
        }
        guard let account = selectedAccount else { return trades }
        let accountTrades = trades.filter { $0.accountId == account.id }
        // Nếu tài khoản được chọn không có lệnh nào nhưng kho dữ liệu lại có lệnh từ tài khoản khác,
        // hiển thị toàn bộ lệnh để người dùng không bị trống màn hình
        return accountTrades.isEmpty ? trades : accountTrades
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
        
        var fetchedAccountsCount = 0
        var fetchedTradesCount = 0
        var fetchedExecutionsCount = 0
        var fetchedPropCount = 0
        var syncWarnings: [String] = []

        // 1. Đồng bộ Accounts (Tải về và đẩy lên)
        do {
            let remoteAccounts = try await SupabaseService.shared.fetchAccounts()
            fetchedAccountsCount = remoteAccounts.count
            if !remoteAccounts.isEmpty {
                for rAcc in remoteAccounts {
                    if let idx = accounts.firstIndex(where: { $0.id == rAcc.id }) {
                        accounts[idx] = rAcc
                    } else {
                        accounts.append(rAcc)
                    }
                }
                // Nếu đang trỏ vào default-acc hoặc account không tồn tại, trỏ sang account thật từ Supabase
                if selectedAccountId == "default-acc" || !accounts.contains(where: { $0.id == selectedAccountId }) {
                    if let first = remoteAccounts.first {
                        selectedAccountId = first.id
                    }
                }
                // Loại bỏ default-acc khi đã có tài khoản thực từ Supabase
                accounts.removeAll(where: { $0.id == "default-acc" && accounts.count > 1 })
            }
            if !accounts.isEmpty {
                try? await SupabaseService.shared.upsertAccounts(accounts)
            }
        } catch {
            AppLogger.error("Supabase accounts sync warning: \(error.localizedDescription)")
            syncWarnings.append("Tài khoản: \(error.localizedDescription)")
        }

        // 2. Tải TOÀN BỘ lệnh giao dịch từ Supabase
        do {
            let remoteTrades = try await SupabaseService.shared.fetchTrades(accountId: nil)
            fetchedTradesCount = remoteTrades.count
            for rTrade in remoteTrades {
                if let idx = trades.firstIndex(where: { $0.key == rTrade.key }) {
                    trades[idx] = rTrade
                } else {
                    trades.append(rTrade)
                }
                // Đảm bảo accountId của lệnh được đăng ký trong danh sách accounts
                if !accounts.contains(where: { $0.id == rTrade.accountId }) {
                    accounts.append(Account(id: rTrade.accountId, name: "Tài khoản \(rTrade.accountId)", kind: .sync))
                }
            }
            // Tự động chuyển selectedAccountId sang tài khoản có lệnh giao dịch nếu tài khoản hiện tại rỗng
            if filteredTrades.isEmpty, let firstTrade = trades.first {
                selectedAccountId = firstTrade.accountId
            }
            if !trades.isEmpty {
                try? await SupabaseService.shared.upsertTrades(trades)
            }
        } catch {
            AppLogger.error("Supabase trades sync warning: \(error.localizedDescription)")
            syncWarnings.append("Lệnh giao dịch: \(error.localizedDescription)")
        }

        // 2b. Tải TOÀN BỘ executions từ Supabase
        do {
            let remoteExecutions = try await SupabaseService.shared.fetchExecutions(accountId: nil)
            fetchedExecutionsCount = remoteExecutions.count
            if !remoteExecutions.isEmpty {
                let uniqueNew = remoteExecutions.filter { !executionHashes.contains($0.contentHash) }
                for fill in uniqueNew {
                    executionHashes.insert(fill.contentHash)
                    executions.append(fill)
                }
            }
            if !executions.isEmpty {
                try? await SupabaseService.shared.upsertExecutions(executions)
            }
        } catch {
            AppLogger.error("Supabase executions sync warning: \(error.localizedDescription)")
            syncWarnings.append("Khớp lệnh (Executions): \(error.localizedDescription)")
        }

        // 3. Đồng bộ Playbooks
        do {
            let remotePlaybooks = try await SupabaseService.shared.fetchPlaybooks()
            for rPb in remotePlaybooks {
                if let idx = playbooks.firstIndex(where: { $0.id == rPb.id }) {
                    playbooks[idx] = rPb
                } else {
                    playbooks.append(rPb)
                }
            }
            let localUserPlaybooks = playbooks.filter { pb in
                !remotePlaybooks.contains(where: { $0.id == pb.id })
            }
            if !localUserPlaybooks.isEmpty {
                try? await SupabaseService.shared.upsertPlaybooks(localUserPlaybooks)
            }
        } catch {
            AppLogger.warn("Supabase playbooks sync warning: \(error.localizedDescription)")
        }

        // 4. Đồng bộ Quỹ (Prop Firm Subsystem)
        do {
            let remotePropAccounts = try await SupabaseService.shared.fetchPropAccounts()
            fetchedPropCount = remotePropAccounts.count
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
                try? await SupabaseService.shared.upsertPropAccounts(propAccounts)
            }
        } catch {
            AppLogger.warn("Supabase prop accounts warning: \(error.localizedDescription)")
        }

        do {
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
                try? await SupabaseService.shared.upsertPropEntries(propEntries)
            }
        } catch {
            AppLogger.warn("Supabase prop entries warning: \(error.localizedDescription)")
        }

        do {
            let remotePropReceipts = try await SupabaseService.shared.fetchPropReceipts()
            for rRcpt in remotePropReceipts {
                if let idx = propReceipts.firstIndex(where: { $0.id == rRcpt.id }) {
                    propReceipts[idx] = rRcpt
                } else {
                    propReceipts.append(rRcpt)
                }
            }
            if !propReceipts.isEmpty {
                try? await SupabaseService.shared.upsertPropReceipts(propReceipts)
            }
        } catch {
            AppLogger.warn("Supabase prop receipts warning: \(error.localizedDescription)")
        }

        do {
            let remotePropAudits = try await SupabaseService.shared.fetchPropAudits()
            for rAudit in remotePropAudits {
                if !propAudits.contains(where: { $0.id == rAudit.id }) {
                    propAudits.append(rAudit)
                }
            }
            if !propAudits.isEmpty {
                try? await SupabaseService.shared.upsertPropAudits(propAudits)
            }
        } catch {
            AppLogger.warn("Supabase prop audits warning: \(error.localizedDescription)")
        }

        // 5. Đồng bộ Tệp đính kèm (Attachments Sync)
        do {
            let remoteAttachments = try await SupabaseService.shared.fetchAttachments()
            for rAtt in remoteAttachments {
                if !attachments.contains(where: { $0.id == rAtt.id }) {
                    attachments.append(rAtt)
                }
            }
        } catch {
            AppLogger.warn("Supabase attachments warning: \(error.localizedDescription)")
        }

        saveToDisk()

        let totalRecords = fetchedAccountsCount + fetchedTradesCount + fetchedExecutionsCount + fetchedPropCount
        await MainActor.run {
            if totalRecords > 0 {
                var summary = "Đồng bộ Supabase thành công: Tải về \(fetchedAccountsCount) tài khoản, \(fetchedTradesCount) lệnh, \(fetchedExecutionsCount) executions, \(fetchedPropCount) quỹ."
                if !syncWarnings.isEmpty {
                    summary += " (Cảnh báo: \(syncWarnings.joined(separator: "; ")))"
                }
                self.lastSyncSummary = summary
                self.lastSyncError = nil
            } else if !syncWarnings.isEmpty {
                self.lastSyncError = syncWarnings.joined(separator: "\n")
            } else {
                self.lastSyncSummary = "Kết nối Supabase thành công. Dữ liệu local và đám mây đã đồng bộ (0 bản ghi mới)."
                self.lastSyncError = nil
            }
            self.isSyncing = false
        }
        AppLogger.info("Supabase sync completed: Accounts=\(fetchedAccountsCount), Trades=\(fetchedTradesCount), Executions=\(fetchedExecutionsCount)")
    }
    
    // MARK: - The5ers MCP Synchronization
    
    public func syncWithThe5ers() async throws -> Int {
        await MainActor.run {
            self.isSyncing = true
            self.lastSyncError = nil
        }
        defer {
            Task { @MainActor in self.isSyncing = false }
        }
        let count = try await The5ersService.shared.syncWithTradeStore(dataStore: self)
        await MainActor.run {
            if count > 0 {
                self.lastSyncSummary = "Đã đồng bộ The5ers MCP thành công: \(count) tài khoản, \(self.trades.filter { $0.tags.contains("the5ers") }.count) lệnh."
            } else {
                self.lastSyncSummary = The5ersService.shared.lastStatus
            }
        }
        return count
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

    // MARK: - Attachments & Screenshots (1:1 port từ source-repo)
    
    private var attachmentsBaseUrl: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public func attachmentsFor(ownerType: String, ownerId: String) -> [Attachment] {
        attachments.filter { $0.ownerType == ownerType && $0.ownerId == ownerId }
    }
    
    public func addAttachment(
        ownerType: String,
        ownerId: String,
        name: String,
        data: Data
    ) throws -> Attachment {
        let validation = try AttachmentEngine.validateAttachment(data: data, declaredName: name)
        let attId = JournalIds.newId()
        let relativePath = AttachmentEngine.storagePath(
            ownerType: ownerType,
            ownerId: ownerId,
            id: attId,
            name: validation.cleanName
        )
        
        let fileUrl = attachmentsBaseUrl.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileUrl, options: .atomic)
        
        let attachment = Attachment(
            id: attId,
            ownerType: ownerType,
            ownerId: ownerId,
            name: validation.cleanName,
            mime: validation.mime,
            size: data.count,
            storagePath: relativePath,
            status: "ready"
        )
        
        attachments.append(attachment)
        saveToDisk()
        
        if SupabaseService.shared.isConfigured {
            Task {
                try? await SupabaseService.shared.uploadAttachmentFile(
                    storagePath: relativePath,
                    data: data,
                    mime: validation.mime
                )
                try? await SupabaseService.shared.upsertAttachments([attachment])
            }
        }
        
        return attachment
    }
    
    public func saveChartScreenshot(
        tradeKey: String,
        symbol: String,
        dataUrl: String
    ) throws -> Attachment {
        let data = try AttachmentEngine.validateChartScreenshotPng(dataUrl: dataUrl)
        let safeSymbol = symbol
            .replacingOccurrences(of: #"[^a-zA-Z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filename = "chart-\(safeSymbol.isEmpty ? "trade" : safeSymbol).png"
        return try addAttachment(
            ownerType: "trade",
            ownerId: tradeKey,
            name: filename,
            data: data
        )
    }
    
    public func deleteAttachment(id: String) throws {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        let att = attachments[index]
        let fileUrl = attachmentsBaseUrl.appendingPathComponent(att.storagePath)
        try? FileManager.default.removeItem(at: fileUrl)
        attachments.remove(at: index)
        saveToDisk()
        
        if SupabaseService.shared.isConfigured {
            Task {
                try? await SupabaseService.shared.deleteAttachmentFile(storagePath: att.storagePath)
            }
        }
    }
    
    public func attachmentFileData(storagePath: String) -> Data? {
        let fileUrl = attachmentsBaseUrl.appendingPathComponent(storagePath)
        return try? Data(contentsOf: fileUrl)
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
        let attachments: [Attachment]?
        let playbooks: [Playbook]?
        let playbookAssessments: [PlaybookRuleAssessment]?
        let calendarNotes: [String: JournalNote]?
        let generalSettings: GeneralSettingsConfig?
        let currencyConversion: CurrencyConversion?
        let marketConnections: MarketConnectionConfig?
        let aiSettings: AiSettingsConfig?
    }
    
    public func saveToDisk() {
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
            propAudits: propAudits,
            attachments: attachments,
            playbooks: playbooks,
            playbookAssessments: playbookAssessments,
            calendarNotes: calendarNotes,
            generalSettings: generalSettings,
            currencyConversion: currencyConversion,
            marketConnections: marketConnections,
            aiSettings: aiSettings
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
            self.attachments = store.attachments ?? []
            self.playbooks = store.playbooks ?? []
            self.playbookAssessments = store.playbookAssessments ?? []
            self.calendarNotes = store.calendarNotes ?? [:]
            self.generalSettings = store.generalSettings ?? .default
            self.currencyConversion = store.currencyConversion ?? .default
            self.marketConnections = store.marketConnections ?? .default
            self.aiSettings = store.aiSettings ?? .default
            self.executionHashes = Set(store.executions.map { $0.contentHash })
            
            AppLogger.info("Loaded \(store.accounts.count) accounts, \(store.executions.count) executions, \(self.notebookNotes.count) notes, \(self.propAccounts.count) prop accounts, \(self.attachments.count) attachments from persistent disk.")
        } catch {
            AppLogger.error("Failed to load store from disk: \(error.localizedDescription)")
        }
    }
    
    private func createInitialDefaultAccount() {
        let defaultAcc = Account(
            id: "default-acc",
            name: "Tài Khoản Giao Dịch",
            broker: "",
            currency: "USD",
            initialBalance: 0
        )
        accounts = [defaultAcc]
        selectedAccountId = defaultAcc.id
        saveToDisk()
    }
    
    // MARK: - Manual Trade Management (Port from source-repo ManualTradeEntry)
    
    public func addManualTrade(
        accountId: String,
        symbol: String,
        direction: TradeDirection,
        quantity: Decimal,
        entryPrice: Decimal,
        exitPrice: Decimal?,
        openedAt: Date,
        closedAt: Date?,
        fee: Decimal = 0,
        notes: String? = nil,
        tags: [String] = [],
        mistakes: [String] = [],
        rating: Int? = nil,
        stopLoss: Decimal? = nil,
        profitTarget: Decimal? = nil,
        playbookId: String? = nil
    ) {
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        let entrySide: ExecutionSide = (direction == .long) ? .buy : .sell
        let halfFee = (exitPrice != nil) ? (fee / 2) : fee
        
        let entryFill = Execution(
            accountId: accountId,
            symbol: cleanSymbol,
            side: entrySide,
            quantity: quantity,
            price: entryPrice,
            fee: halfFee,
            executedAt: openedAt,
            source: "manual"
        )
        
        var newExecutions = [entryFill]
        
        if let exitP = exitPrice {
            let exitSide: ExecutionSide = (direction == .long) ? .sell : .buy
            let exitTime = closedAt ?? openedAt.addingTimeInterval(3600)
            let exitFill = Execution(
                accountId: accountId,
                symbol: cleanSymbol,
                side: exitSide,
                quantity: quantity,
                price: exitP,
                fee: halfFee,
                executedAt: exitTime,
                source: "manual"
            )
            newExecutions.append(exitFill)
        }
        
        for fill in newExecutions {
            executionHashes.insert(fill.contentHash)
            executions.append(fill)
        }
        
        rebuildAccount(accountId: accountId)
        
        // Find the newly reconstructed trade and set user annotations
        if let idx = trades.firstIndex(where: { t in
            t.accountId == accountId &&
            t.symbol == cleanSymbol &&
            abs(t.openedAt.timeIntervalSince(openedAt)) < 2
        }) {
            trades[idx].notes = notes
            trades[idx].tags = tags
            trades[idx].mistakes = mistakes
            trades[idx].rating = rating
            trades[idx].stopLoss = stopLoss
            trades[idx].profitTarget = profitTarget
            trades[idx].playbookId = playbookId
        }
        
        saveToDisk()
        AppLogger.info("Added manual trade for \(cleanSymbol). Total trades now: \(trades.count)")
    }
    
    public func deleteTrade(key: String) {
        guard let trade = trades.first(where: { $0.key == key }) else { return }
        let idsToDelete = Set(trade.executionIds)
        
        let deletedFills = executions.filter { idsToDelete.contains($0.id) }
        for fill in deletedFills {
            executionHashes.remove(fill.contentHash)
        }
        executions.removeAll { idsToDelete.contains($0.id) }
        
        rebuildAccount(accountId: trade.accountId)
        saveToDisk()
        AppLogger.info("Deleted trade \(key), remaining trades: \(trades.count)")
    }
    
    // MARK: - Playbooks & Discipline Assessments
    
    public func savePlaybook(_ playbook: Playbook) {
        if let idx = playbooks.firstIndex(where: { $0.id == playbook.id }) {
            playbooks[idx] = playbook
        } else {
            playbooks.append(playbook)
        }
        saveToDisk()
    }
    
    public func deletePlaybook(id: String) {
        playbooks.removeAll { $0.id == id }
        playbookAssessments.removeAll { $0.playbookId == id }
        saveToDisk()
    }
    
    public func setRuleAssessment(tradeKey: String, playbookId: String, rule: String, followed: Bool) {
        let assessment = PlaybookRuleAssessment(tradeKey: tradeKey, playbookId: playbookId, rule: rule, followed: followed)
        if let idx = playbookAssessments.firstIndex(where: { $0.id == assessment.id }) {
            playbookAssessments[idx] = assessment
        } else {
            playbookAssessments.append(assessment)
        }
        saveToDisk()
    }
    
    // MARK: - Calendar Notes
    
    public func saveCalendarNote(_ note: JournalNote) {
        calendarNotes[note.date] = note
        saveToDisk()
    }
    
    public func deleteCalendarNote(for date: String) {
        calendarNotes.removeValue(forKey: date)
        saveToDisk()
    }
    
    // MARK: - Data Reset
    
    public func resetAllData() {
        executions.removeAll()
        executionHashes.removeAll()
        trades.removeAll()
        calendarNotes.removeAll()
        propAccounts.removeAll()
        propEntries.removeAll()
        propReceipts.removeAll()
        propAudits.removeAll()
        attachments.removeAll()
        createInitialDefaultAccount()
        rebuildAllAccounts()
        saveToDisk()
        AppLogger.info("Reset all trading data to 100% clean blank state.")
    }
    
    /// Xuất danh sách giao dịch sang định dạng CSV 1:1 theo `api/export/route.ts`
    public func exportTradesCsv() -> String {
        let header = "key,account_id,symbol,direction,status,opened_at,closed_at,quantity,avg_entry,avg_exit,gross_pnl,fees,net_pnl,tags,notes"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        
        var lines = [header]
        for t in trades {
            let key = t.key
            let accId = t.accountId
            let symbol = t.symbol
            let direction = t.direction.rawValue
            let status = t.status.rawValue
            let openedAt = iso.string(from: t.openedAt)
            let closedAt = t.closedAt.map { iso.string(from: $0) } ?? ""
            let qty = "\(t.quantity)"
            let avgEntry = "\(t.avgEntry)"
            let avgExit = t.avgExit.map { "\($0)" } ?? ""
            let grossPnl = "\(t.grossPnl)"
            let fees = "\(t.fees)"
            let netPnl = "\(t.netPnl)"
            
            let tagsJson = (try? String(data: JSONEncoder().encode(t.tags), encoding: .utf8)) ?? "[]"
            let tagsCell = "\"" + tagsJson.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let notesCell = "\"" + (t.notes ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\""
            
            let row = [
                key, accId, symbol, direction, status, openedAt, closedAt, qty, avgEntry, avgExit, grossPnl, fees, netPnl, tagsCell, notesCell
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }
}

