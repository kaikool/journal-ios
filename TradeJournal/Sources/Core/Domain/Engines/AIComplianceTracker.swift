import Foundation

// MARK: - AI Compliance & Experience Tracker
/// Mathematical engine that audits trader discipline over time by tracking lesson adherence and recurring failure patterns.
/// Zero hardcoded judgments; strictly provides quantitative compliance statistics to the AI prompt.
public enum AIComplianceTracker {
    
    public struct RecurringViolation: Equatable, Sendable {
        public let rule: String
        public let count: Int
        
        public init(rule: String, count: Int) {
            self.rule = rule
            self.count = count
        }
    }
    
    public struct ComplianceSummary: Equatable, Sendable {
        public let totalLessons: Int
        public let totalVerified: Int
        public let totalViolated: Int
        public let adherenceRate: Double
        public let taxonomyDistribution: [TradeFailureTaxonomy: Int]
        public let recurringViolations: [RecurringViolation]
    }
    
    /// Pure computation of compliance statistics from a set of lesson evaluations
    public static func computeSummary(evaluations: [TradeLessonEvaluation]) -> ComplianceSummary {
        let total = evaluations.count
        let verified = evaluations.reduce(0) { $0 + $1.verifiedCount }
        let violated = evaluations.reduce(0) { $0 + $1.violatedCount }
        let totalAttempts = verified + violated
        let rate: Double = totalAttempts > 0 ? (Double(verified) / Double(totalAttempts)) * 100.0 : 100.0
        
        var dist: [TradeFailureTaxonomy: Int] = [:]
        for t in TradeFailureTaxonomy.allCases {
            dist[t] = 0
        }
        for e in evaluations {
            dist[e.taxonomy, default: 0] += 1
        }
        
        let recurring: [RecurringViolation] = evaluations
            .filter { $0.violatedCount > 0 && $0.ruleBroken != nil && !$0.ruleBroken!.isEmpty }
            .map { RecurringViolation(rule: $0.ruleBroken!, count: $0.violatedCount) }
            .sorted { $0.count > $1.count }
        
        return ComplianceSummary(
            totalLessons: total,
            totalVerified: verified,
            totalViolated: violated,
            adherenceRate: rate,
            taxonomyDistribution: dist,
            recurringViolations: recurring
        )
    }
    
    /// Formats compliance summary into structured markdown form for AI Coach prompts
    public static func formatComplianceForPrompt(_ summary: ComplianceSummary, isVi: Bool = true) -> String {
        guard summary.totalLessons > 0 else { return "" }
        
        let badExec = summary.taxonomyDistribution[.badExecution] ?? 0
        let flawedPlan = summary.taxonomyDistribution[.flawedPlan] ?? 0
        let regimeShift = summary.taxonomyDistribution[.regimeShift] ?? 0
        let randomLoss = summary.taxonomyDistribution[.randomLoss] ?? 0
        
        if isVi {
            var recurringStr = "Không ghi nhận tái phạm"
            if !summary.recurringViolations.isEmpty {
                recurringStr = summary.recurringViolations.prefix(3).map {
                    "[\($0.rule)] (Tái phạm \($0.count) lần)"
                }.joined(separator: ", ")
            }
            
            return """
            
            [LỊCH SỬ TUÂN THỦ KỶ LUẬT & SAI LẦM QUÁ KHỨ (LESSON COMPLIANCE AUDIT)]:
            • Tổng số bài học ghi nhận: \(summary.totalLessons) (Tuân thủ: \(summary.totalVerified) lần, Tái phạm: \(summary.totalViolated) lần, Tỷ lệ kỷ luật: \(String(format: "%.1f", summary.adherenceRate))%)
            • Phân loại nguyên nhân sai lệch: Lỗi thực thi: \(badExec) | Kế hoạch sai: \(flawedPlan) | Thị trường đổi pha: \(regimeShift) | Thua lỗ ngẫu nhiên: \(randomLoss)
            • Mẫu sai lầm lặp lại cần giám sát: \(recurringStr)
            """
        } else {
            var recurringStr = "None recorded"
            if !summary.recurringViolations.isEmpty {
                recurringStr = summary.recurringViolations.prefix(3).map {
                    "[\($0.rule)] (Repeated \($0.count) times)"
                }.joined(separator: ", ")
            }
            
            return """
            
            [LESSON COMPLIANCE & HISTORICAL ERROR AUDIT]:
            • Recorded Lessons: \(summary.totalLessons) (Adhered: \(summary.totalVerified), Repeated: \(summary.totalViolated), Discipline Rate: \(String(format: "%.1f", summary.adherenceRate))%)
            • Failure Breakdown: Bad Execution: \(badExec) | Flawed Plan: \(flawedPlan) | Regime Shift: \(regimeShift) | Random Loss: \(randomLoss)
            • Recurring Pitfalls to Monitor: \(recurringStr)
            """
        }
    }
}
