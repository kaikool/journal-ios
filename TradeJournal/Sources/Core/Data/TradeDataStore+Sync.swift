import Foundation
import SwiftUI

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
        
        var fetchedAccountsCount = 0
        var fetchedTradesCount = 0
        var fetchedExecutionsCount = 0
        var fetchedPropCount = 0
        var syncWarnings: [String] = []

        // 1. Synchronize Accounts
        do {
            let remoteAccounts = (try await SupabaseService.shared.fetchAccounts()).filter { !$0.name.hasPrefix("Account ") }
            fetchedAccountsCount = remoteAccounts.count
            var localAccounts = self.accounts
            if !remoteAccounts.isEmpty {
                for rAcc in remoteAccounts {
                    if let idx = localAccounts.firstIndex(where: { $0.id.isEquivalentAccountId(to: rAcc.id) }) {
                        var updated = rAcc
                        if let localVisible = localAccounts[idx].visibleInJournal {
                            updated.visibleInJournal = localVisible
                        }
                        localAccounts[idx] = updated
                    } else {
                        localAccounts.append(rAcc)
                    }
                }
                if localAccounts.count > 1 {
                    localAccounts.removeAll(where: { $0.id == "default-acc" })
                }
            }
            
            var mergedAccountList = localAccounts.filter { !$0.name.hasPrefix("Account ") }
            let existingAccIds = Set(mergedAccountList.map { $0.id })
            
            for p in propAccounts {
                if let jId = p.journalAccountId, !jId.isEmpty && !existingAccIds.contains(jId) {
                    if !mergedAccountList.contains(where: { $0.id.isEquivalentAccountId(to: jId) }) {
                        mergedAccountList.append(Account(id: jId, name: p.name, broker: p.firm, kind: .sync, currency: p.currency))
                    }
                }
            }
            if self.accounts != mergedAccountList {
                self.accounts = mergedAccountList
                deduplicateAndCleanAccounts()
            }
            if selectedAccountId == "default-acc" || selectedAccountId == "all" || !accounts.contains(where: { $0.id == selectedAccountId || TradeDataStore.isSameAccountId($0.id, selectedAccountId) }) {
                selectedAccountId = mostRecentActiveAccount?.id ?? visibleAccounts.first?.id ?? accounts.first?.id ?? "default-acc"
            }
            
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
            var localTrades = self.trades
            var tradesModified = false
            for rTrade in remoteTrades {
                if let idx = localTrades.firstIndex(where: { $0.key == rTrade.key }) {
                    var local = localTrades[idx]
                    let isBrokerSynced = local.key.hasPrefix("the5ers_") || local.key.hasPrefix("ctrader_")
                    if isBrokerSynced {
                        var mutated = false
                        // Preserve authoritative local broker P&L, fees, swap, and status; only merge user annotations from cloud if local is empty
                        if (local.notes == nil || local.notes?.isEmpty == true), let rNotes = rTrade.notes, !rNotes.isEmpty {
                            local.notes = rNotes
                            mutated = true
                        }
                        if local.tags.isEmpty && !rTrade.tags.isEmpty {
                            local.tags = rTrade.tags
                            mutated = true
                        }
                        if local.mistakes.isEmpty && !rTrade.mistakes.isEmpty {
                            local.mistakes = rTrade.mistakes
                            mutated = true
                        }
                        if local.rating == nil && rTrade.rating != nil { local.rating = rTrade.rating; mutated = true }
                        if local.stopLoss == nil && rTrade.stopLoss != nil { local.stopLoss = rTrade.stopLoss; mutated = true }
                        if local.profitTarget == nil && rTrade.profitTarget != nil { local.profitTarget = rTrade.profitTarget; mutated = true }
                        if local.playbookId == nil && rTrade.playbookId != nil { local.playbookId = rTrade.playbookId; mutated = true }
                        if local.reviewedAt == nil && rTrade.reviewedAt != nil { local.reviewedAt = rTrade.reviewedAt; mutated = true }
                        if mutated {
                            localTrades[idx] = local
                            tradesModified = true
                        }
                    } else if (local.netPnl != 0 || local.grossPnl != 0) && (rTrade.netPnl == 0 && rTrade.grossPnl == 0) {
                        // Keep local non-zero PnL if remote has zero PnL
                    } else if local != rTrade {
                        localTrades[idx] = rTrade
                        tradesModified = true
                    }
                } else {
                    localTrades.append(rTrade)
                    tradesModified = true
                }
                if !rTrade.accountId.isEmpty {
                    if let matched = accounts.first(where: { $0.id.isEquivalentAccountId(to: rTrade.accountId) }) {
                        if let lastIdx = localTrades.indices.last, localTrades[lastIdx].key == rTrade.key, localTrades[lastIdx].accountId != matched.id {
                            localTrades[lastIdx].accountId = matched.id
                            tradesModified = true
                        }
                    }
                }
            }
            if tradesModified || (fetchedTradesCount > 0 && localTrades.count != self.trades.count) {
                self.trades = localTrades
                cleanupLegacyThe5ersCorruptions()
                deduplicateTrades()
            }
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
                if !uniqueNew.isEmpty {
                    var localExecutions = self.executions
                    for fill in uniqueNew {
                        executionHashes.insert(fill.contentHash)
                        localExecutions.append(fill)
                    }
                    self.executions = localExecutions
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
            var localPlaybooks = self.playbooks
            var playbooksModified = false
            var playbooksToUpload: [Playbook] = []
            
            // 1. Reconcile remote playbooks against local
            for rPb in remotePlaybooks {
                // If deleted locally, delete from Supabase and skip
                if deletedPlaybookIds.contains(rPb.id) || (rPb.name.lowercased().contains("test playbook") && deletedPlaybookIds.contains(rPb.id)) {
                    Task { try? await SupabaseService.shared.deletePlaybook(id: rPb.id) }
                    continue
                }
                
                if let idx = localPlaybooks.firstIndex(where: { $0.id == rPb.id }) {
                    let local = localPlaybooks[idx]
                    // Check if content differs
                    if local.name != rPb.name || local.description != rPb.description || local.rules != rPb.rules {
                        // Conflict resolution: if local was edited, keep local and upload to Supabase
                        if local.updatedAt >= rPb.createdAt {
                            playbooksToUpload.append(local)
                        } else {
                            // Remote is newer: adopt remote
                            localPlaybooks[idx] = rPb
                            playbooksModified = true
                        }
                    }
                } else {
                    // New remote playbook not yet in local
                    localPlaybooks.append(rPb)
                    playbooksModified = true
                }
            }
            
            // 2. Identify local playbooks not yet on remote or edited locally
            for localPb in localPlaybooks {
                if deletedPlaybookIds.contains(localPb.id) { continue }
                if !remotePlaybooks.contains(where: { $0.id == localPb.id }) {
                    playbooksToUpload.append(localPb)
                }
            }
            
            // 3. Purge any deleted playbooks from local collection
            let countBeforePurge = localPlaybooks.count
            localPlaybooks.removeAll { deletedPlaybookIds.contains($0.id) }
            if localPlaybooks.count != countBeforePurge {
                playbooksModified = true
            }
            
            if playbooksModified {
                self.playbooks = localPlaybooks
                saveToDisk(immediate: true)
            }
            
            // 4. Upsert pending playbooks to Supabase
            if !playbooksToUpload.isEmpty {
                do {
                    try await SupabaseService.shared.upsertPlaybooks(playbooksToUpload)
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
                    let msg = error.localizedDescription.lowercased()
                    if msg.contains("row-level security") || msg.contains("rls") {
                        AppLogger.warning("Supabase prop audits RLS: \(error.localizedDescription)")
                    } else {
                        AppLogger.warning("Supabase prop audits upsert warning: \(error.localizedDescription)")
                        syncWarnings.append("Prop audits upload: \(error.localizedDescription)")
                    }
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

        // 6. Synchronize Settings (The5ers Token, AI Configuration)
        do {
            let remoteSettings = try await SupabaseService.shared.fetchSettings()
            var localSettingsToUpload: [JournalSettingRecord] = []
            
            // Sync The5ers MCP Token across devices
            if let remoteToken = remoteSettings.first(where: { $0.key == "the5ers_mcp_token" })?.value, !remoteToken.isEmpty {
                let localToken = UserDefaults.standard.string(forKey: "the5ers_mcp_token") ?? ""
                if localToken.isEmpty {
                    UserDefaults.standard.set(remoteToken, forKey: "the5ers_mcp_token")
                    The5ersService.shared.mcpToken = remoteToken
                }
            } else if let localToken = UserDefaults.standard.string(forKey: "the5ers_mcp_token"), !localToken.isEmpty {
                localSettingsToUpload.append(JournalSettingRecord(key: "the5ers_mcp_token", value: localToken))
            }
            
            // Sync AI Configuration across devices
            if let remoteAi = remoteSettings.first(where: { $0.key == "ai_reflection" })?.value, !remoteAi.isEmpty {
                if let data = remoteAi.data(using: .utf8), let decoded = try? JSONDecoder().decode(AiSettingsConfig.self, from: data) {
                    if self.aiSettings == .default && decoded != .default {
                        self.aiSettings = decoded
                    }
                }
            } else if self.aiSettings != .default {
                if let data = try? JSONEncoder().encode(self.aiSettings), let jsonStr = String(data: data, encoding: .utf8) {
                    localSettingsToUpload.append(JournalSettingRecord(key: "ai_reflection", value: jsonStr))
                }
            }
            
            if !localSettingsToUpload.isEmpty {
                try? await SupabaseService.shared.upsertSettings(localSettingsToUpload)
            }
        } catch {
            AppLogger.warning("Supabase settings sync warning: \(error.localizedDescription)")
        }

        // 7. Synchronize Notebook Folders & Notes
        do {
            let remoteFolders = try await SupabaseService.shared.fetchFolders()
            for rF in remoteFolders {
                if let idx = folders.firstIndex(where: { $0.id == rF.id }) {
                    if rF.deletedAt != nil && folders[idx].deletedAt == nil {
                        folders[idx].deletedAt = rF.deletedAt
                    } else if folders[idx].name != rF.name {
                        folders[idx].name = rF.name
                    }
                } else {
                    folders.append(rF)
                }
            }
            let foldersToUpload = folders.filter { local in
                !remoteFolders.contains(where: { $0.id == local.id })
            }
            if !foldersToUpload.isEmpty {
                try? await SupabaseService.shared.upsertFolders(foldersToUpload)
            }
            
            let remoteNotes = try await SupabaseService.shared.fetchNotes()
            for rN in remoteNotes {
                if let idx = notebookNotes.firstIndex(where: { $0.id == rN.id }) {
                    if rN.updatedAt >= notebookNotes[idx].updatedAt {
                        notebookNotes[idx] = rN
                    }
                } else {
                    notebookNotes.append(rN)
                }
            }
            let notesToUpload = notebookNotes.filter { local in
                !remoteNotes.contains(where: { $0.id == local.id && $0.updatedAt >= local.updatedAt })
            }
            if !notesToUpload.isEmpty {
                try? await SupabaseService.shared.upsertNotes(notesToUpload)
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase notebook sync warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // 8. Synchronize Progress Rules (Routines) & Checks
        do {
            let remoteRules = try await SupabaseService.shared.fetchProgressRules()
            var localRules = self.progressRules
            var rulesModified = false
            var rulesToUpload: [ProgressRule] = []
            
            for rRule in remoteRules {
                // If permanently deleted locally, enforce deletion on Supabase and skip
                if deletedProgressRuleIds.contains(rRule.id) {
                    Task { try? await SupabaseService.shared.deleteProgressRule(id: rRule.id) }
                    continue
                }
                
                if let idx = localRules.firstIndex(where: { $0.id == rRule.id }) {
                    let local = localRules[idx]
                    if local.title != rRule.title || local.stage != rRule.stage || local.weekdaysJson != rRule.weekdaysJson || local.archivedAt != rRule.archivedAt {
                        if local.archivedAt != nil && rRule.archivedAt == nil {
                            rulesToUpload.append(local)
                        } else {
                            localRules[idx] = rRule
                            rulesModified = true
                        }
                    }
                } else {
                    localRules.append(rRule)
                    rulesModified = true
                }
            }
            
            for localRule in localRules {
                if deletedProgressRuleIds.contains(localRule.id) { continue }
                if !remoteRules.contains(where: { $0.id == localRule.id }) {
                    rulesToUpload.append(localRule)
                }
            }
            
            let countBefore = localRules.count
            localRules.removeAll { deletedProgressRuleIds.contains($0.id) }
            if localRules.count != countBefore {
                rulesModified = true
            }
            
            if rulesModified {
                self.progressRules = localRules
                saveToDisk(immediate: true)
            }
            
            if !rulesToUpload.isEmpty {
                try? await SupabaseService.shared.upsertProgressRules(rulesToUpload)
            }
            
            let remoteChecks = try await SupabaseService.shared.fetchProgressChecks()
            var localChecks = self.progressChecks
            var checksModified = false
            var checksToUpload: [ProgressCheck] = []
            
            for rCheck in remoteChecks {
                if deletedProgressRuleIds.contains(rCheck.ruleId) {
                    Task { try? await SupabaseService.shared.deleteProgressCheck(id: rCheck.id) }
                    continue
                }
                if let idx = localChecks.firstIndex(where: { $0.ruleId == rCheck.ruleId && $0.date == rCheck.date }) {
                    if localChecks[idx].done != rCheck.done {
                        localChecks[idx].done = rCheck.done
                        checksModified = true
                    }
                } else {
                    localChecks.append(rCheck)
                    checksModified = true
                }
            }
            
            for localCheck in localChecks {
                if deletedProgressRuleIds.contains(localCheck.ruleId) { continue }
                if !remoteChecks.contains(where: { $0.ruleId == localCheck.ruleId && $0.date == localCheck.date }) {
                    checksToUpload.append(localCheck)
                }
            }
            
            let checkCountBefore = localChecks.count
            localChecks.removeAll { deletedProgressRuleIds.contains($0.ruleId) }
            if localChecks.count != checkCountBefore {
                checksModified = true
            }
            
            if checksModified {
                self.progressChecks = localChecks
                saveToDisk(immediate: true)
            }
            
            if !checksToUpload.isEmpty {
                try? await SupabaseService.shared.upsertProgressChecks(checksToUpload)
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase progress rules/checks sync warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

        // 9. Synchronize Missed Trades
        do {
            let remoteMissed = try await SupabaseService.shared.fetchMissedTrades()
            for rMissed in remoteMissed {
                if let idx = missedTrades.firstIndex(where: { $0.id == rMissed.id }) {
                    if missedTrades[idx].symbol != rMissed.symbol || missedTrades[idx].notes != rMissed.notes || missedTrades[idx].archivedAt != rMissed.archivedAt {
                        missedTrades[idx] = rMissed
                    }
                } else {
                    missedTrades.append(rMissed)
                }
            }
            let missedToUpload = missedTrades.filter { local in
                !remoteMissed.contains(where: { $0.id == local.id })
            }
            if !missedToUpload.isEmpty {
                try? await SupabaseService.shared.upsertMissedTrades(missedToUpload)
            }
        } catch {
            if Self.isCancellation(error) { return }
            AppLogger.warning("Supabase missed trades sync warning: \(error.localizedDescription)")
        }

        if Task.isCancelled { return }

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

        let totalRecords = fetchedAccountsCount + fetchedTradesCount + fetchedExecutionsCount + fetchedPropCount
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
