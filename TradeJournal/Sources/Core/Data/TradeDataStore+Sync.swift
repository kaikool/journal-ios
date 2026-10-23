import Foundation
import SwiftUI

// MARK: - Remote Synchronization Extension
extension TradeDataStore {
    
    public static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        let desc = error.localizedDescription.lowercased()
        if desc.contains("cancel") { return true }
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
                    if let idx = accounts.firstIndex(where: { $0.id.isEquivalentAccountId(to: rAcc.id) }) {
                        var updated = rAcc
                        if let localVisible = accounts[idx].visibleInJournal {
                            updated.visibleInJournal = localVisible
                        }
                        accounts[idx] = updated
                    } else {
                        accounts.append(rAcc)
                    }
                }
                if selectedAccountId == "default-acc" || selectedAccountId == "all" || !accounts.contains(where: { $0.id == selectedAccountId || TradeDataStore.isSameAccountId($0.id, selectedAccountId) }) {
                    selectedAccountId = mostRecentActiveAccount?.id ?? visibleAccounts.first?.id ?? accounts.first?.id ?? "default-acc"
                }
                accounts.removeAll(where: { $0.id == "default-acc" && accounts.count > 1 })
            }
            
            var mergedAccountList = accounts.filter { !$0.name.hasPrefix("Account ") }
            let existingAccIds = Set(mergedAccountList.map { $0.id })
            
            for p in propAccounts {
                if let jId = p.journalAccountId, !jId.isEmpty && !existingAccIds.contains(jId) {
                    if !mergedAccountList.contains(where: { $0.id.isEquivalentAccountId(to: jId) }) {
                        mergedAccountList.append(Account(id: jId, name: p.name, broker: p.firm, kind: .sync, currency: p.currency))
                    }
                }
            }
            for i in 0..<trades.count {
                let tAcc = trades[i].accountId
                if let matched = mergedAccountList.first(where: { $0.id.isEquivalentAccountId(to: tAcc) }) {
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
                    var local = trades[idx]
                    let isBrokerSynced = local.key.hasPrefix("the5ers_") || local.key.hasPrefix("ctrader_")
                    if isBrokerSynced {
                        // Preserve authoritative local broker P&L, fees, swap, and status; only merge user annotations from cloud if local is empty
                        if (local.notes == nil || local.notes?.isEmpty == true), let rNotes = rTrade.notes, !rNotes.isEmpty {
                            local.notes = rNotes
                        }
                        if local.tags.isEmpty && !rTrade.tags.isEmpty {
                            local.tags = rTrade.tags
                        }
                        if local.mistakes.isEmpty && !rTrade.mistakes.isEmpty {
                            local.mistakes = rTrade.mistakes
                        }
                        if local.rating == nil { local.rating = rTrade.rating }
                        if local.stopLoss == nil { local.stopLoss = rTrade.stopLoss }
                        if local.profitTarget == nil { local.profitTarget = rTrade.profitTarget }
                        if local.playbookId == nil { local.playbookId = rTrade.playbookId }
                        if local.reviewedAt == nil { local.reviewedAt = rTrade.reviewedAt }
                        trades[idx] = local
                    } else if (local.netPnl != 0 || local.grossPnl != 0) && (rTrade.netPnl == 0 && rTrade.grossPnl == 0) {
                        // Keep local non-zero PnL if remote has zero PnL
                    } else {
                        trades[idx] = rTrade
                    }
                } else {
                    trades.append(rTrade)
                }
                if !rTrade.accountId.isEmpty {
                    if let matched = accounts.first(where: { $0.id.isEquivalentAccountId(to: rTrade.accountId) }) {
                        if let lastIdx = trades.indices.last, trades[lastIdx].key == rTrade.key {
                            trades[lastIdx].accountId = matched.id
                        }
                    }
                }
            }
            cleanupLegacyThe5ersCorruptions()
            deduplicateTrades()
            if selectedAccountId == "default-acc" || selectedAccountId == "all" || !accounts.contains(where: { $0.id == selectedAccountId || TradeDataStore.isSameAccountId($0.id, selectedAccountId) }) {
                selectedAccountId = mostRecentActiveAccount?.id ?? visibleAccounts.first?.id ?? accounts.first?.id ?? "default-acc"
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
                if let idx = propAccounts.firstIndex(where: { $0.id.isEquivalentAccountId(to: rAcc.id) }) {
                    let local = propAccounts[idx]
                    if local.firm == "The5ers" {
                        var merged = local
                        merged.revision = max(local.revision, rAcc.revision)
                        propAccounts[idx] = merged
                    } else if rAcc.revision >= local.revision {
                        propAccounts[idx] = rAcc
                    }
                } else {
                    propAccounts.append(rAcc)
                }
            }
            cleanupLegacyThe5ersCorruptions()
            let validAccIds = Set(accounts.map { $0.id })
            let validPropIds = Set(propAccounts.map { $0.id })
            for idx in 0..<propAccounts.count {
                if let jId = propAccounts[idx].journalAccountId, !jId.isEmpty {
                    if !validAccIds.contains(jId) {
                        if let matched = accounts.first(where: { $0.id.isEquivalentAccountId(to: jId) }) {
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
            cleanupLegacyThe5ersCorruptions()
            deduplicatePropEntries()
            
            let currentPropIds = Set(propAccounts.map { $0.id })
            let currentEntryIds = Set(propEntries.map { $0.id })
            for idx in 0..<propEntries.count {
                if propEntries[idx].firm == "The5ers" && propEntries[idx].kind == "expense" && propEntries[idx].id.hasPrefix("the5ers_purchase_") {
                    propEntries[idx].accountId = nil
                } else if let aId = propEntries[idx].accountId, !aId.isEmpty {
                    if !currentPropIds.contains(aId) {
                        if let matched = propAccounts.first(where: { $0.id.isEquivalentAccountId(to: aId) }) {
                            propEntries[idx].accountId = matched.id
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
            deduplicatePropReceipts()
            reconcileReceiptsToEntries()
            
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
            if !isBackground {
                await MainActor.run { self.isSyncing = false }
            }
            return
        }

        deduplicateAndCleanAccounts()
        saveToDisk(immediate: true)

        let totalRecords = fetchedAccountsCount + fetchedTradesCount + fetchedExecutionsCount + fetchedPropCount
        if !isBackground {
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
                self.objectWillChange.send()
            }
        }
        AppLogger.info("Supabase sync completed (isBackground=\(isBackground)): Accounts=\(fetchedAccountsCount), Trades=\(fetchedTradesCount), Executions=\(fetchedExecutionsCount)")
    }
    
    // MARK: - The5ers MCP Synchronization
    
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
