import Foundation
import SwiftUI
import Combine

/// Central orchestrator coordinating all registered broker, prop firm, and cloud backup providers.
@MainActor
public final class SyncManager: ObservableObject {
    public static let shared = SyncManager()
    
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var currentProgress: String? = nil
    @Published public private(set) var lastSyncResults: [String: SyncResult] = [:]
    @Published public private(set) var lastSyncDate: Date? = nil
    @Published public private(set) var isCancelledByUser: Bool = false
    
    @Published public var savedQuickSyncOptions: SyncOptions {
        didSet {
            saveQuickSyncOptions()
        }
    }
    
    public private(set) var providers: [any SyncProvider] = []
    
    private init() {
        // Load saved quick sync options from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "journal_quick_sync_options_v1"),
           var decoded = try? JSONDecoder().decode(SyncOptions.self, from: data) {
            // Ensure Exness is enabled if configured
            if !decoded.enabledProviderIds.contains("exness") {
                decoded.enabledProviderIds.insert("exness")
            }
            self.savedQuickSyncOptions = decoded
        } else {
            self.savedQuickSyncOptions = .default
        }
        
        // Register core built-in providers
        register(provider: ExnessSyncProvider())
        register(provider: CTraderSyncProvider())
        register(provider: The5ersSyncProvider())
        register(provider: SupabaseSyncProvider())
    }
    
    public func register(provider: any SyncProvider) {
        if !providers.contains(where: { $0.id == provider.id }) {
            providers.append(provider)
        }
    }
    
    public func provider(for id: String) -> (any SyncProvider)? {
        providers.first(where: { $0.id == id })
    }
    
    public var configuredProviders: [any SyncProvider] {
        providers.filter { $0.isConfigured }
    }
    
    private func saveQuickSyncOptions() {
        if let encoded = try? JSONEncoder().encode(savedQuickSyncOptions) {
            UserDefaults.standard.set(encoded, forKey: "journal_quick_sync_options_v1")
        }
    }
    
    private var backgroundBackupTask: Task<Void, Never>? = nil
    private var activeSyncTask: Task<[SyncResult], Never>? = nil
    private var lastAutoSyncDate: Date? = nil
    private var autoSyncTimer: AnyCancellable? = nil
    
    /// Starts periodic gentle background auto-sync every 5 minutes while the app is active
    public func startPeriodicAutoSync() {
        stopPeriodicAutoSync()
        autoSyncTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.autoSyncIfNeeded(cooldownSeconds: 240, delaySeconds: 0)
            }
    }
    
    /// Stops periodic background timer when app enters background
    public func stopPeriodicAutoSync() {
        autoSyncTimer?.cancel()
        autoSyncTimer = nil
    }
    
    /// Automatically synchronizes data in the background without blocking the UI.
    /// Runs gently on app launch, foreground resume, and periodically every 5 minutes.
    public func autoSyncIfNeeded(cooldownSeconds: Double = 120, delaySeconds: Double = 3, force: Bool = false) {
        guard !isSyncing else { return }
        
        let now = Date()
        if !force, let last = lastAutoSyncDate, now.timeIntervalSince(last) < cooldownSeconds {
            return
        }
        lastAutoSyncDate = now
        
        Task.detached(priority: .background) { [weak self] in
            // Wait for UI to finish loading completely and be 100% interactive
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            
            var brokerUpdatesCount = 0
            
            // 1. Auto-sync Exness if configured
            if ExnessService.shared.isConfigured {
                let count = (try? await ExnessService.shared.syncTrades()) ?? 0
                if count > 0 { brokerUpdatesCount += count }
            }
            
            // 2. Auto-sync cTrader if configured
            if CTraderService.shared.isConfigured {
                let res = try? await CTraderService.shared.syncWithTradeStore(dataStore: TradeDataStore.shared)
                let cCount = (res?.dealsImported ?? 0) + (res?.tradesRebuilt ?? 0)
                if cCount > 0 { brokerUpdatesCount += cCount }
            }
            
            // 3. Auto-sync The5ers if configured
            if The5ersService.shared.isConfigured {
                let count = (try? await The5ersService.shared.syncWithTradeStore(dataStore: TradeDataStore.shared)) ?? 0
                if count > 0 { brokerUpdatesCount += count }
            }
            
            // If any broker brought fresh trades or balance updates, refresh UI and schedule cloud backup
            if brokerUpdatesCount > 0 {
                await MainActor.run {
                    TradeDataStore.shared.invalidatePerformanceCaches()
                    TradeDataStore.shared.saveToDisk(immediate: true)
                    TradeDataStore.shared.objectWillChange.send()
                }
                self?.scheduleBackgroundCloudBackup(delaySeconds: 5)
            }
        }
    }
    
    /// Cancels any in-progress sync operation across all registered providers
    @MainActor
    public func cancelSync() {
        self.isCancelledByUser = true
        activeSyncTask?.cancel()
        activeSyncTask = nil
        The5ersService.shared.cancelSync()
        CTraderService.shared.cancelSync()
        self.isSyncing = false
        self.currentProgress = "Synchronization cancelled."
        TradeDataStore.shared.isSyncing = false
        TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
        TradeDataStore.shared.lastSyncError = nil
    }
    
    /// Schedules an asynchronous, debounced cloud backup to Supabase.
    /// Runs quietly in the background without blocking the UI or pull-to-refresh spinner.
    public func scheduleBackgroundCloudBackup(delaySeconds: Double = 15) {
        guard let supabaseProvider = provider(for: "supabase"), supabaseProvider.isConfigured else {
            return
        }
        backgroundBackupTask?.cancel()
        backgroundBackupTask = Task.detached(priority: .background) {
            do {
                try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            AppLogger.info("Initiating debounced background Supabase backup...")
            await TradeDataStore.shared.syncWithSupabase(isBackground: true)
            AppLogger.info("Debounced background Supabase backup completed.")
        }
    }
    
    /// Executes the saved Quick Sync strategy (typically last 30 days for active accounts).
    /// Used for foreground swipe-to-refresh: strictly fetches fresh broker data and triggers
    /// background cloud backup if updates are found.
    @discardableResult
    public func performQuickSync() async -> [SyncResult] {
        var options = savedQuickSyncOptions
        
        // If broker providers are configured, sync them. If only Supabase is configured, enable Cloud sync so pull-to-refresh syncs data.
        let activeBrokers = providers.filter { $0.id != "supabase" && options.enabledProviderIds.contains($0.id) && $0.isConfigured }
        if activeBrokers.isEmpty, let supabase = provider(for: "supabase"), supabase.isConfigured {
            options.backupToCloud = true
        } else {
            options.backupToCloud = false
        }
        
        let results = await performSync(with: options)
        let hasSuccess = results.contains { $0.success }
        if hasSuccess && !options.backupToCloud {
            scheduleBackgroundCloudBackup(delaySeconds: 5)
        }
        return results
    }
    
    /// Executes a synchronization run with specified options.
    /// Uses an unstructured detached task so that SwiftUI view redraws or gesture releases during
    /// pull-to-refresh do NOT cancel the in-flight network synchronization.
    @discardableResult
    public func performSync(with options: SyncOptions) async -> [SyncResult] {
        // If already syncing, wait for existing active task
        if let existing = activeSyncTask {
            return await existing.value
        }
        
        self.isCancelledByUser = false
        
        let task = Task.detached(priority: .userInitiated) { @MainActor [weak self] () -> [SyncResult] in
            guard let self = self else { return [] }
            return await self.executeSyncPipeline(options: options)
        }
        self.activeSyncTask = task
        
        let results = await task.value
        self.activeSyncTask = nil
        return results
    }
    
    @MainActor
    private func executeSyncPipeline(options: SyncOptions) async -> [SyncResult] {
        self.isSyncing = true
        self.isCancelledByUser = false
        self.currentProgress = "Initializing synchronization..."
        TradeDataStore.shared.isSyncing = true
        TradeDataStore.shared.lastSyncError = nil
        TradeDataStore.shared.lastSyncSummary = self.currentProgress
        
        defer {
            self.isSyncing = false
            self.currentProgress = nil
            TradeDataStore.shared.isSyncing = false
        }
        
        var results: [SyncResult] = []
        
        // Check if any connections configured at all
        let totalConfigured = configuredProviders.count
        if totalConfigured == 0 {
            let msg = "No connections configured. Configure in Settings -> Connections."
            TradeDataStore.shared.lastSyncSummary = msg
            TradeDataStore.shared.lastSyncError = nil
            return results
        }
        
        // 1. Separate broker/exchange providers from cloud storage providers
        let brokerProviders = providers.filter {
            $0.id != "supabase" && options.enabledProviderIds.contains($0.id) && $0.isConfigured
        }
        
        // 2. Synchronize market data sources sequentially
        for provider in brokerProviders {
            if self.isCancelledByUser || !self.isSyncing {
                TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
                TradeDataStore.shared.lastSyncError = nil
                return results
            }
            
            self.currentProgress = "Syncing with \(provider.displayName)..."
            TradeDataStore.shared.lastSyncSummary = self.currentProgress
            
            do {
                let res = try await provider.performSync(options: options) { [weak self] update in
                    Task { @MainActor in
                        guard let self = self, !self.isCancelledByUser else { return }
                        self.currentProgress = "\(update.providerName): \(update.message)"
                        TradeDataStore.shared.lastSyncSummary = self.currentProgress
                    }
                }
                results.append(res)
                lastSyncResults[provider.id] = res
            } catch {
                if self.isCancelledByUser || !self.isSyncing {
                    AppLogger.info("Sync cancelled for \(provider.displayName)")
                    TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
                    TradeDataStore.shared.lastSyncError = nil
                    return results
                }
                let errResult = SyncResult(
                    providerId: provider.id,
                    providerName: provider.displayName,
                    success: false,
                    message: error.localizedDescription,
                    error: error.localizedDescription
                )
                results.append(errResult)
                lastSyncResults[provider.id] = errResult
            }
        }
        
        if self.isCancelledByUser || !self.isSyncing {
            TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
            TradeDataStore.shared.lastSyncError = nil
            return results
        }
        
        // 3. Persist local store
        TradeDataStore.shared.saveToDisk()
        
        // 4. If Cloud Backup is requested and Supabase provider is configured, backup fresh data
        if options.backupToCloud, let supabaseProvider = provider(for: "supabase"), supabaseProvider.isConfigured {
            if self.isCancelledByUser || !self.isSyncing {
                TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
                TradeDataStore.shared.lastSyncError = nil
                return results
            }
            
            self.currentProgress = "Backing up to Supabase Cloud Database..."
            TradeDataStore.shared.lastSyncSummary = self.currentProgress
            
            do {
                let cloudRes = try await supabaseProvider.performSync(options: options) { [weak self] update in
                    Task { @MainActor in
                        guard let self = self, !self.isCancelledByUser else { return }
                        self.currentProgress = update.message
                        TradeDataStore.shared.lastSyncSummary = self.currentProgress
                    }
                }
                results.append(cloudRes)
                lastSyncResults["supabase"] = cloudRes
            } catch {
                if self.isCancelledByUser || !self.isSyncing {
                    AppLogger.info("Supabase sync cancelled.")
                    TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
                    TradeDataStore.shared.lastSyncError = nil
                    return results
                }
                let cloudErr = SyncResult(
                    providerId: "supabase",
                    providerName: "Supabase Cloud",
                    success: false,
                    message: "Supabase backup failed: \(error.localizedDescription)",
                    error: error.localizedDescription
                )
                results.append(cloudErr)
                lastSyncResults["supabase"] = cloudErr
            }
        }
        
        let now = Date()
        self.lastSyncDate = now
        
        if self.isCancelledByUser || !self.isSyncing {
            TradeDataStore.shared.lastSyncSummary = "Synchronization cancelled."
            TradeDataStore.shared.lastSyncError = nil
            return results
        }
        
        // Construct user-facing summary report
        let successCount = results.filter { $0.success }.count
        let actualErrors = results.filter { !$0.success && !($0.error?.lowercased().contains("cancel") ?? false) }
        let totalExecs = results.reduce(0) { $0 + $1.importedExecutionsCount }
        
        if actualErrors.isEmpty {
            let summary = "Sync completed: \(successCount) source(s) updated, \(totalExecs) executions imported."
            TradeDataStore.shared.lastSyncSummary = summary
            TradeDataStore.shared.lastSyncError = nil
        } else {
            let errs = actualErrors.compactMap { $0.error }.joined(separator: " · ")
            TradeDataStore.shared.lastSyncError = errs
            TradeDataStore.shared.lastSyncSummary = "Sync finished with \(actualErrors.count) warning(s)."
        }
        
        return results
    }
}
