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
    }
    
    public func deleteMissedTrade(id: String) {
        missedTrades.removeAll(where: { $0.id == id })
        saveToDisk(immediate: true)
    }
    
    public func toggleArchiveMissedTrade(id: String) {
        if let idx = missedTrades.firstIndex(where: { $0.id == id }) {
            if missedTrades[idx].archivedAt == nil {
                missedTrades[idx].archivedAt = JournalIds.nowIso()
            } else {
                missedTrades[idx].archivedAt = nil
            }
            saveToDisk()
        }
    }
    
    // MARK: - Progress Rules & Disciplined Routines
    
    public static var defaultProgressRules: [ProgressRule] {
        [
            ProgressRule(title: "Check high-impact economic news", stage: "Before trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Identify H1-H4 Key Levels & Liquidity", stage: "Before trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Always set Stop Loss before order fill", stage: "During trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Do not move SL or hold beyond planned R:R", stage: "During trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Log emotional notes & post-trade review", stage: "After trading", weekdaysJson: "[1,2,3,4,5]"),
            ProgressRule(title: "Save chart screenshots and score Playbook", stage: "After trading", weekdaysJson: "[1,2,3,4,5]")
        ]
    }
    
    public func saveProgressRule(_ rule: ProgressRule) {
        if let idx = progressRules.firstIndex(where: { $0.id == rule.id }) {
            progressRules[idx] = rule
        } else {
            progressRules.append(rule)
        }
        saveToDisk()
    }
    
    public func deleteProgressRule(id: String) {
        progressRules.removeAll(where: { $0.id == id })
        progressChecks.removeAll(where: { $0.ruleId == id })
        saveToDisk(immediate: true)
        Task {
            try? await SupabaseService.shared.deleteProgressRule(id: id)
        }
    }
    
    public func toggleProgressCheck(ruleId: String, date: String) {
        if let idx = progressChecks.firstIndex(where: { $0.ruleId == ruleId && $0.date == date }) {
            progressChecks[idx].done.toggle()
        } else {
            progressChecks.append(ProgressCheck(ruleId: ruleId, date: date, done: true))
        }
        saveToDisk()
    }
    
    public func progressScore(for date: String) -> (completed: Int, total: Int, percent: Double) {
        let activeRules = progressRules.filter { $0.archivedAt == nil }
        guard !activeRules.isEmpty else { return (0, 0, 0) }
        let completed = activeRules.filter { r in
            progressChecks.contains(where: { $0.ruleId == r.id && $0.date == date && $0.done })
        }.count
        let pct = Double(completed) / Double(activeRules.count)
        return (completed, activeRules.count, pct)
    }
    
    // MARK: - Playbooks & Discipline Assessments
    
    public func savePlaybook(_ playbook: Playbook) {
        if let idx = playbooks.firstIndex(where: { $0.id == playbook.id }) {
            playbooks[idx] = playbook
        } else {
            playbooks.append(playbook)
        }
        saveToDisk()
    }

    public func updatePlaybook(id: String, title: String, description: String, rules: [String]) {
        guard let idx = playbooks.firstIndex(where: { $0.id == id }) else { return }
        playbooks[idx].name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        playbooks[idx].rules = rules
        saveToDisk()
        let updated = playbooks[idx]
        Task {
            try? await SupabaseService.shared.upsertPlaybooks([updated])
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
