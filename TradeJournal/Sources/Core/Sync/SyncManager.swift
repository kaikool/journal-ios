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
    
    @Published public var savedQuickSyncOptions: SyncOptions {
        didSet {
            saveQuickSyncOptions()
        }
    }
    
    public private(set) var providers: [any SyncProvider] = []
    
    private init() {
        // Load saved quick sync options from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "journal_quick_sync_options_v1"),
           let decoded = try? JSONDecoder().decode(SyncOptions.self, from: data) {
            self.savedQuickSyncOptions = decoded
        } else {
            self.savedQuickSyncOptions = .default
        }
        
        // Register core built-in providers
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
        options.backupToCloud = false // Guarantee Quick Sync never blocks on Cloud backup
        let results = await performSync(with: options)
        
        let importedCount = results.reduce(0) { $0 + $1.importedExecutionsCount }
        if importedCount > 0 {
            scheduleBackgroundCloudBackup(delaySeconds: 10)
        }
        return results
    }
    
    /// Executes a custom synchronization run with specified options
    @discardableResult
    public func performSync(with options: SyncOptions) async -> [SyncResult] {
        guard !isSyncing else {
            return Array(lastSyncResults.values)
        }
        
        self.isSyncing = true
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
        
        // 1. Separate broker/exchange providers from cloud storage providers
        let brokerProviders = providers.filter {
            $0.id != "supabase" && options.enabledProviderIds.contains($0.id) && $0.isConfigured
        }
        
        // 2. Synchronize market data sources sequentially
        for provider in brokerProviders {
            if Task.isCancelled {
                TradeDataStore.shared.lastSyncError = nil
                return results
            }
            
            self.currentProgress = "Syncing with \(provider.displayName)..."
            TradeDataStore.shared.lastSyncSummary = self.currentProgress
            
            do {
                let res = try await provider.performSync(options: options) { [weak self] update in
                    Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        self?.currentProgress = "\(update.providerName): \(update.message)"
                        TradeDataStore.shared.lastSyncSummary = self?.currentProgress
                    }
                }
                results.append(res)
                lastSyncResults[provider.id] = res
            } catch {
                if TradeDataStore.isCancellation(error) {
                    AppLogger.info("Sync cancelled for \(provider.displayName)")
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
        
        if Task.isCancelled {
            TradeDataStore.shared.lastSyncError = nil
            return results
        }
        
        // 3. Persist local store
        TradeDataStore.shared.saveToDisk()
        
        // 4. If Cloud Backup is requested and Supabase provider is configured, backup fresh data
        if options.backupToCloud, let supabaseProvider = provider(for: "supabase"), supabaseProvider.isConfigured {
            if Task.isCancelled {
                TradeDataStore.shared.lastSyncError = nil
                return results
            }
            
            self.currentProgress = "Backing up to Supabase Cloud Database..."
            TradeDataStore.shared.lastSyncSummary = self.currentProgress
            
            do {
                let cloudRes = try await supabaseProvider.performSync(options: options) { [weak self] update in
                    Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        self?.currentProgress = update.message
                        TradeDataStore.shared.lastSyncSummary = self?.currentProgress
                    }
                }
                results.append(cloudRes)
                lastSyncResults["supabase"] = cloudRes
            } catch {
                if TradeDataStore.isCancellation(error) {
                    AppLogger.info("Supabase sync cancelled.")
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
        
        if Task.isCancelled {
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
