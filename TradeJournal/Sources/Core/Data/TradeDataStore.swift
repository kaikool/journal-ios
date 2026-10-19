import SwiftUI
import Combine

/// Central reactive data store managing accounts, trades, executions, notes, playbooks, and prop accounts.
/// Methods are cleanly partitioned into domain extensions:
/// - `TradeDataStore+Accounts.swift`
/// - `TradeDataStore+Trades.swift`
/// - `TradeDataStore+PropFirm.swift`
/// - `TradeDataStore+Notebook.swift`
/// - `TradeDataStore+Playbooks.swift`
/// - `TradeDataStore+Sync.swift`
@MainActor
public final class TradeDataStore: ObservableObject {
    public static let shared = TradeDataStore()
    
    @Published public var accounts: [Account] = [] {
        didSet { invalidatePerformanceCaches() }
    }
    @Published public var executions: [Execution] = [] {
        didSet { invalidatePerformanceCaches() }
    }
    @Published public var trades: [Trade] = [] {
        didSet { invalidatePerformanceCaches() }
    }
    @Published public var selectedAccountId: String = "default-acc" {
        didSet { invalidatePerformanceCaches() }
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
    @Published public private(set) var isLoaded: Bool = false
    
    internal var executionHashes: Set<String> = []
    private var hydrationTask: Task<Void, Never>? = nil
    private var saveDebounceTask: Task<Void, Never>? = nil
    
    // MARK: - Performance Caching
    internal var _cachedFilteredTrades: [Trade]? = nil
    internal var _cachedFilteredTradesAccountId: String? = nil
    internal var _cachedVisibleAccounts: [Account]? = nil
    internal var _cachedActiveAccounts: [Account]? = nil
    internal var _cachedMostRecentActiveAccount: Account? = nil
    internal var _cachedMostRecentActiveAccountValid: Bool = false
    internal var activePropAccountIdsCache: Set<String>? = nil
    internal var inactivePropAccountIdsCache: Set<String>? = nil
    
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
    
    internal var persistenceUrl: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("trade_journal_store_v1.json")
    }
    
    internal var backupPersistenceUrl: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("trade_journal_store_v1.json.bak")
    }
    
    public init(loadSynchronously: Bool = true) {
        self.folders = NotebookEngine.defaultSystemFolders
        if loadSynchronously {
            loadFromDiskSync()
        } else {
            loadFromDiskAsync()
        }
    }
    
    /// Asynchronously awaits completion of the background disk hydration
    public func ensureHydrated() async {
        if isLoaded { return }
        if let task = hydrationTask {
            _ = await task.value
        } else {
            loadFromDiskAsync()
            _ = await hydrationTask?.value
        }
    }
    
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
    
    public func saveToDisk(immediate: Bool = false) {
        guard isLoaded else {
            AppLogger.warning("Skipping saveToDisk because store is not yet loaded.")
            return
        }
        
        if immediate {
            saveDebounceTask?.cancel()
            saveDebounceTask = nil
            performSaveToDisk()
        } else {
            saveDebounceTask?.cancel()
            saveDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, let self = self else { return }
                self.performSaveToDisk()
            }
        }
    }
    
    internal func performSaveToDisk() {
        guard isLoaded else { return }
        let store = PersistedStore(
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
        do {
            let data = try JSONEncoder().encode(store)
            
            // Maintain a backup copy of previous valid save if it exists
            if FileManager.default.fileExists(atPath: persistenceUrl.path) {
                try? FileManager.default.removeItem(at: backupPersistenceUrl)
                try? FileManager.default.copyItem(at: persistenceUrl, to: backupPersistenceUrl)
            }
            
            try data.write(to: persistenceUrl, options: .atomic)
        } catch {
            AppLogger.error("Failed to save store to disk: \(error.localizedDescription)")
        }
    }
    
    internal static func decodeStoreFromDisk(primaryUrl: URL, backupUrl: URL) -> (store: PersistedStore, hashes: Set<String>)? {
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
        loadFromDiskSync()
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
        if folders.isEmpty {
            folders = NotebookEngine.defaultSystemFolders
        }
        if selectedAccountId == "default-acc" || (!accounts.contains(where: { $0.id == selectedAccountId }) && selectedAccountId != "all") {
            selectedAccountId = mostRecentActiveAccount?.id ?? "all"
        }
        refreshActiveAccountCache()
        invalidatePerformanceCaches()
    }
}
