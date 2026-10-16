import Foundation

/// Analyzes playbook discipline and rule adherence
public enum AdherenceEngine {
    
    public static func analyzeAdherence(
        playbooks: [Playbook],
        trades: [Trade],
        assessments: [PlaybookRuleAssessment]
    ) -> [PlaybookAdherenceSummary] {
        // Group trades by playbook
        var tradesByPlaybook: [String: [Trade]] = [:]
        for trade in trades {
            guard trade.status != .open, let pbId = trade.playbookId, !pbId.isEmpty else { continue }
            tradesByPlaybook[pbId, default: []].append(trade)
        }
        
        // Group assessments by playbook -> tradeKey -> rule -> followed
        var assessMap: [String: [String: [String: Bool]]] = [:]
        for a in assessments {
            assessMap[a.playbookId, default: [:]][a.tradeKey, default: [:]][a.rule] = a.followed
        }
        
        return playbooks.map { playbook in
            let pbTrades = tradesByPlaybook[playbook.id] ?? []
            let uniqueRules = Array(Set(playbook.rules))
            
            var followedTrades: [Trade] = []
            var brokenTrades: [Trade] = []
            var evaluatedCount = 0
            var positiveCount = 0
            
            for trade in pbTrades {
                let tradeAssessed = assessMap[playbook.id]?[trade.key] ?? [:]
                var isComplete = !uniqueRules.isEmpty
                var hasBroken = false
                
                for rule in uniqueRules {
                    if let result = tradeAssessed[rule] {
                        evaluatedCount += 1
                        if result {
                            positiveCount += 1
                        } else {
                            hasBroken = true
                        }
                    } else {
                        isComplete = false
                    }
                }
                
                if hasBroken {
                    brokenTrades.append(trade)
                } else if isComplete {
                    followedTrades.append(trade)
                }
            }
            
            let rate: Double? = evaluatedCount > 0 ? Double(positiveCount) / Double(evaluatedCount) : nil
            let pnlFollowed = followedTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
            let pnlBroken = brokenTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
            let unassessed = pbTrades.count - followedTrades.count - brokenTrades.count
            
            return PlaybookAdherenceSummary(
                playbook: playbook,
                totalTrades: pbTrades.count,
                followedTradesCount: followedTrades.count,
                brokenTradesCount: brokenTrades.count,
                unassessedTradesCount: max(0, unassessed),
                overallAdherenceRate: rate,
                netPnlWhenFollowed: pnlFollowed,
                netPnlWhenBroken: pnlBroken
            )
        }
    }
}
