import Foundation
import Combine

// MARK: - Provider Synchronization (The5ers, cTrader, Global)
extension TradeDataStore {
    // MARK: - Sync Cancellation
    
    @MainActor
    public func cancelSync() {
        The5ersService.shared.cancelSync()
        CTraderService.shared.cancelSync()
        SyncManager.shared.cancelSync()
        self.isSyncing = false
        self.lastSyncSummary = "Synchronization cancelled."
        self.lastSyncError = nil
        self.objectWillChange.send()
    }
    
    public func syncWithThe5ers() async throws -> Int {
        await MainActor.run {
            self.isSyncing = true
            self.lastSyncError = nil
        }
        defer {
            Task { @MainActor in self.isSyncing = false }
        }
        do {
            let count = try await The5ersService.shared.syncWithTradeStore(dataStore: self)
            await MainActor.run {
                if The5ersService.shared.isCancelledByUser {
                    self.lastSyncSummary = "Synchronization cancelled."
                } else if count > 0 {
                    self.lastSyncSummary = "The5ers MCP synchronized successfully: \(count) accounts, \(self.trades.filter { $0.tags.contains("the5ers") }.count) trades."
                } else {
                    self.lastSyncSummary = The5ersService.shared.lastStatus
                }
                self.objectWillChange.send()
            }
            if count > 0 && SupabaseService.shared.isConfigured {
                Task {
                    await self.syncWithSupabase(isBackground: true)
                }
            }
            return count
        } catch {
            if Self.isCancellation(error) || The5ersService.shared.isCancelledByUser {
                await MainActor.run {
                    self.lastSyncSummary = "Synchronization cancelled."
                    self.lastSyncError = nil
                    self.objectWillChange.send()
                }
                return 0
            }
            throw error
        }
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
}
