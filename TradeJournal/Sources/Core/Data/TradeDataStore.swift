import Foundation
import Combine

/// Central reactive data store managing accounts, trades, executions, notes, playbooks, and prop accounts.
/// Acts as a unified facade coordinating dedicated domain stores:
/// - `TradesDomainStore` (trades, executions, trade metrics)
/// - `AccountsDomainStore` (accounts, active account selection, caching)
/// - `PropFirmDomainStore` (prop evaluations, funded accounts, receipts)
/// - `NotebookDomainStore` (folders, notes, calendar days)
/// - `PlaybooksDomainStore` (playbooks, rules, assessments)
@MainActor
public final class TradeDataStore: ObservableObject {
    public static let shared = TradeDataStore()
    
    // MARK: - Domain Sub-Stores
    public let tradesStore = TradesDomainStore()
    public let accountsStore = AccountsDomainStore()
    public let propFirmStore = PropFirmDomainStore()
    public let notebookStore = NotebookDomainStore()
    public let playbooksStore = PlaybooksDomainStore()
    
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
    @Published public var selectedTimeRange: JournalTimeRange = .all {
        didSet { invalidatePerformanceCaches() }
    }
    public private(set) var cacheVersion: Int = 0
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
    public var deletedProgressRuleIds: Set<String> = []
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
    @Published public var lastSyncDate: Date? = nil
    @Published public internal(set) var isLoaded: Bool = false
    
    internal var executionHashes: Set<String> = []
    internal var hydrationTask: Task<Void, Never>? = nil
    internal var saveDebounceTask: Task<Void, Never>? = nil
    
    // MARK: - Performance Caching
    internal var _cachedFilteredTrades: [Trade]? = nil
    internal var _cachedFilteredTradesAccountId: String? = nil
    internal var _cachedVisibleAccounts: [Account]? = nil
    internal var _cachedVisibleAccountIds: Set<String>? = nil
    internal var _cachedActiveAccounts: [Account]? = nil
    internal var _cachedMostRecentActiveAccount: Account? = nil
    internal var _cachedMostRecentActiveAccountValid: Bool = false
    internal var activePropAccountIdsCache: Set<String>? = nil
    internal var inactivePropAccountIdsCache: Set<String>? = nil
    
    public func invalidatePerformanceCaches() {
        _cachedFilteredTrades = nil
        _cachedFilteredTradesAccountId = nil
        _cachedVisibleAccounts = nil
        _cachedVisibleAccountIds = nil
        _cachedActiveAccounts = nil
        _cachedMostRecentActiveAccount = nil
        _cachedMostRecentActiveAccountValid = false
        activePropAccountIdsCache = nil
        inactivePropAccountIdsCache = nil
        cacheVersion &+= 1
        
        // Synchronize domain stores
        tradesStore.trades = trades
        tradesStore.executions = executions
        tradesStore.missedTrades = missedTrades
        tradesStore.attachments = attachments
        accountsStore.accounts = accounts
        accountsStore.selectedAccountId = selectedAccountId
        accountsStore.selectedTimeRange = selectedTimeRange
        propFirmStore.propAccounts = propAccounts
        propFirmStore.propEntries = propEntries
        propFirmStore.propReceipts = propReceipts
        propFirmStore.propAudits = propAudits
        notebookStore.folders = folders
        notebookStore.notebookNotes = notebookNotes
        notebookStore.journalDays = journalDays
        notebookStore.calendarNotes = calendarNotes
        playbooksStore.playbooks = playbooks
        playbooksStore.playbookAssessments = playbookAssessments
        playbooksStore.progressRules = progressRules
        playbooksStore.progressChecks = progressChecks
        
        // Standard 27: Evaluate Discipline (Tilt) and Schedule Daily Journal Review
        AppNotificationCoordinator.shared.evaluateTiltAndRevengeTrading(trades: trades)
        AppNotificationCoordinator.shared.scheduleDailyJournalReview(
            trades: trades,
            timeZone: AppEnvironment.shared.currentTimeZone
        )
    }
    
    internal var persistenceUrl: URL {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return baseDir.appendingPathComponent("trade_journal_store_v1.json")
    }
    
    internal var backupPersistenceUrl: URL {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return baseDir.appendingPathComponent("trade_journal_store_v1.json.bak")
    }
    
    /// Creates a store instance.
    /// - Parameters:
    ///   - loadFromDisk: When false the store starts empty and never touches the persistence
    ///     layer. Used by tests that need an isolated store.
    ///   - loadSynchronously: When true the persisted state is loaded synchronously instead of
    ///     hydrating in the background.
    public init(loadFromDisk: Bool = true, loadSynchronously: Bool = false) {
        self.folders = NotebookEngine.defaultSystemFolders
        if !loadFromDisk {
            isLoaded = true
        } else if loadSynchronously {
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
    
}