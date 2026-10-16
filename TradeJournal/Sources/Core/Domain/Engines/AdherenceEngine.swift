import Foundation

public struct RuleAdherenceStat: Sendable, Equatable {
    public let rule: String
    public let evaluated: Int
    public let rate: Double?
    public let followed: GroupSummary
    public let broken: GroupSummary
}

public struct PlaybookAdherenceSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let playbook: Playbook
    public let total: Int
    public let evaluated: Int
    public let possible: Int
    public let rate: Double?
    public let accountIds: [String]
    public let followed: GroupSummary
    public let broken: GroupSummary
    public let unassessed: Int
    public let rules: [RuleAdherenceStat]
    
    // Compatibility helpers
    public var totalTrades: Int { total }
    public var followedTradesCount: Int { followed.trades }
    public var brokenTradesCount: Int { broken.trades }
    public var unassessedTradesCount: Int { unassessed }
    public var overallAdherenceRate: Double? { rate }
    public var netPnlWhenFollowed: Decimal { followed.netPnl }
    public var netPnlWhenBroken: Decimal { broken.netPnl }
}

/// Port 1:1 từ `packages/core/src/adherence.ts`.
public enum AdherenceEngine {
    
    public static func analyzeAdherence(
        playbooks: [Playbook],
        trades: [Trade],
        assessments: [PlaybookRuleAssessment] = []
    ) -> [PlaybookAdherenceSummary] {
        var tradesByBook: [String: [Trade]] = [:]
        for trade in trades {
            guard let id = trade.playbookId, !id.isEmpty, trade.status != .open else { continue }
            tradesByBook[id, default: []].append(trade)
        }
        
        var checksByBook: [String: [String: [String: Bool]]] = [:]
        for check in assessments {
            checksByBook[check.playbookId, default: [:]][check.tradeKey, default: [:]][check.rule] = check.followed
        }
        
        return playbooks.map { book in
            let ts = tradesByBook[book.id] ?? []
            let uniqueRuleStrings = Array(Set(book.rules))
            
            var ruleFollowedMap: [String: [Trade]] = [:]
            var ruleBrokenMap: [String: [Trade]] = [:]
            for r in uniqueRuleStrings {
                ruleFollowedMap[r] = []
                ruleBrokenMap[r] = []
            }
            
            var followedTrades: [Trade] = []
            var brokenTrades: [Trade] = []
            var evaluated = 0
            var positive = 0
            
            for trade in ts {
                let assessed = checksByBook[book.id]?[trade.key] ?? [:]
                var complete = !uniqueRuleStrings.isEmpty
                var hasBroken = false
                
                for rule in uniqueRuleStrings {
                    if let result = assessed[rule] {
                        evaluated += 1
                        if result {
                            positive += 1
                            ruleFollowedMap[rule]?.append(trade)
                        } else {
                            hasBroken = true
                            ruleBrokenMap[rule]?.append(trade)
                        }
                    } else {
                        complete = false
                    }
                }
                
                if hasBroken {
                    brokenTrades.append(trade)
                } else if complete {
                    followedTrades.append(trade)
                }
            }
            
            let rate: Double? = evaluated > 0 ? Double(positive) / Double(evaluated) : nil
            let accountIds = Array(Set(ts.map { $0.accountId }))
            let followedSummary = TradeAnalysisEngine.summarizeGroup(all: followedTrades)
            let brokenSummary = TradeAnalysisEngine.summarizeGroup(all: brokenTrades)
            let unassessed = ts.count - followedTrades.count - brokenTrades.count
            
            let ruleStats: [RuleAdherenceStat] = uniqueRuleStrings.map { rule in
                let fList = ruleFollowedMap[rule] ?? []
                let bList = ruleBrokenMap[rule] ?? []
                let totalEval = fList.count + bList.count
                let rRate = totalEval > 0 ? Double(fList.count) / Double(totalEval) : nil
                return RuleAdherenceStat(
                    rule: rule,
                    evaluated: totalEval,
                    rate: rRate,
                    followed: TradeAnalysisEngine.summarizeGroup(all: fList),
                    broken: TradeAnalysisEngine.summarizeGroup(all: bList)
                )
            }
            
            return PlaybookAdherenceSummary(
                id: book.id,
                playbook: book,
                total: ts.count,
                evaluated: evaluated,
                possible: ts.count * uniqueRuleStrings.count,
                rate: rate,
                accountIds: accountIds,
                followed: followedSummary,
                broken: brokenSummary,
                unassessed: max(0, unassessed),
                rules: ruleStats
            )
        }
    }
    
    public static func analyzeAdherence(
        playbooks: [Playbook],
        trades: [Trade],
        checks: [PlaybookRuleAssessment]
    ) -> [PlaybookAdherenceSummary] {
        analyzeAdherence(playbooks: playbooks, trades: trades, assessments: checks)
    }
    
    public static func analyzeAdherence(
        trades: [Trade],
        playbooks: [PlaybookRuleSet],
        checks: [PlaybookRuleAssessment]
    ) -> [PlaybookAdherenceSummary] {
        let converted = playbooks.map { Playbook(id: $0.id, title: $0.id, rules: $0.rules) }
        return analyzeAdherence(playbooks: converted, trades: trades, assessments: checks)
    }
    
    public static func analyzeAdherence(
        trades: [Trade],
        playbooks: [Playbook],
        checks: [PlaybookRuleAssessment]
    ) -> [PlaybookAdherenceSummary] {
        analyzeAdherence(playbooks: playbooks, trades: trades, assessments: checks)
    }
}
