import SwiftUI
import Combine

/// Central reactive data store managing accounts, trades, executions, notes, playbooks, and prop accounts
@MainActor
public final class TradeDataStore: ObservableObject {
    public static let shared = TradeDataStore()
    
    @Published public var accounts: [Account] = [] {
        didSet {
            invalidatePerformanceCaches()
        }
    }
    @Published public var executions: [Execution] = [] {
        didSet {
            invalidatePerformanceCaches()
        }
    }
    @Published public var trades: [Trade] = [] {
        didSet {
            invalidatePerformanceCaches()
        }
    }
    @Published public var selectedAccountId: String = "default-acc" {
        didSet {
            invalidatePerformanceCaches()
        }
    }
    @Published public private(set) var cacheVersion: Int = 0
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
    public var deletedPlaybookIds: Set<String> = []
    @Published public var calendarNotes: [String: JournalNote] = [:]
    @Published public var missedTrades: [MissedTrade] = []
    @Published public var progressRules: [ProgressRule] = []
    @Published public var progressChecks: [ProgressCheck] = []
    @Published public var generalSettings: GeneralSettingsConfig = .default
    @Published public var currencyConversion: CurrencyConversion = .default
    @Published public var marketConnections: MarketConnectionConfig = .default
    @Published public var aiSettings: AiSettingsConfig = .default
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncError: String? = nil
    @Published public var lastSyncSummary: String? = nil
    
    private var executionHashes: Set<String> = []
    
    // MARK: - Performance Caching
    private var _cachedFilteredTrades: [Trade]? = nil
    private var _cachedFilteredTradesAccountId: String? = nil
    
    private var _cachedVisibleAccounts: [Account]? = nil
    
    private var _cachedActiveAccounts: [Account]? = nil
    
    private var _cachedMostRecentActiveAccount: Account? = nil
    private var _cachedMostRecentActiveAccountValid: Bool = false
    
    public func invalidatePerformanceCaches() {
        _cachedFilteredTrades = nil
        _cachedFilteredTradesAccountId = nil
        _cachedVisibleAccounts = nil
        _cachedActiveAccounts = nil
        _cachedMostRecentActiveAccount = nil
        _cachedMostRecentActiveAccountValid = false
        activePropAccountIdsCache = nil
        inactivePropAccountIdsCache = nil
        cacheVersion &+= 1
    }
    
    private var persistenceUrl: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("trade_journal_store_v1.json")
    }
    
    public init() {
        loadFromDisk()
        if accounts.isEmpty {
            createInitialDefaultAccount()
        } else if accounts.contains(where: { $0.id != "default-acc" }) {
            accounts.removeAll(where: { $0.id == "default-acc" })
        }
        if folders.isEmpty {
            folders = NotebookEngine.defaultSystemFolders
        }
        if selectedAccountId == "default-acc" || (!accounts.contains(where: { $0.id == selectedAccountId }) && selectedAccountId != "all") {
            selectedAccountId = mostRecentActiveAccount?.id ?? "all"
        }
        rebuildAllAccounts()
    }
    
    public var availableCurrencies: [String] {
        let list = (visibleAccounts.isEmpty ? accounts : visibleAccounts).map { $0.currency.uppercased() }
        let unique = Array(Set(list)).sorted()
        return unique.isEmpty ? ["USD"] : unique
    }
    
    private var activePropAccountIdsCache: Set<String>? = nil
    private var inactivePropAccountIdsCache: Set<String>? = nil
    
    public func refreshActiveAccountCache() {
        var activeIds = Set<String>()
        var inactiveIds = Set<String>()
        for p in propAccounts {
            let s = p.status.rawValue.lowercased()
            let isActive = (s == "active" || s == "funded" || s == "open")
            let candidates = [
                p.id,
                p.journalAccountId ?? "",
                p.id.hasPrefix("the5ers_") ? String(p.id.dropFirst(8)) : "the5ers_\(p.id)"
            ].filter { !$0.isEmpty }
            for c in candidates {
                if isActive {
                    activeIds.insert(c)
                } else {
                    inactiveIds.insert(c)
                }
            }
        }
        activePropAccountIdsCache = activeIds
        inactivePropAccountIdsCache = inactiveIds
    }
    
    public func isAccountActive(_ account: Account) -> Bool {
        if account.archivedAt != nil { return false }
        if activePropAccountIdsCache == nil {
            refreshActiveAccountCache()
        }
        let accId = account.id
        if activePropAccountIdsCache?.contains(accId) == true {
            return true
        }
        if inactivePropAccountIdsCache?.contains(accId) == true {
            return false
        }
        let clean = accId.hasPrefix("the5ers_") ? String(accId.dropFirst(8)) : "the5ers_\(accId)"
        if activePropAccountIdsCache?.contains(clean) == true {
            return true
        }
        if inactivePropAccountIdsCache?.contains(clean) == true {
            return false
        }
        return true
    }

    public func isAccountVisible(_ account: Account) -> Bool {
        if let v = account.visibleInJournal {
            return v
        }
        return account.archivedAt == nil
    }

    public var visibleAccounts: [Account] {
        if let cached = _cachedVisibleAccounts {
            return cached
        }
        let result = accounts.filter { isAccountVisible($0) }
        _cachedVisibleAccounts = result
        return result
    }

    public var visibleAccountIds: Set<String> {
        var ids = Set<String>()
        for acc in visibleAccounts {
            ids.insert(acc.id)
            let clean = acc.id.hasPrefix("the5ers_") ? String(acc.id.dropFirst(8)) : acc.id
            ids.insert(clean)
            ids.insert("the5ers_\(clean)")
        }
        for prop in propAccounts {
            if isPropAccountVisible(prop) {
                ids.insert(prop.id)
                let clean = prop.id.hasPrefix("the5ers_") ? String(prop.id.dropFirst(8)) : prop.id
                ids.insert(clean)
                ids.insert("the5ers_\(clean)")
                if let jId = prop.journalAccountId, !jId.isEmpty {
                    ids.insert(jId)
                    let cleanJ = jId.hasPrefix("the5ers_") ? String(jId.dropFirst(8)) : jId
                    ids.insert(cleanJ)
                    ids.insert("the5ers_\(cleanJ)")
                }
            }
        }
        return ids
    }

    public func isPropAccountVisible(_ prop: PropAccountItem) -> Bool {
        if let acc = accounts.first(where: {
            $0.id == prop.journalAccountId ||
            $0.id == prop.id ||
            $0.id == "the5ers_\(prop.id)" ||
            (prop.id.hasPrefix("the5ers_") && $0.id == String(prop.id.dropFirst(8)))
        }) {
            return isAccountVisible(acc)
        }
        return !prop.archived
    }

    public func isPropEntryVisible(_ entry: PropEntryItem) -> Bool {
        guard let entryAccId = entry.accountId, !entryAccId.isEmpty else {
            return true
        }
        if let prop = propAccounts.first(where: { $0.id == entryAccId }) {
            return isPropAccountVisible(prop)
        }
        if let acc = accounts.first(where: {
            $0.id == entryAccId ||
            $0.id == "the5ers_\(entryAccId)" ||
            (entryAccId.hasPrefix("the5ers_") && $0.id == String(entryAccId.dropFirst(8)))
        }) {
            return isAccountVisible(acc)
        }
        return true
    }

    public var activeAccounts: [Account] {
        if let cached = _cachedActiveAccounts {
            return cached
        }
        let result = accounts.filter { isAccountActive($0) }
        _cachedActiveAccounts = result
        return result
    }

    public var mostRecentActiveAccount: Account? {
        if _cachedMostRecentActiveAccountValid {
            return _cachedMostRecentActiveAccount
        }
        
        let active = activeAccounts
        guard !active.isEmpty else {
            _cachedMostRecentActiveAccount = accounts.first
            _cachedMostRecentActiveAccountValid = true
            return accounts.first
        }
        
        // Single O(Trades) pass to find the latest trade timestamp for each account ID
        var latestTradeDateByAccountId: [String: Date] = [:]
        for trade in trades {
            let id = trade.accountId
            if let existing = latestTradeDateByAccountId[id] {
                if trade.openedAt > existing {
                    latestTradeDateByAccountId[id] = trade.openedAt
                }
            } else {
                latestTradeDateByAccountId[id] = trade.openedAt
            }
        }
        
        // Find the active account with the latest trade
        var bestAccount: Account? = nil
        var bestDate: Date = .distantPast
        
        for acc in active {
            let candidates = [
                acc.id,
                "the5ers_\(acc.id)",
                acc.id.hasPrefix("the5ers_") ? String(acc.id.dropFirst(8)) : ""
            ]
            for cand in candidates where !cand.isEmpty {
                if let d = latestTradeDateByAccountId[cand], d > bestDate {
                    bestDate = d
                    bestAccount = acc
                }
            }
        }
        
        let result = bestAccount ?? active.first ?? accounts.first
        _cachedMostRecentActiveAccount = result
        _cachedMostRecentActiveAccountValid = true
        return result
    }

    public var selectedAccount: Account? {
        if selectedAccountId == "all" {
            return mostRecentActiveAccount ?? visibleAccounts.first ?? accounts.first
        }
        let selId = selectedAccountId
        let cleanSel = selId.hasPrefix("the5ers_") ? String(selId.dropFirst(8)) : selId
        let altId = "the5ers_\(cleanSel)"
        return accounts.first(where: { $0.id == selId || $0.id == cleanSel || $0.id == altId }) ?? mostRecentActiveAccount ?? accounts.first
    }

    public var filteredTrades: [Trade] {
        if let cached = _cachedFilteredTrades,
           _cachedFilteredTradesAccountId == selectedAccountId {
            return cached
        }
        let result: [Trade]
        if selectedAccountId == "all" {
            let visibleIds = visibleAccountIds
            result = trades.filter { trade in
                if visibleIds.contains(trade.accountId) { return true }
                let clean = trade.accountId.hasPrefix("the5ers_") ? String(trade.accountId.dropFirst(8)) : trade.accountId
                if visibleIds.contains(clean) { return true }
                if visibleIds.contains("the5ers_\(clean)") { return true }
                return false
            }
        } else {
            let selId = selectedAccountId
            let cleanSel = selId.hasPrefix("the5ers_") ? String(selId.dropFirst(8)) : selId
            let altId = "the5ers_\(cleanSel)"
            result = trades.filter { trade in
                trade.accountId == selId || trade.accountId == cleanSel || trade.accountId == altId
            }
        }
        _cachedFilteredTrades = result
        _cachedFilteredTradesAccountId = selectedAccountId
        return result
    }
    
    public var existingHashesForSelectedAccount: Set<String> {
        Set(executions.filter { $0.accountId == selectedAccountId }.map { $0.contentHash })
    }
    
    public func selectAccount(id: String) {
        guard selectedAccountId != id else { return }
        selectedAccountId = id
        invalidatePerformanceCaches()
        saveToDisk()
        objectWillChange.send()
    }
    
    public func addAccount(name: String, broker: String = "", currency: String = "USD", initialBalance: Decimal = 0, profitCalcMethod: ProfitCalcMethod = .fifo) {
        let newAccount = Account(
            name: name,
            broker: broker,
            currency: currency,
            initialBalance: initialBalance,
            profitCalcMethod: profitCalcMethod
        )
        accounts.append(newAccount)
        selectedAccountId = newAccount.id
        saveToDisk()
        AppLogger.info("Added account: \(name) (\(newAccount.id))")
    }
    
    public func archiveAccount(id: String, archived: Bool) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].archivedAt = archived ? Date() : nil
            invalidatePerformanceCaches()
            saveToDisk()
            objectWillChange.send()
        }
    }

    public func updateAccount(
        id: String,
        name: String,
        broker: String,
        kind: AccountKind,
        currency: String,
        initialBalance: Decimal
    ) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[idx].broker = broker.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[idx].kind = kind
        accounts[idx].currency = currency
        accounts[idx].initialBalance = initialBalance
        invalidatePerformanceCaches()
        saveToDisk()
        objectWillChange.send()
        let updatedAcc = accounts[idx]
        Task {
            try? await SupabaseService.shared.upsertAccounts([updatedAcc])
        }
    }
    
    public func deleteAccount(id: String) {
        accounts.removeAll(where: { $0.id == id })
        trades.removeAll(where: { $0.accountId == id })
        executions.removeAll(where: { $0.accountId == id })
        if selectedAccountId == id {
            selectedAccountId = accounts.first?.id ?? "all"
        }
        invalidatePerformanceCaches()
        saveToDisk()
        objectWillChange.send()
        Task {
            try? await SupabaseService.shared.deleteAccount(id: id)
        }
    }
    
    public func toggleAccountAutoSync(id: String) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx].autoSync.toggle()
            saveToDisk()
        }
    }
    
    public func toggleAccountVisibility(id: String) {
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            let current = isAccountVisible(accounts[idx])
            accounts[idx].visibleInJournal = !current
            invalidatePerformanceCaches()
            saveToDisk()
            objectWillChange.send()
        }
    }
    
    public func setBulkAccountVisibility(action: String) {
        for idx in accounts.indices {
            switch action {
            case "select-all":
                accounts[idx].visibleInJournal = true
            case "select-active":
                accounts[idx].visibleInJournal = (accounts[idx].archivedAt == nil)
            case "deselect-all":
                accounts[idx].visibleInJournal = false
            default:
                break
            }
        }
        invalidatePerformanceCaches()
        saveToDisk()
        objectWillChange.send()
    }
    
    /// Imports new fills for an account and triggers reconstruction
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
    
    /// Reconstructs round trips from raw executions using account profit calculation method
    public func rebuildAccount(accountId: String) {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        
        // The5ers accounts store reported positions directly as round trips and do not use atomic execution reconstruction
        if accountId.hasPrefix("the5ers_") || (account.broker.lowercased() == "the5ers") {
            return
        }
        
        let accountFills = executions.filter { $0.accountId == accountId }
        let reconstructed = TradeReconstructionEngine.buildRoundTrips(
            executions: accountFills,
            options: .init(method: account.profitCalcMethod, multipliers: multipliers)
        )
        
        // Preserve existing user annotations (notes, tags, mistakes, ratings, risk levels) across rebuilds
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
                // Apply default account risk rules if annotations do not set stop loss / target
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
    
    public static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cancel") { return true }
        return false
    }
    
    public static func isSameAccountId(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let cleanA = a.hasPrefix("the5ers_") ? String(a.dropFirst(8)) : a
        let cleanB = b.hasPrefix("the5ers_") ? String(b.dropFirst(8)) : b
        return cleanA == cleanB
    }
    
    public func deduplicateAndCleanAccounts() {
        refreshActiveAccountCache()
        
        // 0. Build canonical account ID map and re-link any trades pointing to phantom accounts
        var canonicalMap: [String: String] = [:]
        for acc in accounts where !acc.name.hasPrefix("Account ") {
            let clean = acc.id.hasPrefix("the5ers_") ? String(acc.id.dropFirst(8)) : acc.id
            canonicalMap[clean] = acc.id
            canonicalMap["the5ers_\(clean)"] = acc.id
            canonicalMap[acc.id] = acc.id
        }
        for i in 0..<trades.count {
            if let canonical = canonicalMap[trades[i].accountId] {
                trades[i].accountId = canonical
            } else {
                let clean = trades[i].accountId.hasPrefix("the5ers_") ? String(trades[i].accountId.dropFirst(8)) : trades[i].accountId
                if let canonical = canonicalMap[clean] {
                    trades[i].accountId = canonical
                }
            }
        }
        
        // 1. Purge phantom accounts generated previously with "Account <id>"
        if accounts.contains(where: { !$0.name.hasPrefix("Account ") }) {
            accounts.removeAll(where: { $0.name.hasPrefix("Account ") })
        }

        // 2. Deduplicate accounts (merge '12345' into 'the5ers_12345')
        var seenCleanAccIds = Set<String>()
        var cleanedAccounts: [Account] = []
        for acc in accounts {
            let clean = acc.id.hasPrefix("the5ers_") ? String(acc.id.dropFirst(8)) : acc.id
            if seenCleanAccIds.contains(clean) {
                if acc.id.hasPrefix("the5ers_"), let idx = cleanedAccounts.firstIndex(where: { Self.isSameAccountId($0.id, acc.id) }) {
                    cleanedAccounts[idx] = acc
                }
                continue
            }
            seenCleanAccIds.insert(clean)
            cleanedAccounts.append(acc)
        }
        if cleanedAccounts.count != accounts.count {
            AppLogger.info("Deduplicated accounts: \(accounts.count) -> \(cleanedAccounts.count)")
            self.accounts = cleanedAccounts
        }

        // 2. Deduplicate propAccounts
        var seenCleanPropIds = Set<String>()
        var cleanedPropAccounts: [PropAccountItem] = []
        for p in propAccounts {
            let clean = p.id.hasPrefix("the5ers_") ? String(p.id.dropFirst(8)) : p.id
            if seenCleanPropIds.contains(clean) {
                if p.id.hasPrefix("the5ers_"), let idx = cleanedPropAccounts.firstIndex(where: { Self.isSameAccountId($0.id, p.id) }) {
                    cleanedPropAccounts[idx] = p
                }
                continue
            }
            seenCleanPropIds.insert(clean)
            cleanedPropAccounts.append(p)
        }
        if cleanedPropAccounts.count != propAccounts.count {
            AppLogger.info("Deduplicated prop accounts: \(propAccounts.count) -> \(cleanedPropAccounts.count)")
            self.propAccounts = cleanedPropAccounts
        }

        // 3. Remove synthetic executions and reconstructed trades on The5ers accounts
        let the5ersAccountIds = Set(accounts.filter { $0.broker.lowercased() == "the5ers" || $0.id.hasPrefix("the5ers_") }.flatMap { [$0.id, $0.id.hasPrefix("the5ers_") ? String($0.id.dropFirst(8)) : "the5ers_\($0.id)"] })
        executions.removeAll(where: { $0.id.hasPrefix("the5ers_exec_") || $0.source == "the5ers" })
        trades.removeAll(where: { trade in
            (the5ersAccountIds.contains(trade.accountId) || trade.accountId.hasPrefix("the5ers_") || trade.tags.contains("the5ers")) && !trade.key.hasPrefix("the5ers_")
        })

        // 4. Deduplicate trades by key
        var seenTradeKeys = Set<String>()
        var cleanedTrades: [Trade] = []
        for t in trades {
            if !seenTradeKeys.contains(t.key) {
                seenTradeKeys.insert(t.key)
                cleanedTrades.append(t)
            }
        }
        if cleanedTrades.count != trades.count {
            AppLogger.info("Deduplicated trades: \(trades.count) -> \(cleanedTrades.count)")
            self.trades = cleanedTrades
        }
    }
    
    public func rebuildAllAccounts(forceRebuildTrades: Bool = false) {
        deduplicateAndCleanAccounts()
        for i in 0..<accounts.count {
            accounts[i].name = Formatters.cleanAccountName(accounts[i].name, balance: accounts[i].initialBalance)
        }
        for i in 0..<propAccounts.count {
            let sizeBal = propAccounts[i].sizeMinor.map { Decimal($0) / 100 }
            propAccounts[i].name = Formatters.cleanAccountName(propAccounts[i].name, balance: sizeBal)
        }
        // Only reconstruct round trips from raw executions if explicitly requested or if trades are missing
        if forceRebuildTrades || (trades.isEmpty && !executions.isEmpty) {
            for acc in accounts {
                rebuildAccount(accountId: acc.id)
            }
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

        // 1. Synchronize Accounts
        do {
            let remoteAccounts = (try await SupabaseService.shared.fetchAccounts()).filter { !$0.name.hasPrefix("Account ") }
            fetchedAccountsCount = remoteAccounts.count
            if !remoteAccounts.isEmpty {
                for rAcc in remoteAccounts {
                    if let idx = accounts.firstIndex(where: { Self.isSameAccountId($0.id, rAcc.id) }) {
                        var updated = rAcc
                        if let localVisible = accounts[idx].visibleInJournal {
                            updated.visibleInJournal = localVisible
                        }
                        accounts[idx] = updated
                    } else {
                        accounts.append(rAcc)
                    }
                }
                if selectedAccountId == "default-acc" || (!accounts.contains(where: { $0.id == selectedAccountId }) && selectedAccountId != "all") {
                    selectedAccountId = "all"
                }
                accounts.removeAll(where: { $0.id == "default-acc" && accounts.count > 1 })
            }
            
            // Ensure all accounts referenced by prop accounts and trades exist prior to upload
            var mergedAccountList = accounts.filter { !$0.name.hasPrefix("Account ") }
            let existingAccIds = Set(mergedAccountList.map { $0.id })
            
            for p in propAccounts {
                if let jId = p.journalAccountId, !jId.isEmpty && !existingAccIds.contains(jId) {
                    if !mergedAccountList.contains(where: { Self.isSameAccountId($0.id, jId) }) {
                        mergedAccountList.append(Account(id: jId, name: p.name, broker: p.firm, kind: .sync, currency: p.currency))
                    }
                }
            }
            // Normalize trades to link with known accounts without creating phantom accounts
            for i in 0..<trades.count {
                let tAcc = trades[i].accountId
                if let matched = mergedAccountList.first(where: { Self.isSameAccountId($0.id, tAcc) }) {
                    trades[i].accountId = matched.id
                }
            }
            self.accounts = mergedAccountList
            deduplicateAndCleanAccounts()
            
            if !accounts.isEmpty {
                do {
                    try await SupabaseService.shared.upsertAccounts(accounts)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.error("Supabase accounts upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Accounts upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.error("Supabase accounts sync warning: \(error.localizedDescription)")
            syncWarnings.append("Accounts: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // 2. Synchronize Trades
        do {
            let remoteTrades = try await SupabaseService.shared.fetchTrades(accountId: nil)
            fetchedTradesCount = remoteTrades.count
            for rTrade in remoteTrades {
                if let idx = trades.firstIndex(where: { $0.key == rTrade.key }) {
                    let local = trades[idx]
                    if (local.netPnl != 0 || local.grossPnl != 0) && (rTrade.netPnl == 0 && rTrade.grossPnl == 0) {
                        // Keep local non-zero PnL if remote has zero PnL
                    } else {
                        trades[idx] = rTrade
                    }
                } else {
                    trades.append(rTrade)
                }
                // Re-link trade accountId to known accounts without creating phantom accounts
                if !rTrade.accountId.isEmpty {
                    if let matched = accounts.first(where: { Self.isSameAccountId($0.id, rTrade.accountId) }) {
                        if let lastIdx = trades.indices.last, trades[lastIdx].key == rTrade.key {
                            trades[lastIdx].accountId = matched.id
                        }
                    }
                }
            }
            if selectedAccountId != "all" && !accounts.contains(where: { $0.id == selectedAccountId }) {
                selectedAccountId = "all"
            }
            if !trades.isEmpty {
                do {
                    try await SupabaseService.shared.upsertTrades(trades)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.error("Supabase trades upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Trades upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.error("Supabase trades sync warning: \(error.localizedDescription)")
            syncWarnings.append("Trades: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // 3. Synchronize Executions
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
                do {
                    try await SupabaseService.shared.upsertExecutions(executions)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.error("Supabase executions upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Executions upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.error("Supabase executions sync warning: \(error.localizedDescription)")
            syncWarnings.append("Executions: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // Supabase playbooks sync
        do {
            let remotePlaybooks = try await SupabaseService.shared.fetchPlaybooks()
            for rPb in remotePlaybooks {
                if deletedPlaybookIds.contains(rPb.id) || (rPb.name.lowercased().contains("test playbook") && deletedPlaybookIds.contains(rPb.id)) {
                    Task { try? await SupabaseService.shared.deletePlaybook(id: rPb.id) }
                    continue
                }
                if let idx = playbooks.firstIndex(where: { $0.id == rPb.id }) {
                    playbooks[idx] = rPb
                } else {
                    playbooks.append(rPb)
                }
            }
            let localUserPlaybooks = playbooks.filter { pb in
                !deletedPlaybookIds.contains(pb.id) && !remotePlaybooks.contains(where: { $0.id == pb.id })
            }
            if !localUserPlaybooks.isEmpty {
                do {
                    try await SupabaseService.shared.upsertPlaybooks(localUserPlaybooks)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.warning("Supabase playbooks upsert warning: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase playbooks sync warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // Supabase journal_days (calendar notes) sync
        do {
            let remoteNotes = try await SupabaseService.shared.fetchJournalDays()
            for rNote in remoteNotes {
                if let local = calendarNotes[rNote.date] {
                    if rNote.updatedAt >= local.updatedAt {
                        calendarNotes[rNote.date] = rNote
                        journalDays[rNote.date] = rNote.content
                    }
                } else {
                    calendarNotes[rNote.date] = rNote
                    journalDays[rNote.date] = rNote.content
                }
            }
            let localNotesToUpload = calendarNotes.values.filter { local in
                !remoteNotes.contains(where: { $0.date == local.date && $0.updatedAt >= local.updatedAt })
            }
            if !localNotesToUpload.isEmpty {
                try? await SupabaseService.shared.upsertJournalDays(Array(localNotesToUpload))
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase journal_days sync warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // 4. Synchronize Prop Accounts
        do {
            let remotePropAccounts = try await SupabaseService.shared.fetchPropAccounts()
            fetchedPropCount = remotePropAccounts.count
            for rAcc in remotePropAccounts {
                if let idx = propAccounts.firstIndex(where: { Self.isSameAccountId($0.id, rAcc.id) }) {
                    if rAcc.revision >= propAccounts[idx].revision {
                        propAccounts[idx] = rAcc
                    }
                } else {
                    propAccounts.append(rAcc)
                }
            }
            // Sanitize journalAccountId and parentId before uploading prop accounts
            let validAccIds = Set(accounts.map { $0.id })
            let validPropIds = Set(propAccounts.map { $0.id })
            for idx in 0..<propAccounts.count {
                if let jId = propAccounts[idx].journalAccountId, !jId.isEmpty {
                    if !validAccIds.contains(jId) {
                        if let matched = accounts.first(where: { Self.isSameAccountId($0.id, jId) }) {
                            propAccounts[idx].journalAccountId = matched.id
                        } else {
                            propAccounts[idx].journalAccountId = nil
                        }
                    }
                }
                if let pId = propAccounts[idx].parentId, !pId.isEmpty {
                    if !validPropIds.contains(pId) {
                        propAccounts[idx].parentId = nil
                    }
                }
            }
            
            if !propAccounts.isEmpty {
                do {
                    try await SupabaseService.shared.upsertPropAccounts(propAccounts)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.warning("Supabase prop accounts upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Prop accounts upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase prop accounts warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

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
            
            // Sanitize accountId and parentId before uploading prop entries
            let currentPropIds = Set(propAccounts.map { $0.id })
            let currentEntryIds = Set(propEntries.map { $0.id })
            for idx in 0..<propEntries.count {
                if let aId = propEntries[idx].accountId, !aId.isEmpty {
                    if !currentPropIds.contains(aId) {
                        if let matched = propAccounts.first(where: { Self.isSameAccountId($0.id, aId) }) {
                            propEntries[idx].accountId = matched.id
                        } else if let firstProp = propAccounts.first {
                            propEntries[idx].accountId = firstProp.id
                        } else {
                            propEntries[idx].accountId = nil
                        }
                    }
                }
                if let pId = propEntries[idx].parentId, !pId.isEmpty {
                    if !currentEntryIds.contains(pId) {
                        propEntries[idx].parentId = nil
                    }
                }
            }
            
            if !propEntries.isEmpty {
                do {
                    try await SupabaseService.shared.upsertPropEntries(propEntries)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.warning("Supabase prop entries upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Prop entries upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase prop entries warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        do {
            let remotePropReceipts = try await SupabaseService.shared.fetchPropReceipts()
            for rRcpt in remotePropReceipts {
                if let idx = propReceipts.firstIndex(where: { $0.id == rRcpt.id }) {
                    propReceipts[idx] = rRcpt
                } else {
                    propReceipts.append(rRcpt)
                }
            }
            
            // Filter receipts to ensure referenced payout entry exists to avoid FK errors
            let validEntryIds = Set(propEntries.map { $0.id })
            var validReceipts: [PropReceiptItem] = []
            for var rcpt in propReceipts {
                if validEntryIds.contains(rcpt.payoutId) {
                    validReceipts.append(rcpt)
                } else if let matched = propEntries.first(where: { $0.id.contains(rcpt.payoutId) || rcpt.payoutId.contains($0.id) }) {
                    rcpt.payoutId = matched.id
                    validReceipts.append(rcpt)
                } else {
                    AppLogger.warning("Supabase sync: Skipping receipt \(rcpt.id) because referenced payout entry \(rcpt.payoutId) does not exist.")
                }
            }
            
            if !validReceipts.isEmpty {
                do {
                    try await SupabaseService.shared.upsertPropReceipts(validReceipts)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.warning("Supabase prop receipts upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Prop receipts upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase prop receipts warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        do {
            let remotePropAudits = try await SupabaseService.shared.fetchPropAudits()
            for rAudit in remotePropAudits {
                if !propAudits.contains(where: { $0.id == rAudit.id }) {
                    propAudits.append(rAudit)
                }
            }
            if !propAudits.isEmpty {
                do {
                    try await SupabaseService.shared.upsertPropAudits(propAudits)
                } catch {
                    if Self.isCancellation(error) { return }
                    AppLogger.warning("Supabase prop audits upsert warning: \(error.localizedDescription)")
                    syncWarnings.append("Prop audits upload: \(error.localizedDescription)")
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase prop audits warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // 5. Synchronize Attachments
        do {
            let remoteAttachments = try await SupabaseService.shared.fetchAttachments()
            for rAtt in remoteAttachments {
                if !attachments.contains(where: { $0.id == rAtt.id }) {
                    attachments.append(rAtt)
                }
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase attachments warning: \(error.localizedDescription)")
        }

        if Task.isCancelled {
            await MainActor.run { self.isSyncing = false }
            return
        }

        deduplicateAndCleanAccounts()
        saveToDisk()

        let totalRecords = fetchedAccountsCount + fetchedTradesCount + fetchedExecutionsCount + fetchedPropCount
        await MainActor.run {
            if totalRecords > 0 {
                var summary = "Supabase sync successful: Downloaded \(fetchedAccountsCount) accounts, \(fetchedTradesCount) trades, \(fetchedExecutionsCount) executions, \(fetchedPropCount) prop accounts."
                if !syncWarnings.isEmpty {
                    summary += " (Warnings: \(syncWarnings.joined(separator: "; ")))"
                }
                self.lastSyncSummary = summary
                self.lastSyncError = nil
            } else if !syncWarnings.isEmpty {
                self.lastSyncError = syncWarnings.joined(separator: "\n")
            } else {
                self.lastSyncSummary = "Supabase connection successful. Local and cloud data are synchronized (0 new records)."
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
                self.lastSyncSummary = "The5ers MCP synchronized successfully: \(count) accounts, \(self.trades.filter { $0.tags.contains("the5ers") }.count) trades."
            } else {
                self.lastSyncSummary = The5ersService.shared.lastStatus
            }
        }
        return count
    }
    
    // MARK: - cTrader Open API Synchronization
    
    public func syncWithCTrader() async throws -> CTraderSyncSummary {
        await MainActor.run {
            self.isSyncing = true
            self.lastSyncError = nil
        }
        defer {
            Task { @MainActor in self.isSyncing = false }
        }
        let summary = try await CTraderService.shared.syncWithTradeStore(dataStore: self)
        await MainActor.run {
            self.lastSyncSummary = summary.message
        }
        return summary
    }
    
    // MARK: - Unified Global Synchronization
    
    public func performGlobalSync() async {
        await SyncManager.shared.performQuickSync()
    }
    
    private func legacyPerformGlobalSync() async {
        guard !isSyncing else { return }
        
        await MainActor.run {
            self.isSyncing = true
            self.lastSyncError = nil
            self.lastSyncSummary = "Connecting to services..."
        }
        defer {
            Task { @MainActor in self.isSyncing = false }
        }
        
        let hasThe5ers = The5ersService.shared.isConfigured
        let hasCTrader = CTraderService.shared.isConfigured
        let hasSupabase = SupabaseService.shared.isConfigured
        
        guard hasThe5ers || hasCTrader || hasSupabase else {
            await MainActor.run {
                self.lastSyncError = "No sync provider configured. Open Settings to connect cTrader, The5ers MCP, or Supabase Cloud."
                self.lastSyncSummary = nil
            }
            return
        }
        
        var the5ersCount = 0
        var the5ersErrorMsg: String? = nil
        var the5ersSuccess = false
        
        // 1. Pull fresh accounts, positions, purchases, and payouts from The5ers MCP Hub
        if hasThe5ers {
            if Task.isCancelled { return }
            await MainActor.run {
                self.lastSyncSummary = "Fetching accounts & positions from The5ers Hub..."
            }
            do {
                the5ersCount = try await The5ersService.shared.syncWithTradeStore(dataStore: self)
                the5ersSuccess = true
            } catch {
                if Self.isCancellation(error) {
                    AppLogger.info("The5ers sync cancelled.")
                    return
                }
                AppLogger.error("The5ers sync failed: \(error.localizedDescription)")
                let nsErr = error as NSError
                if nsErr.code == 401 || error.localizedDescription.contains("401") || error.localizedDescription.localizedCaseInsensitiveContains("unauthorized") {
                    the5ersErrorMsg = "The5ers session token expired or invalid (401). Please re-login in Settings."
                } else {
                    the5ersErrorMsg = "The5ers: \(error.localizedDescription)"
                }
            }
        }
        
        if Task.isCancelled { return }
        
        // 2. Synchronize cTrader accounts and executions
        var cTraderErrorMsg: String? = nil
        var cTraderSummary: CTraderSyncSummary? = nil
        if hasCTrader {
            if Task.isCancelled { return }
            await MainActor.run {
                self.lastSyncSummary = "Fetching accounts & deals from cTrader Open API..."
            }
            do {
                cTraderSummary = try await CTraderService.shared.syncWithTradeStore(dataStore: self)
            } catch {
                if Self.isCancellation(error) {
                    AppLogger.info("cTrader sync cancelled.")
                    return
                }
                AppLogger.error("cTrader sync failed: \(error.localizedDescription)")
                cTraderErrorMsg = "cTrader: \(error.localizedDescription)"
            }
        }
        
        if Task.isCancelled { return }
        
        // 3. Synchronize with Supabase Cloud PostgreSQL database
        var supabaseErrorMsg: String? = nil
        var supabaseSuccess = false
        if hasSupabase {
            if Task.isCancelled { return }
            await MainActor.run {
                self.lastSyncSummary = "Synchronizing with Supabase Cloud Database..."
            }
            await syncWithSupabase()
            if Task.isCancelled { return }
            if let supErr = self.lastSyncError {
                if !supErr.lowercased().contains("cancel") {
                    supabaseErrorMsg = supErr
                }
            } else {
                supabaseSuccess = true
            }
        }
        
        if Task.isCancelled { return }
        
        // 4. Final summary state update
        await MainActor.run {
            var errors: [String] = []
            if let tErr = the5ersErrorMsg { errors.append(tErr) }
            if let cErr = cTraderErrorMsg { errors.append(cErr) }
            if let sErr = supabaseErrorMsg { errors.append("Supabase: \(sErr)") }
            
            if !errors.isEmpty {
                self.lastSyncError = errors.joined(separator: "\n")
            } else {
                self.lastSyncError = nil
            }
            
            var details: [String] = []
            if hasThe5ers && the5ersSuccess {
                let the5ersTradesCount = self.trades.filter { $0.tags.contains("the5ers") }.count
                details.append("The5ers: \(the5ersCount) accounts (\(the5ersTradesCount) trades)")
            }
            if let cSummary = cTraderSummary {
                details.append("cTrader: \(cSummary.accountsSynced) accounts (\(cSummary.dealsImported) deals)")
            }
            if hasSupabase && supabaseSuccess {
                details.append("Supabase Cloud backed up")
            }
            
            if !details.isEmpty {
                self.lastSyncSummary = "Sync completed: \(details.joined(separator: " • "))"
            }
        }
    }
    
    // MARK: - Notebook & Folders Management
    
    public func createFolder(name: String) throws -> NotebookFolder {
        let (folder, updated) = try NotebookEngine.createFolder(name: name, existingFolders: folders)
        self.folders = updated
        saveToDisk()
        return folder
    }

    public func renameFolder(id: String, name: String) throws {
        let updated = try NotebookEngine.renameFolder(id: id, name: name, existingFolders: folders)
        self.folders = updated
        saveToDisk()
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
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteCalendarNote(for: date)
            return
        }
        self.journalDays[date] = note
        let jNote = JournalNote(date: date, content: note, updatedAt: Date())
        self.calendarNotes[date] = jNote
        saveToDisk()
        Task {
            try? await SupabaseService.shared.upsertJournalDay(jNote)
        }
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
    
    public func deletePropAccount(id: String) {
        let entryIds = Set(propEntries.filter { $0.accountId == id }.map { $0.id })
        propAccounts.removeAll { $0.id == id }
        propEntries.removeAll { $0.accountId == id }
        propReceipts.removeAll { entryIds.contains($0.payoutId) }
        saveToDisk()
        Task {
            try? await SupabaseService.shared.deletePropAccount(id: id)
        }
    }

    public func deletePropEntry(id: String) {
        propEntries.removeAll { $0.id == id }
        propReceipts.removeAll { $0.payoutId == id }
        saveToDisk()
        Task {
            try? await SupabaseService.shared.deletePropEntry(id: id)
        }
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
        
        // Automatically transition payout status to approved if receipt is recorded
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
        
        // Ensure cumulative receipt sum is non-negative after receipt void/reversal
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

    // MARK: - Attachments Management
    
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
        let missedTrades: [MissedTrade]?
        let progressRules: [ProgressRule]?
        let progressChecks: [ProgressCheck]?
        let generalSettings: GeneralSettingsConfig?
        let currencyConversion: CurrencyConversion?
        let marketConnections: MarketConnectionConfig?
        let aiSettings: AiSettingsConfig?
        let deletedPlaybookIds: [String]?
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
            missedTrades: missedTrades,
            progressRules: progressRules,
            progressChecks: progressChecks,
            generalSettings: generalSettings,
            currencyConversion: currencyConversion,
            marketConnections: marketConnections,
            aiSettings: aiSettings,
            deletedPlaybookIds: Array(deletedPlaybookIds)
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
            self.deletedPlaybookIds = Set(store.deletedPlaybookIds ?? [])
            self.calendarNotes = store.calendarNotes ?? [:]
            self.missedTrades = store.missedTrades ?? []
            self.progressRules = store.progressRules ?? Self.defaultProgressRules
            self.progressChecks = store.progressChecks ?? []
            self.generalSettings = store.generalSettings ?? .default
            self.currencyConversion = store.currencyConversion ?? .default
            self.marketConnections = store.marketConnections ?? .default
            self.aiSettings = store.aiSettings ?? .default
            self.executionHashes = Set(store.executions.map { $0.contentHash })
            invalidatePerformanceCaches()
            
            AppLogger.info("Loaded \(store.accounts.count) accounts, \(store.executions.count) executions, \(self.notebookNotes.count) notes, \(self.propAccounts.count) prop accounts, \(self.attachments.count) attachments from persistent disk.")
        } catch {
            AppLogger.error("Failed to load store from disk: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Missed Trades & Progress Management
    
    public static var defaultProgressRules: [ProgressRule] {
        [
            ProgressRule(title: "Check high-impact economic news", stage: "Before trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Identify H1-H4 Key Levels & Liquidity", stage: "Before trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Always set Stop Loss before order fill", stage: "During trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Do not move SL or hold beyond planned R:R", stage: "During trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Log emotional notes & post-trade review", stage: "After trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Save chart screenshots and score Playbook", stage: "After trading", weekdaysJson: "[1,2,3,4,5]")
        ]
    }
    
    public func saveMissedTrade(_ trade: MissedTrade) {
        if let idx = missedTrades.firstIndex(where: { $0.id == trade.id }) {
            missedTrades[idx] = trade
        } else {
            missedTrades.append(trade)
        }
        saveToDisk()
    }
    
    public func deleteMissedTrade(id: String) {
        missedTrades.removeAll(where: { $0.id == id })
        saveToDisk()
    }
    
    public func toggleArchiveMissedTrade(id: String) {
        if let idx = missedTrades.firstIndex(where: { $0.id == id }) {
            if missedTrades[idx].archivedAt == nil {
                missedTrades[idx].archivedAt = JournalIds.nowIso()
            } else {
                missedTrades[idx].archivedAt = nil
            }
            saveToDisk()
        }
    }
    
    public func saveProgressRule(_ rule: ProgressRule) {
        if let idx = progressRules.firstIndex(where: { $0.id == rule.id }) {
            progressRules[idx] = rule
        } else {
            progressRules.append(rule)
        }
        saveToDisk()
    }
    
    public func deleteProgressRule(id: String) {
        progressRules.removeAll(where: { $0.id == id })
        progressChecks.removeAll(where: { $0.ruleId == id })
        saveToDisk()
        Task {
            try? await SupabaseService.shared.deleteProgressRule(id: id)
        }
    }
    
    public func toggleProgressCheck(ruleId: String, date: String) {
        if let idx = progressChecks.firstIndex(where: { $0.ruleId == ruleId && $0.date == date }) {
            progressChecks[idx].done.toggle()
        } else {
            progressChecks.append(ProgressCheck(ruleId: ruleId, date: date, done: true))
        }
        saveToDisk()
    }
    
    public func progressScore(for date: String) -> (completed: Int, total: Int, percent: Double) {
        let activeRules = progressRules.filter { $0.archivedAt == nil }
        guard !activeRules.isEmpty else { return (0, 0, 0) }
        let completed = activeRules.filter { r in
            progressChecks.contains(where: { $0.ruleId == r.id && $0.date == date && $0.done })
        }.count
        let pct = Double(completed) / Double(activeRules.count)
        return (completed, activeRules.count, pct)
    }
    
    private func createInitialDefaultAccount() {
        let defaultAcc = Account(
            id: "default-acc",
            name: "Trading Account",
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
        playbookId: String? = nil,
        ruleAssessments: [String: Bool] = [:]
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
            
            if let pbId = playbookId, !ruleAssessments.isEmpty {
                let tradeKey = trades[idx].key
                for (rule, followed) in ruleAssessments {
                    let assessment = PlaybookRuleAssessment(
                        tradeKey: tradeKey,
                        playbookId: pbId,
                        rule: rule,
                        followed: followed
                    )
                    if let aIdx = playbookAssessments.firstIndex(where: { $0.id == assessment.id }) {
                        playbookAssessments[aIdx] = assessment
                    } else {
                        playbookAssessments.append(assessment)
                    }
                }
            }
        }
        
        saveToDisk()
        AppLogger.info("Added manual trade for \(cleanSymbol). Total trades now: \(trades.count)")
        Task {
            try? await SupabaseService.shared.upsertExecutions(newExecutions)
            if let t = self.trades.first(where: { $0.accountId == accountId && $0.symbol == cleanSymbol && abs($0.openedAt.timeIntervalSince(openedAt)) < 2 }) {
                try? await SupabaseService.shared.upsertTrades([t])
            }
        }
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
        Task {
            try? await SupabaseService.shared.deleteTrade(key: key)
        }
    }

    public func updateManualTrade(
        key: String,
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
        guard let trade = trades.first(where: { $0.key == key }) else { return }
        let accId = trade.accountId
        
        // Remove old executions
        let oldIds = Set(trade.executionIds)
        let oldFills = executions.filter { oldIds.contains($0.id) }
        for fill in oldFills {
            executionHashes.remove(fill.contentHash)
        }
        executions.removeAll { oldIds.contains($0.id) }
        
        // Build new executions
        let cleanSymbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        let entrySide: ExecutionSide = (direction == .long) ? .buy : .sell
        let halfFee = (exitPrice != nil) ? (fee / 2) : fee
        
        let entryFill = Execution(
            accountId: accId,
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
                accountId: accId,
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
        
        rebuildAccount(accountId: accId)
        
        if let idx = trades.firstIndex(where: { t in
            t.accountId == accId &&
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
        Task {
            try? await SupabaseService.shared.deleteTrade(key: key)
            try? await SupabaseService.shared.upsertExecutions(newExecutions)
            if let t = self.trades.first(where: { $0.accountId == accId && $0.symbol == cleanSymbol && abs($0.openedAt.timeIntervalSince(openedAt)) < 2 }) {
                try? await SupabaseService.shared.upsertTrades([t])
            }
        }
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

    public func updatePlaybook(id: String, title: String, description: String, rules: [String]) {
        guard let idx = playbooks.firstIndex(where: { $0.id == id }) else { return }
        playbooks[idx].name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].rules = rules
        saveToDisk()
        let updated = playbooks[idx]
        Task {
            try? await SupabaseService.shared.upsertPlaybooks([updated])
        }
    }
    
    public func deletePlaybook(id: String) {
        playbooks.removeAll { $0.id == id }
        playbookAssessments.removeAll { $0.playbookId == id }
        for i in 0..<trades.count {
            if trades[i].playbookId == id {
                trades[i].playbookId = nil
            }
        }
        deletedPlaybookIds.insert(id)
        saveToDisk()
        Task {
            do {
                try await SupabaseService.shared.deletePlaybook(id: id)
            } catch {
                AppLogger.warning("Supabase deletePlaybook notice: \(error.localizedDescription)")
            }
        }
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
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && (note.rating == nil || note.rating == 0) {
            deleteCalendarNote(for: note.date)
            return
        }
        calendarNotes[note.date] = note
        journalDays[note.date] = note.content
        saveToDisk()
        Task {
            try? await SupabaseService.shared.upsertJournalDay(note)
        }
    }
    
    public func deleteCalendarNote(for date: String) {
        calendarNotes.removeValue(forKey: date)
        journalDays.removeValue(forKey: date)
        saveToDisk()
        Task {
            try? await SupabaseService.shared.deleteJournalDay(date: date)
        }
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
    
    // MARK: - Demo Data Loading
    
    /// Seeds a "Demo data" account with plausible day trading executions so a fresh install has rich data.
    /// Ported 1:1 from `source-repo/apps/web/src/server/demo.ts`
    public func loadDemoData() {
        if let existing = accounts.first(where: { $0.broker == "demo" }) {
            if existing.archivedAt != nil {
                archiveAccount(id: existing.id, archived: false)
            }
            selectedAccountId = existing.id
            return
        }
        
        let demoAccountId = JournalIds.newId()
        let demoAccount = Account(
            id: demoAccountId,
            name: "Demo data",
            broker: "demo",
            kind: .import,
            currency: "USD",
            initialBalance: 25000,
            profitCalcMethod: .fifo,
            autoSync: false,
            visibleInJournal: true
        )
        accounts.append(demoAccount)
        
        var fills: [Execution] = []
        var s: Double = 42
        let rnd: () -> Double = {
            s = Double((Int64(s * 1103515245) + 12345) % 2147483648)
            return s / 2147483648.0
        }
        
        struct Spec {
            let symbol: String
            let price: Double
            let qtyMin: Double
            let qtyMax: Double
        }
        let symbols: [Spec] = [
            Spec(symbol: "NVDA", price: 128, qtyMin: 50, qtyMax: 150),
            Spec(symbol: "TSLA", price: 242, qtyMin: 30, qtyMax: 100),
            Spec(symbol: "AAPL", price: 226, qtyMin: 50, qtyMax: 200),
            Spec(symbol: "AMD", price: 158, qtyMin: 80, qtyMax: 250),
            Spec(symbol: "META", price: 512, qtyMin: 20, qtyMax: 60),
            Spec(symbol: "SPY", price: 556, qtyMin: 40, qtyMax: 120)
        ]
        
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        
        func atDate(day: Date, minute: Int) -> Date {
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 13
            comps.minute = 30 + minute
            comps.second = Int(rnd() * 60)
            comps.timeZone = TimeZone(secondsFromGMT: 0)
            return cal.date(from: comps) ?? day
        }
        
        for back in stride(from: 90, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let dow = cal.component(.weekday, from: day)
            if dow == 1 || dow == 7 { continue }
            if rnd() < 0.28 { continue }
            
            let tradesToday = 1 + Int(rnd() * 4)
            var minute = 5 + Int(rnd() * 40)
            
            for _ in 0..<tradesToday {
                let spec = symbols[Int(rnd() * Double(symbols.count)) % symbols.count]
                let isLong = rnd() < 0.72
                let quantity = round(spec.qtyMin + rnd() * (spec.qtyMax - spec.qtyMin))
                let entry = spec.price * (0.97 + rnd() * 0.06)
                let isWin = rnd() < 0.56
                let magnitude = isWin ? (0.004 + rnd() * 0.014) : (0.003 + rnd() * 0.008)
                let exit = entry + (isWin ? 1.0 : -1.0) * (isLong ? 1.0 : -1.0) * magnitude * entry
                let hold = 4 + Int(rnd() * 55)
                let entrySide: ExecutionSide = isLong ? .buy : .sell
                let exitSide: ExecutionSide = isLong ? .sell : .buy
                let entryTime = atDate(day: day, minute: minute)
                let exitTime = atDate(day: day, minute: minute + hold)
                
                fills.append(Execution(
                    accountId: demoAccountId,
                    symbol: spec.symbol,
                    side: entrySide,
                    quantity: Decimal(quantity),
                    price: Decimal(string: String(format: "%.2f", entry)) ?? Decimal(entry),
                    fee: 1,
                    executedAt: entryTime,
                    assetClass: "equity",
                    source: "import"
                ))
                
                if rnd() < 0.3 && quantity >= 60 {
                    let half = round(quantity / 2.0)
                    let mid = entry + (exit - entry) * (0.4 + rnd() * 0.3)
                    let midTime = atDate(day: day, minute: minute + hold / 2)
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(half),
                        price: Decimal(string: String(format: "%.2f", mid)) ?? Decimal(mid),
                        fee: 1,
                        executedAt: midTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(quantity - half),
                        price: Decimal(string: String(format: "%.2f", exit)) ?? Decimal(exit),
                        fee: 1,
                        executedAt: exitTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                } else {
                    fills.append(Execution(
                        accountId: demoAccountId,
                        symbol: spec.symbol,
                        side: exitSide,
                        quantity: Decimal(quantity),
                        price: Decimal(string: String(format: "%.2f", exit)) ?? Decimal(exit),
                        fee: 1,
                        executedAt: exitTime,
                        assetClass: "equity",
                        source: "import"
                    ))
                }
                minute += hold + 10 + Int(rnd() * 50)
                if minute > 340 { break }
            }
        }
        
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now) {
            fills.append(Execution(
                accountId: demoAccountId,
                symbol: "NVDA",
                side: .buy,
                quantity: 120,
                price: 131.42,
                fee: 1,
                executedAt: atDate(day: yesterday, minute: 44),
                assetClass: "equity",
                source: "import"
            ))
            fills.append(Execution(
                accountId: demoAccountId,
                symbol: "SPY",
                side: .sell,
                quantity: 80,
                price: 561.18,
                fee: 1,
                executedAt: atDate(day: yesterday, minute: 92),
                assetClass: "equity",
                source: "import"
            ))
        }
        
        importExecutions(accountId: demoAccountId, newExecutions: fills)
        selectedAccountId = demoAccountId
        saveToDisk()
        AppLogger.info("Loaded demo data: \(fills.count) executions for demo account \(demoAccountId)")
    }
    
    /// Exports all reconstructed trades into an RFC 4180 CSV table
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

