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
    
    /// Executes the saved Quick Sync strategy (typically last 30 days for active accounts)
    @discardableResult
    public func performQuickSync() async -> [SyncResult] {
        await performSync(with: savedQuickSyncOptions)
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
        
        // 2. Synchronize market data sources concurrently or sequentially
        for provider in brokerProviders {
            self.currentProgress = "Syncing with \(provider.displayName)..."
            TradeDataStore.shared.lastSyncSummary = self.currentProgress
            
            do {
                let res = try await provider.performSync(options: options) { [weak self] update in
                    Task { @MainActor in
                        self?.currentProgress = "\(update.providerName): \(update.message)"
                        TradeDataStore.shared.lastSyncSummary = self?.currentProgress
                    }
                }
                results.append(res)
                lastSyncResults[provider.id] = res
            } catch {
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
        
        // 3. Persist local store
        TradeDataStore.shared.saveToDisk()
        
        // 4. If Cloud Backup is requested and Supabase provider is configured, backup fresh data
        if options.backupToCloud, let supabaseProvider = provider(for: "supabase"), supabaseProvider.isConfigured {
            self.currentProgress = "Backing up to Supabase Cloud Database..."
            TradeDataStore.shared.lastSyncSummary = self.currentProgress
            
            do {
                let cloudRes = try await supabaseProvider.performSync(options: options) { [weak self] update in
                    Task { @MainActor in
                        self?.currentProgress = update.message
                        TradeDataStore.shared.lastSyncSummary = self?.currentProgress
                    }
                }
                results.append(cloudRes)
                lastSyncResults["supabase"] = cloudRes
            } catch {
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
        
        // Construct user-facing summary report
        let successCount = results.filter { $0.success }.count
        let failCount = results.filter { !$0.success }.count
        let totalExecs = results.reduce(0) { $0 + $1.importedExecutionsCount }
        
        if failCount == 0 {
            let summary = "Sync completed: \(successCount) source(s) updated, \(totalExecs) executions imported."
            TradeDataStore.shared.lastSyncSummary = summary
            TradeDataStore.shared.lastSyncError = nil
        } else {
            let errs = results.compactMap { $0.error }.joined(separator: " · ")
            TradeDataStore.shared.lastSyncError = errs
            TradeDataStore.shared.lastSyncSummary = "Sync finished with \(failCount) warning(s)."
        }
        
        return results
    }
}
