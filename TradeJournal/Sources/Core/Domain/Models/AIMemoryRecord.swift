import Foundation

// MARK: - AI Memory Category
/// 5 distinct classes of long-term memory defined in AI Coach Architecture Module A
public enum AIMemoryCategory: String, Codable, CaseIterable, Sendable {
    case preference = "preference" // User preferences, trading habits, guidelines, bounds
    case decision = "decision"     // Tactical commitments, trade entries, rationales
    case research = "research"     // Hypotheses, ongoing tests, empirical conclusions
    case failure = "failure"       // Repetitive leaks, post-loss forensic lessons, remedies
    case context = "context"       // Active projects, current focus, upcoming milestones
    
    public var localizedTitle: String {
        switch self {
        case .preference: return "Preferences & Rules"
        case .decision:   return "Decisions & Commitments"
        case .research:   return "Research & Hypotheses"
        case .failure:    return "Lessons & Mistakes"
        case .context:    return "Operating Context"
        }
    }
}

// MARK: - AI Memory Status
public enum AIMemoryStatus: String, Codable, CaseIterable, Sendable {
    case active = "active"         // In active application
    case verified = "verified"     // Empirically confirmed by subsequent trading data
    case deprecated = "deprecated" // Outdated or superseded by a newer rule
    case refuted = "refuted"       // Disproven by live market testing
}

// MARK: - AI Memory Source Type
public enum AIMemorySourceType: String, Codable, CaseIterable, Sendable {
    case preTrade = "pre_trade"
    case tradeAudit = "trade_audit"
    case chat = "chat"
    case research = "research"
    case manual = "manual"
}

// MARK: - AI Memory Record
/// Unified domain model for persistent, cross-session long-term AI memory.
public struct AIMemoryRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var category: AIMemoryCategory
    public var symbol: String?
    public var title: String
    public var content: String
    public var confidence: Double // 0.00 to 1.00
    public var status: AIMemoryStatus
    public var supersededBy: String?
    public var sourceType: AIMemorySourceType
    public var sourceId: String? // Linked trade key, order ticket, or research project id
    public var metadataJson: String
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = JournalIds.newId(),
        category: AIMemoryCategory,
        symbol: String? = nil,
        title: String,
        content: String,
        confidence: Double = 1.0,
        status: AIMemoryStatus = .active,
        supersededBy: String? = nil,
        sourceType: AIMemorySourceType = .manual,
        sourceId: String? = nil,
        metadataJson: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.symbol = symbol?.uppercased()
        self.title = title
        self.content = content
        self.confidence = max(0.0, min(1.0, confidence))
        self.status = status
        self.supersededBy = supersededBy
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.metadataJson = metadataJson
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Conversion from TraderAILesson
    public static func from(lesson: TraderAILesson) -> AIMemoryRecord {
        let meta: [String: String] = [
            "mistakeTag": lesson.mistakeTag ?? "",
            "context": lesson.context ?? ""
        ]
        let metaJson = (try? String(data: JSONEncoder().encode(meta), encoding: .utf8)) ?? "{}"
        
        return AIMemoryRecord(
            id: lesson.id,
            category: .failure,
            symbol: lesson.symbol,
            title: lesson.setupType,
            content: lesson.lesson,
            confidence: 1.0,
            status: .active,
            sourceType: .tradeAudit,
            metadataJson: metaJson,
            createdAt: lesson.timestamp,
            updatedAt: lesson.timestamp
        )
    }
    
    // MARK: - Conversion to TraderAILesson
    public func toTraderAILesson() -> TraderAILesson {
        var mistakeTag: String? = nil
        var ctx: String? = nil
        if let data = metadataJson.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            mistakeTag = dict["mistakeTag"]?.isEmpty == false ? dict["mistakeTag"] : nil
            ctx = dict["context"]?.isEmpty == false ? dict["context"] : nil
        }
        
        return TraderAILesson(
            id: id,
            symbol: symbol,
            timestamp: createdAt,
            setupType: title,
            mistakeTag: mistakeTag,
            lesson: content,
            context: ctx
        )
    }
    
    // MARK: - Conversion from AdvisorCommitmentRecord
    public static func from(commitment: AdvisorCommitmentRecord) -> AIMemoryRecord {
        let meta: [String: String] = [
            "bias": commitment.bias,
            "plannedEntry": commitment.plannedEntry ?? "",
            "invalidationSL": commitment.invalidationSL ?? "",
            "targetTP": commitment.targetTP ?? "",
            "triggerCondition": commitment.triggerCondition ?? "",
            "linkedOrderTicket": commitment.linkedOrderTicket ?? "",
            "linkedTradeKey": commitment.linkedTradeKey ?? ""
        ]
        let metaJson = (try? String(data: JSONEncoder().encode(meta), encoding: .utf8)) ?? "{}"
        
        return AIMemoryRecord(
            id: commitment.id,
            category: .decision,
            symbol: commitment.symbol,
            title: "\(commitment.symbol) [\(commitment.bias)] Pre-Trade Plan",
            content: commitment.thesisSummary,
            confidence: 1.0,
            status: .active,
            sourceType: .preTrade,
            sourceId: commitment.linkedTradeKey ?? commitment.linkedOrderTicket,
            metadataJson: metaJson,
            createdAt: commitment.timestamp,
            updatedAt: commitment.timestamp
        )
    }
    
    // MARK: - Conversion to AdvisorCommitmentRecord
    public func toAdvisorCommitmentRecord() -> AdvisorCommitmentRecord? {
        guard category == .decision else { return nil }
        var bias = "FLAT"
        var plannedEntry: String? = nil
        var invalidationSL: String? = nil
        var targetTP: String? = nil
        var triggerCondition: String? = nil
        var linkedOrderTicket: String? = nil
        var linkedTradeKey: String? = nil
        
        if let data = metadataJson.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            bias = dict["bias"] ?? "FLAT"
            plannedEntry = dict["plannedEntry"]?.isEmpty == false ? dict["plannedEntry"] : nil
            invalidationSL = dict["invalidationSL"]?.isEmpty == false ? dict["invalidationSL"] : nil
            targetTP = dict["targetTP"]?.isEmpty == false ? dict["targetTP"] : nil
            triggerCondition = dict["triggerCondition"]?.isEmpty == false ? dict["triggerCondition"] : nil
            linkedOrderTicket = dict["linkedOrderTicket"]?.isEmpty == false ? dict["linkedOrderTicket"] : nil
            linkedTradeKey = dict["linkedTradeKey"]?.isEmpty == false ? dict["linkedTradeKey"] : nil
        }
        
        return AdvisorCommitmentRecord(
            id: id,
            symbol: symbol ?? "MARKET",
            timestamp: createdAt,
            bias: bias,
            plannedEntry: plannedEntry,
            invalidationSL: invalidationSL,
            targetTP: targetTP,
            triggerCondition: triggerCondition,
            thesisSummary: content,
            linkedOrderTicket: linkedOrderTicket,
            linkedTradeKey: linkedTradeKey
        )
    }
    
    // MARK: - Conversion from TradeLessonEvaluation (Module D)
    public static func from(evaluation: TradeLessonEvaluation) -> AIMemoryRecord {
        let meta: [String: String] = [
            "taxonomy": evaluation.taxonomy.rawValue,
            "ruleBroken": evaluation.ruleBroken ?? "",
            "deviationPoints": evaluation.deviationPoints.map { "\($0)" } ?? "",
            "plannedRR": evaluation.plannedRR.map { "\($0)" } ?? "",
            "realizedRR": evaluation.realizedRR.map { "\($0)" } ?? "",
            "verifiedCount": "\(evaluation.verifiedCount)",
            "violatedCount": "\(evaluation.violatedCount)"
        ]
        let metaJson = (try? String(data: JSONEncoder().encode(meta), encoding: .utf8)) ?? "{}"
        
        return AIMemoryRecord(
            id: evaluation.id,
            category: .failure,
            symbol: evaluation.symbol,
            title: evaluation.ruleBroken ?? evaluation.taxonomy.titleEn,
            content: evaluation.lessonText,
            confidence: 1.0,
            status: evaluation.adherenceRate >= 80 ? .verified : .active,
            sourceType: .tradeAudit,
            sourceId: evaluation.tradeId,
            metadataJson: metaJson,
            createdAt: evaluation.createdAt,
            updatedAt: evaluation.updatedAt
        )
    }
    
    // MARK: - Conversion to TradeLessonEvaluation
    public func toTradeLessonEvaluation() -> TradeLessonEvaluation {
        var tax: TradeFailureTaxonomy = .unclassified
        var dev: Decimal? = nil
        var pRR: Decimal? = nil
        var rRR: Decimal? = nil
        var rule: String? = nil
        var ver: Int = 0
        var vio: Int = 0
        
        if let data = metadataJson.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            if let tStr = dict["taxonomy"] { tax = TradeFailureTaxonomy(rawValue: tStr) ?? .unclassified }
            if let dStr = dict["deviationPoints"], let d = Decimal(string: dStr) { dev = d }
            if let pStr = dict["plannedRR"], let p = Decimal(string: pStr) { pRR = p }
            if let rStr = dict["realizedRR"], let r = Decimal(string: rStr) { rRR = r }
            rule = dict["ruleBroken"]?.isEmpty == false ? dict["ruleBroken"] : nil
            if let vStr = dict["verifiedCount"], let v = Int(vStr) { ver = v }
            if let viStr = dict["violatedCount"], let vi = Int(viStr) { vio = vi }
        }
        
        return TradeLessonEvaluation(
            id: id,
            tradeId: sourceId ?? "",
            symbol: symbol ?? "",
            taxonomy: tax,
            deviationPoints: dev,
            plannedRR: pRR,
            realizedRR: rRR,
            ruleBroken: rule ?? title,
            lessonText: content,
            verifiedCount: ver,
            violatedCount: vio,
            metadataJson: metadataJson,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
