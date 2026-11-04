import Foundation
import Combine

// MARK: - Remote Synchronization Extension
extension TradeDataStore {
    
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cancelled") || desc.contains("canceled") { return true }
        return false
    }
    
    public static func isSameAccountId(_ a: String, _ b: String) -> Bool {
        a.isEquivalentAccountId(to: b)
    }
    
    // MARK: - Supabase Synchronization
    
    public func syncWithSupabase(isBackground: Bool = false) async {
        guard SupabaseService.shared.isConfigured else {
            AppLogger.info("Supabase credentials not configured in settings, running in local-first mode.")
            return
        }
        
        if !isBackground {
            await MainActor.run {
                self.isSyncing = true
                self.lastSyncError = nil
            }
        }
        defer {
            if !isBackground {
                Task { @MainActor in
                    self.isSyncing = false
                }
            }
        }
        
        var ctx = SupabaseSyncContext()

        guard await syncSupabaseAccounts(&ctx), !Task.isCancelled else { return }
        guard await syncSupabaseTrades(&ctx), !Task.isCancelled else { return }
        guard await syncSupabaseExecutions(&ctx), !Task.isCancelled else { return }
        guard await syncSupabasePlaybooks(&ctx), !Task.isCancelled else { return }
        guard await syncSupabaseJournalDays(&ctx), !Task.isCancelled else { return }
        guard await syncSupabasePropAccounts(&ctx), !Task.isCancelled else { return }
        guard await syncSupabasePropEntries(&ctx), !Task.isCancelled else { return }
        guard await syncSupabasePropReceipts(&ctx), !Task.isCancelled else { return }
        guard await syncSupabasePropAudits(&ctx), !Task.isCancelled else { return }
        guard await syncSupabaseAttachmentsSettingsAndNotebook(&ctx), !Task.isCancelled else { return }
        guard await syncSupabaseProgressRoutines(&ctx), !Task.isCancelled else { return }
        guard await syncSupabaseMissedTrades(&ctx), !Task.isCancelled else { return }

        // 10. Synchronize Economic Calendar Archive with Supabase asynchronously without blocking trade store
        Task.detached(priority: .utility) {
            await ForexFactoryService.shared.syncWithSupabase()
        }

        // 11. Synchronize AI Long-Term Memories & Research Projects with Supabase asynchronously
        Task.detached(priority: .utility) {
            await AIAdvisorMemoryEngine.shared.syncWithRemote()
            await AIResearchWorkspaceEngine.shared.syncWithRemote()
        }

        if Task.isCancelled {
            if !isBackground {
                await MainActor.run { self.isSyncing = false }
            }
            return
        }

        let totalRecords = ctx.accountsCount + ctx.tradesCount + ctx.executionsCount + ctx.propCount
        if totalRecords > 0 {
            deduplicateAndCleanAccounts()
            if isBackground {
                performSaveToDiskAsync()
            } else {
                saveToDisk(immediate: true)
            }
        } else if !isBackground {
            saveToDisk(immediate: true)
        }

        if !isBackground {
            await MainActor.run {
                if totalRecords > 0 {
                    var summary = "Supabase sync successful: Downloaded \(ctx.accountsCount) accounts, \(ctx.tradesCount) trades, \(ctx.executionsCount) executions, \(ctx.propCount) prop accounts."
                    if !ctx.warnings.isEmpty {
                        summary += " (Warnings: \(ctx.warnings.joined(separator: "; ")))"
                    }
                    self.lastSyncSummary = summary
                    self.lastSyncError = nil
                } else if !ctx.warnings.isEmpty {
                    self.lastSyncError = ctx.warnings.joined(separator: "\n")
                } else {
                    self.lastSyncSummary = "Supabase connection successful. Local and cloud data are synchronized (0 new records)."
                    self.lastSyncError = nil
                }
                self.isSyncing = false
            }
        }
        AppLogger.info("Supabase sync completed (isBackground=\(isBackground)): Accounts=\(ctx.accountsCount), Trades=\(ctx.tradesCount), Executions=\(ctx.executionsCount)")
    }
}
