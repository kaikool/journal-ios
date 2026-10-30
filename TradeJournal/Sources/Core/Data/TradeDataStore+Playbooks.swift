import Foundation
import SwiftUI

// MARK: - Playbooks, Missed Trades & Discipline Routines Extension
extension TradeDataStore {
    
    // MARK: - Missed Trades
    
    public func saveMissedTrade(_ trade: MissedTrade) {
        if let idx = missedTrades.firstIndex(where: { $0.id == trade.id }) {
            missedTrades[idx] = trade
        } else {
            missedTrades.append(trade)
        }
        saveToDisk()
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertMissedTrades([trade])
            }
        }
    }
    
    public func deleteMissedTrade(id: String) {
        missedTrades.removeAll(where: { $0.id == id })
        saveToDisk(immediate: true)
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.deleteMissedTrade(id: id)
            }
        }
    }
    
    public func toggleArchiveMissedTrade(id: String) {
        if let idx = missedTrades.firstIndex(where: { $0.id == id }) {
            if missedTrades[idx].archivedAt == nil {
                missedTrades[idx].archivedAt = JournalIds.nowIso()
            } else {
                missedTrades[idx].archivedAt = nil
            }
            saveToDisk()
            let updated = missedTrades[idx]
            Task {
                if SupabaseService.shared.isConfigured {
                    try? await SupabaseService.shared.upsertMissedTrades([updated])
                }
            }
        }
    }
    
    // MARK: - Progress Rules & Disciplined Routines
    
    public static var defaultProgressRules: [ProgressRule] {
        [
            ProgressRule(id: "rule_news_check", title: "Check high-impact economic news", stage: "Before trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(id: "rule_levels_liquidity", title: "Identify H1-H4 Key Levels & Liquidity", stage: "Before trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(id: "rule_set_sl", title: "Always set Stop Loss before order fill", stage: "During trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(id: "rule_hold_rr", title: "Do not move SL or hold beyond planned R:R", stage: "During trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(id: "rule_emotional_notes", title: "Log emotional notes & post-trade review", stage: "After trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(id: "rule_save_screenshots", title: "Save chart screenshots and score Playbook", stage: "After trading", weekdaysJson: "[1,2,3,4,5]")
        ]
    }
    
    public func saveProgressRule(_ rule: ProgressRule) {
        deletedProgressRuleIds.remove(rule.id)
        if let idx = progressRules.firstIndex(where: { $0.id == rule.id }) {
            progressRules[idx] = rule
        } else {
            progressRules.append(rule)
        }
        saveToDisk(immediate: true)
        objectWillChange.send()
        Task {
            if SupabaseService.shared.isConfigured {
                do {
                    try await SupabaseService.shared.upsertProgressRules([rule])
                    AppLogger.info("Successfully synced progress rule '\(rule.title)' to Supabase")
                } catch {
                    AppLogger.warning("Supabase upsertProgressRules failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Permanently deletes a progress routine from local database, memory, and Supabase cloud.
    /// Uses tombstones (`deletedProgressRuleIds`) so background sync will NEVER resurrect it.
    public func deleteProgressRule(id: String) {
        progressRules.removeAll(where: { $0.id == id })
        progressChecks.removeAll(where: { $0.ruleId == id })
        deletedProgressRuleIds.insert(id)
        saveToDisk(immediate: true)
        Task {
            do {
                try await SupabaseService.shared.deleteProgressRule(id: id)
                AppLogger.info("Permanently deleted progress rule '\(id)' from Supabase")
            } catch {
                AppLogger.warning("Supabase deleteProgressRule failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Archives a progress routine: hides it from active daily checklists while preserving historical logs.
    public func archiveProgressRule(id: String) {
        guard let idx = progressRules.firstIndex(where: { $0.id == id }) else { return }
        progressRules[idx].archivedAt = JournalIds.nowIso()
        let updated = progressRules[idx]
        saveToDisk(immediate: true)
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertProgressRules([updated])
            }
        }
    }
    
    /// Restores an archived progress routine back to active daily checklists.
    public func unarchiveProgressRule(id: String) {
        guard let idx = progressRules.firstIndex(where: { $0.id == id }) else { return }
        progressRules[idx].archivedAt = nil
        let updated = progressRules[idx]
        saveToDisk(immediate: true)
        Task {
            if SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertProgressRules([updated])
            }
        }
    }
    
    public func toggleArchiveProgressRule(id: String) {
        guard let rule = progressRules.first(where: { $0.id == id }) else { return }
        if rule.isArchived {
            unarchiveProgressRule(id: id)
        } else {
            archiveProgressRule(id: id)
        }
    }
    
    public func toggleProgressCheck(ruleId: String, date: String) {
        let checkId = "chk_\(ruleId)_\(date)"
        let checkToSync: ProgressCheck
        if let idx = progressChecks.firstIndex(where: { ($0.ruleId == ruleId && $0.date == date) || $0.id == checkId }) {
            progressChecks[idx].done.toggle()
            checkToSync = progressChecks[idx]
        } else {
            let newCheck = ProgressCheck(id: checkId, ruleId: ruleId, date: date, done: true)
            progressChecks.append(newCheck)
            checkToSync = newCheck
        }
        saveToDisk(immediate: true)
        objectWillChange.send()
        Task {
            if SupabaseService.shared.isConfigured {
                do {
                    try await SupabaseService.shared.upsertProgressChecks([checkToSync])
                    AppLogger.info("Successfully synced progress check '\(checkToSync.id)' to Supabase")
                } catch {
                    AppLogger.warning("Supabase upsertProgressChecks failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func progressScore(for date: String) -> (completed: Int, total: Int, percent: Double) {
        let activeRules = progressRules.filter { r in
            !deletedProgressRuleIds.contains(r.id) && r.isActive(on: date) && r.isScheduled(on: date)
        }
        guard !activeRules.isEmpty else { return (0, 0, 0) }
        let completed = activeRules.filter { r in
            progressChecks.contains(where: { $0.ruleId == r.id && $0.date == date && $0.done })
        }.count
        let pct = Double(completed) / Double(activeRules.count)
        return (completed, activeRules.count, pct)
    }
    
    // MARK: - Playbooks & Discipline Assessments
    
    public var defaultPlaybook: Playbook? {
        playbooks.first(where: { $0.isDefault })
    }
    
    public func setDefaultPlaybook(id: String?) {
        for i in 0..<playbooks.count {
            playbooks[i].isDefault = (playbooks[i].id == id)
        }
        if let targetId = id {
            var modified = false
            for i in 0..<trades.count {
                if trades[i].playbookId == nil || trades[i].playbookId?.isEmpty == true {
                    trades[i].playbookId = targetId
                    modified = true
                }
            }
            if modified {
                invalidatePerformanceCaches()
            }
        }
        saveToDisk(immediate: true)
        Task {
            do {
                try await SupabaseService.shared.upsertPlaybooks(playbooks)
                if SupabaseService.shared.isConfigured {
                    try await SupabaseService.shared.upsertTrades(trades)
                }
            } catch {
                AppLogger.warning("Supabase setDefaultPlaybook notice: \(error.localizedDescription)")
            }
        }
    }
    
    public func savePlaybook(_ playbook: Playbook) {
        var pb = playbook
        pb.updatedAt = Date()
        if pb.isDefault {
            for i in 0..<playbooks.count where playbooks[i].id != pb.id {
                playbooks[i].isDefault = false
            }
        }
        if let idx = playbooks.firstIndex(where: { $0.id == pb.id }) {
            playbooks[idx] = pb
        } else {
            playbooks.append(pb)
        }
        deletedPlaybookIds.remove(pb.id)
        saveToDisk(immediate: true)
        Task {
            do {
                try await SupabaseService.shared.upsertPlaybooks([pb])
                AppLogger.info("Successfully saved playbook '\(pb.title)' to Supabase")
            } catch {
                AppLogger.warning("Supabase savePlaybook notice: \(error.localizedDescription)")
            }
        }
    }

    public func updatePlaybook(id: String, title: String, description: String, rules: [String], isDefault: Bool? = nil) {
        guard let idx = playbooks.firstIndex(where: { $0.id == id }) else { return }
        playbooks[idx].name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].rules = rules
        if let def = isDefault {
            playbooks[idx].isDefault = def
            if def {
                for i in 0..<playbooks.count where playbooks[i].id != id {
                    playbooks[i].isDefault = false
                }
            }
        }
        playbooks[idx].updatedAt = Date()
        deletedPlaybookIds.remove(id)
        saveToDisk(immediate: true)
        let updated = playbooks[idx]
        Task {
            do {
                try await SupabaseService.shared.upsertPlaybooks([updated])
                AppLogger.info("Successfully updated playbook '\(updated.title)' in Supabase")
            } catch {
                AppLogger.warning("Supabase updatePlaybook notice: \(error.localizedDescription)")
            }
        }
    }
    
    public func deletePlaybook(id: String) {
        playbooks.removeAll { $0.id == id }
        playbookAssessments.removeAll { $0.playbookId == id }
        for i in 0..<trades.count {
            if trades[i].playbookId == id {
                trades[i].playbookId = nil
            }
        }
        deletedPlaybookIds.insert(id)
        saveToDisk(immediate: true)
        Task {
            do {
                try await SupabaseService.shared.deletePlaybook(id: id)
                AppLogger.info("Successfully deleted playbook '\(id)' from Supabase")
            } catch {
                AppLogger.warning("Supabase deletePlaybook notice: \(error.localizedDescription)")
            }
        }
    }
    
    public func setRuleAssessment(tradeKey: String, playbookId: String, rule: String, followed: Bool) {
        let assessment = PlaybookRuleAssessment(tradeKey: tradeKey, playbookId: playbookId, rule: rule, followed: followed)
        if let idx = playbookAssessments.firstIndex(where: { $0.id == assessment.id }) {
            playbookAssessments[idx] = assessment
        } else {
            playbookAssessments.append(assessment)
        }
        saveToDisk()
    }
}
