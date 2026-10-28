import Foundation

// MARK: - Failure Taxonomy (Module D: Learning from Experience)
/// Four canonical failure modes defined in the AI Coach roadmap.
/// Zero hardcoded judgments; serves as structured categorization for objective analysis.
public enum TradeFailureTaxonomy: String, Codable, CaseIterable, Sendable {
    case badExecution = "bad_execution"
    case flawedPlan   = "flawed_plan"
    case regimeShift  = "regime_shift"
    case randomLoss   = "random_loss"
    case unclassified = "unclassified"
    
    public var titleVi: String {
        switch self {
        case .badExecution: return "Lỗi thực thi (Bad Execution)"
        case .flawedPlan:   return "Kế hoạch sai lệch (Flawed Plan)"
        case .regimeShift:  return "Thị trường đổi pha (Regime Shift)"
        case .randomLoss:   return "Thua lỗ ngẫu nhiên (Random Loss)"
        case .unclassified: return "Chưa phân loại (Unclassified)"
        }
    }
    
    public var titleEn: String {
        switch self {
        case .badExecution: return "Bad Execution"
        case .flawedPlan:   return "Flawed Plan"
        case .regimeShift:  return "Regime Shift"
        case .randomLoss:   return "Random Statistical Loss"
        case .unclassified: return "Unclassified"
        }
    }
}

// MARK: - Trade Lesson Evaluation Record
/// Structured record capturing initial plan vs realized outcome, failure taxonomy, and subsequent verification.
public struct TradeLessonEvaluation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let tradeId: String
    public let symbol: String
    public let taxonomy: TradeFailureTaxonomy
    public let deviationPoints: Decimal?
    public let plannedRR: Decimal?
    public let realizedRR: Decimal?
    public let ruleBroken: String?
    public let lessonText: String
    public var verifiedCount: Int
    public var violatedCount: Int
    public let metadataJson: String
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = JournalIds.prefixed("les_"),
        tradeId: String,
        symbol: String,
        taxonomy: TradeFailureTaxonomy,
        deviationPoints: Decimal? = nil,
        plannedRR: Decimal? = nil,
        realizedRR: Decimal? = nil,
        ruleBroken: String? = nil,
        lessonText: String,
        verifiedCount: Int = 0,
        violatedCount: Int = 0,
        metadataJson: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tradeId = tradeId
        self.symbol = symbol.uppercased()
        self.taxonomy = taxonomy
        self.deviationPoints = deviationPoints
        self.plannedRR = plannedRR
        self.realizedRR = realizedRR
        self.ruleBroken = ruleBroken
        self.lessonText = lessonText
        self.verifiedCount = verifiedCount
        self.violatedCount = violatedCount
        self.metadataJson = metadataJson
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Adherence rate as a percentage [0.0 ... 100.0]
    public var adherenceRate: Double {
        let total = verifiedCount + violatedCount
        guard total > 0 else { return 100.0 }
        return (Double(verifiedCount) / Double(total)) * 100.0
    }
}
