import Foundation

#if canImport(UIKit)
import UIKit
#endif

extension TradeDataStore {
    // MARK: - Local Persistence
    
    internal struct PersistedStore: Codable, Sendable {
        let schemaVersion: Int?
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
    
    /// Snapshots in-memory state into an immutable value-type instantly on the main actor (< 1ms).
    private func snapshotStore() -> PersistedStore {
        PersistedStore(
            schemaVersion: 1,
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
    }
    
    /// High-performance asynchronous persistence.
    /// NEVER blocks the main runloop with synchronous JSON serialization or disk writes.
    public func saveToDisk(immediate: Bool = false) {
        guard isLoaded else {
            AppLogger.warning("Skipping saveToDisk because store is not yet loaded.")
            return
        }
        
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        
        if immediate {
            performSaveToDiskAsync(isBackgroundTrigger: false)
        } else {
            saveDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, let self = self else { return }
                self.performSaveToDiskAsync(isBackgroundTrigger: false)
            }
        }
    }
    
    /// Snapshots in-memory state and offloads JSON encoding and atomic disk I/O to a background thread.
    /// Uses iOS background task protection when triggered during app suspension.
    public func performSaveToDiskAsync(isBackgroundTrigger: Bool = false) {
        guard isLoaded else { return }
        let store = snapshotStore()
        let primaryUrl = persistenceUrl
        let backupUrl = backupPersistenceUrl
        
        #if os(iOS)
        var backgroundTaskId = UIBackgroundTaskIdentifier.invalid
        if isBackgroundTrigger || UIApplication.shared.applicationState == .background {
            backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "SaveTradeJournalStore") {
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
            }
        }
        #endif
        
        Task.detached(priority: .utility) {
            Self.writeStoreToDisk(store, primaryUrl: primaryUrl, backupUrl: backupUrl)
            #if os(iOS)
            if backgroundTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskId)
            }
            #endif
        }
    }
    
    nonisolated private static func writeStoreToDisk(_ store: PersistedStore, primaryUrl: URL, backupUrl: URL) {
        do {
            let data = try JSONEncoder().encode(store)
            
            // Maintain a backup copy of previous valid save if it exists
            if FileManager.default.fileExists(atPath: primaryUrl.path) {
                try? FileManager.default.removeItem(at: backupUrl)
                try? FileManager.default.copyItem(at: primaryUrl, to: backupUrl)
            }
            
            try data.write(to: primaryUrl, options: .atomic)
        } catch {
            AppLogger.error("Failed to save store to disk: \(error.localizedDescription)")
        }
    }
    
    nonisolated internal static func decodeStoreFromDisk(primaryUrl: URL, backupUrl: URL) -> (store: PersistedStore, hashes: Set<String>)? {
        // 1. Try decoding primary file
        if FileManager.default.fileExists(atPath: primaryUrl.path) {
            do {
                let data = try Data(contentsOf: primaryUrl)
                let store = try JSONDecoder().decode(PersistedStore.self, from: data)
                let hashes = Set(store.executions.map { $0.contentHash })
                return (store, hashes)
            } catch {
                AppLogger.error("Failed to decode primary store at \(primaryUrl.path): \(error.localizedDescription)")
                
                // Quarantine corrupted file to avoid permanent loss
                let corruptPath = primaryUrl.deletingLastPathComponent().appendingPathComponent("trade_journal_corrupt_\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: primaryUrl, to: corruptPath)
                AppLogger.warning("Quarantined corrupted primary store to \(corruptPath.lastPathComponent)")
            }
        }
        
        // 2. Try decoding backup file (.bak)
        if FileManager.default.fileExists(atPath: backupUrl.path) {
            do {
                let data = try Data(contentsOf: backupUrl)
                let store = try JSONDecoder().decode(PersistedStore.self, from: data)
                let hashes = Set(store.executions.map { $0.contentHash })
                AppLogger.info("Successfully recovered store from backup file (.bak).")
                return (store, hashes)
            } catch {
                AppLogger.error("Backup file also failed to decode: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    /// Asynchronously hydrates the store from disk on a background thread without freezing the main runloop
    public func loadFromDiskAsync() {
        guard !isLoaded, hydrationTask == nil else { return }
        
        let url = persistenceUrl
        let bakUrl = backupPersistenceUrl
        hydrationTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            let decoded = await Task.detached(priority: .userInitiated) { () -> (store: PersistedStore, hashes: Set<String>)? in
                Self.decodeStoreFromDisk(primaryUrl: url, backupUrl: bakUrl)
            }.value
            
            if let result = decoded {
                self.applyLoadedStore(result.store, executionHashes: result.hashes)
            }
            self.isLoaded = true
            self.postHydrationSetup()
        }
    }
    
    public func loadFromDisk() {
        loadFromDiskAsync()
    }
    
    public func loadFromDiskSync() {
        if let result = Self.decodeStoreFromDisk(primaryUrl: persistenceUrl, backupUrl: backupPersistenceUrl) {
            applyLoadedStore(result.store, executionHashes: result.hashes)
        }
        isLoaded = true
        postHydrationSetup()
    }
    
    private func applyLoadedStore(_ store: PersistedStore, executionHashes: Set<String>) {
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
        self.executionHashes = executionHashes
        invalidatePerformanceCaches()
        
        AppLogger.info("Loaded \(store.accounts.count) accounts, \(store.executions.count) executions, \(self.notebookNotes.count) notes, \(self.propAccounts.count) prop accounts, \(self.attachments.count) attachments from persistent disk.")
    }
    
    private func postHydrationSetup() {
        if accounts.isEmpty {
            createInitialDefaultAccount()
        } else if accounts.contains(where: { $0.id != "default-acc" }) {
            accounts.removeAll(where: { $0.id == "default-acc" })
        }
        
        // Ensure discovered cTrader accounts are registered in TradeDataStore if configured
        if CTraderService.shared.isConfigured && !CTraderService.shared.discoveredAccounts.isEmpty {
            CTraderService.shared.registerDiscoveredAccounts(into: self)
        }
        
        if folders.isEmpty {
            folders = NotebookEngine.defaultSystemFolders
        }
        if selectedAccountId == "default-acc" || selectedAccountId == "all" || !accounts.contains(where: { $0.id == selectedAccountId || TradeDataStore.isSameAccountId($0.id, selectedAccountId) }) {
            selectedAccountId = mostRecentActiveAccount?.id ?? visibleAccounts.first?.id ?? accounts.first?.id ?? "default-acc"
        }
        
        // Rebuild trades for any accounts that have imported executions but no reconstructed trades
        let accountsWithTrades = Set(trades.map { $0.accountId })
        let accountsWithExecutions = Set(executions.map { $0.accountId })
        for acc in accounts {
            if !accountsWithTrades.contains(acc.id) && accountsWithExecutions.contains(acc.id) {
                rebuildAccount(accountId: acc.id)
            }
        }
        
        deduplicateAndCleanAccounts()
        refreshActiveAccountCache()
        if selectedAccountId == "default-acc" || selectedAccountId == "all" || selectedAccountId.isEmpty || !accounts.contains(where: { $0.id == selectedAccountId || TradeDataStore.isSameAccountId($0.id, selectedAccountId) }) {
            selectedAccountId = mostRecentActiveAccount?.id ?? visibleAccounts.first?.id ?? accounts.first?.id ?? "default-acc"
        }
        invalidatePerformanceCaches()
    }
}