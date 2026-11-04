import Foundation

// MARK: - Supabase AI Memory, Lesson Evaluation & Research DTOs
// MARK: - PostgREST AI Memory Record DTO
public struct SupabaseAIMemoryRecord: Codable {
    public let id: String
    public let category: String
    public let symbol: String?
    public let title: String
    public let content: String
    public let confidence: Double
    public let status: String
    public let supersededBy: String?
    public let sourceType: String
    public let sourceId: String?
    public let metadataJson: String
    public let createdAt: String
    public let updatedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, category, symbol, title, content, confidence, status
        case supersededBy = "superseded_by"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(record: AIMemoryRecord) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = record.id
        self.category = record.category.rawValue
        self.symbol = record.symbol
        self.title = record.title
        self.content = record.content
        self.confidence = record.confidence
        self.status = record.status.rawValue
        self.supersededBy = record.supersededBy
        self.sourceType = record.sourceType.rawValue
        self.sourceId = record.sourceId
        self.metadataJson = record.metadataJson
        self.createdAt = iso.string(from: record.createdAt)
        self.updatedAt = iso.string(from: record.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.category = c.decodeString(forKeys: ["category"]) ?? "preference"
        self.symbol = c.decodeString(forKeys: ["symbol"])
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.content = c.decodeString(forKeys: ["content"]) ?? ""
        self.confidence = c.decodeDouble(forKeys: ["confidence"]) ?? 1.0
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.supersededBy = c.decodeString(forKeys: ["superseded_by", "supersededBy"])
        self.sourceType = c.decodeString(forKeys: ["source_type", "sourceType"]) ?? "manual"
        self.sourceId = c.decodeString(forKeys: ["source_id", "sourceId"])
        self.metadataJson = c.decodeString(forKeys: ["metadata_json", "metadataJson"]) ?? "{}"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"]) ?? JournalIds.nowIso()
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(supersededBy, forKey: .supersededBy)
        try c.encode(sourceType, forKey: .sourceType)
        try c.encodeIfPresent(sourceId, forKey: .sourceId)
        try c.encode(metadataJson, forKey: .metadataJson)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
    
    public func toRecord() -> AIMemoryRecord {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let created = iso.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) ?? Date()
        let updated = iso.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt) ?? Date()
        
        return AIMemoryRecord(
            id: id,
            category: AIMemoryCategory(rawValue: category) ?? .preference,
            symbol: symbol,
            title: title,
            content: content,
            confidence: confidence,
            status: AIMemoryStatus(rawValue: status) ?? .active,
            supersededBy: supersededBy,
            sourceType: AIMemorySourceType(rawValue: sourceType) ?? .manual,
            sourceId: sourceId,
            metadataJson: metadataJson,
            createdAt: created,
            updatedAt: updated
        )
    }
}

// MARK: - PostgREST DTO for trade_lesson_evaluations
public struct SupabaseTradeLessonEvaluationRecord: Codable, Sendable {
    public let id: String
    public let tradeId: String
    public let symbol: String
    public let taxonomy: String
    public let deviationPoints: Decimal?
    public let plannedRR: Decimal?
    public let realizedRR: Decimal?
    public let ruleBroken: String?
    public let lessonText: String
    public let verifiedCount: Int
    public let violatedCount: Int
    public let metadataJson: String
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, symbol, taxonomy
        case tradeId = "trade_id"
        case deviationPoints = "deviation_points"
        case plannedRR = "planned_rr"
        case realizedRR = "realized_rr"
        case ruleBroken = "rule_broken"
        case lessonText = "lesson_text"
        case verifiedCount = "verified_count"
        case violatedCount = "violated_count"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(evaluation: TradeLessonEvaluation) {
        self.id = evaluation.id
        self.tradeId = evaluation.tradeId
        self.symbol = evaluation.symbol
        self.taxonomy = evaluation.taxonomy.rawValue
        self.deviationPoints = evaluation.deviationPoints
        self.plannedRR = evaluation.plannedRR
        self.realizedRR = evaluation.realizedRR
        self.ruleBroken = evaluation.ruleBroken
        self.lessonText = evaluation.lessonText
        self.verifiedCount = evaluation.verifiedCount
        self.violatedCount = evaluation.violatedCount
        self.metadataJson = evaluation.metadataJson
        self.createdAt = ISO8601DateFormatter().string(from: evaluation.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: evaluation.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? JournalIds.prefixed("les_")
        self.tradeId = c.decodeString(forKeys: ["trade_id", "tradeId"]) ?? ""
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? ""
        self.taxonomy = c.decodeString(forKeys: ["taxonomy"]) ?? "unclassified"
        self.deviationPoints = c.decodeDecimal(forKeys: ["deviation_points", "deviationPoints"])
        self.plannedRR = c.decodeDecimal(forKeys: ["planned_rr", "plannedRR"])
        self.realizedRR = c.decodeDecimal(forKeys: ["realized_rr", "realizedRR"])
        self.ruleBroken = c.decodeString(forKeys: ["rule_broken", "ruleBroken"])
        self.lessonText = c.decodeString(forKeys: ["lesson_text", "lessonText"]) ?? ""
        self.verifiedCount = c.decodeInt(forKeys: ["verified_count", "verifiedCount"]) ?? 0
        self.violatedCount = c.decodeInt(forKeys: ["violated_count", "violatedCount"]) ?? 0
        self.metadataJson = c.decodeString(forKeys: ["metadata_json", "metadataJson"]) ?? "{}"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tradeId, forKey: .tradeId)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(taxonomy, forKey: .taxonomy)
        try c.encodeIfPresent(deviationPoints.map { supabaseDecimalString($0) }, forKey: .deviationPoints)
        try c.encodeIfPresent(plannedRR.map { supabaseDecimalString($0) }, forKey: .plannedRR)
        try c.encodeIfPresent(realizedRR.map { supabaseDecimalString($0) }, forKey: .realizedRR)
        try c.encodeIfPresent(ruleBroken, forKey: .ruleBroken)
        try c.encode(lessonText, forKey: .lessonText)
        try c.encode(verifiedCount, forKey: .verifiedCount)
        try c.encode(violatedCount, forKey: .violatedCount)
        try c.encode(metadataJson, forKey: .metadataJson)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toEvaluation() -> TradeLessonEvaluation {
        let formatter = ISO8601DateFormatter()
        let cDate = createdAt.flatMap { formatter.date(from: $0) } ?? Date()
        let uDate = updatedAt.flatMap { formatter.date(from: $0) } ?? Date()
        return TradeLessonEvaluation(
            id: id,
            tradeId: tradeId,
            symbol: symbol,
            taxonomy: TradeFailureTaxonomy(rawValue: taxonomy) ?? .unclassified,
            deviationPoints: deviationPoints,
            plannedRR: plannedRR,
            realizedRR: realizedRR,
            ruleBroken: ruleBroken,
            lessonText: lessonText,
            verifiedCount: verifiedCount,
            violatedCount: violatedCount,
            metadataJson: metadataJson,
            createdAt: cDate,
            updatedAt: uDate
        )
    }
}

// MARK: - PostgREST DTO for ai_research_projects (Module E)
public struct SupabaseAIResearchProjectRecord: Codable, Sendable {
    public let id: String
    public let title: String
    public let hypothesis: String
    public let status: String
    public let sampleCriteriaJson: String
    public let sampleCount: Int
    public let winRate: Decimal?
    public let profitFactor: Decimal?
    public let conclusion: String?
    public let metadataJson: String
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, title, hypothesis, status, conclusion
        case sampleCriteriaJson = "sample_criteria_json"
        case sampleCount = "sample_count"
        case winRate = "win_rate"
        case profitFactor = "profit_factor"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(project: AIResearchProject) {
        self.id = project.id
        self.title = project.title
        self.hypothesis = project.hypothesis
        self.status = project.status.rawValue
        
        let encoder = JSONEncoder()
        let criteriaData = (try? encoder.encode(project.criteria)) ?? Data()
        self.sampleCriteriaJson = String(data: criteriaData, encoding: .utf8) ?? "{}"
        
        self.sampleCount = project.sampleCount
        self.winRate = project.winRate.map { Decimal($0) }
        self.profitFactor = project.profitFactor.map { Decimal($0) }
        self.conclusion = project.conclusion
        
        // Encode checkpoints into metadataJson if needed
        var metaDict: [String: String] = [:]
        if let checkpointsData = try? encoder.encode(project.checkpoints),
           let chkStr = String(data: checkpointsData, encoding: .utf8) {
            metaDict["checkpoints"] = chkStr
        }
        let metaData = (try? encoder.encode(metaDict)) ?? Data()
        self.metadataJson = String(data: metaData, encoding: .utf8) ?? "{}"
        
        self.createdAt = ISO8601DateFormatter().string(from: project.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: project.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? JournalIds.prefixed("res_")
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.hypothesis = c.decodeString(forKeys: ["hypothesis"]) ?? ""
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.sampleCriteriaJson = c.decodeString(forKeys: ["sample_criteria_json", "sampleCriteriaJson"]) ?? "{}"
        self.sampleCount = c.decodeInt(forKeys: ["sample_count", "sampleCount"]) ?? 0
        self.winRate = c.decodeDecimal(forKeys: ["win_rate", "winRate"])
        self.profitFactor = c.decodeDecimal(forKeys: ["profit_factor", "profitFactor"])
        self.conclusion = c.decodeString(forKeys: ["conclusion"])
        self.metadataJson = c.decodeString(forKeys: ["metadata_json", "metadataJson"]) ?? "{}"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(hypothesis, forKey: .hypothesis)
        try c.encode(status, forKey: .status)
        try c.encode(sampleCriteriaJson, forKey: .sampleCriteriaJson)
        try c.encode(sampleCount, forKey: .sampleCount)
        try c.encodeIfPresent(winRate.map { supabaseDecimalString($0) }, forKey: .winRate)
        try c.encodeIfPresent(profitFactor.map { supabaseDecimalString($0) }, forKey: .profitFactor)
        try c.encodeIfPresent(conclusion, forKey: .conclusion)
        try c.encode(metadataJson, forKey: .metadataJson)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toProject() -> AIResearchProject {
        let formatter = ISO8601DateFormatter()
        let cDate = createdAt.flatMap { formatter.date(from: $0) } ?? Date()
        let uDate = updatedAt.flatMap { formatter.date(from: $0) } ?? Date()
        
        let decoder = JSONDecoder()
        var criteria = AIResearchSampleCriteria()
        if let cData = sampleCriteriaJson.data(using: .utf8),
           let decoded = try? decoder.decode(AIResearchSampleCriteria.self, from: cData) {
            criteria = decoded
        }
        
        var chks: [AIResearchCheckpoint] = []
        if let mData = metadataJson.data(using: .utf8),
           let metaDict = try? decoder.decode([String: String].self, from: mData),
           let chkStr = metaDict["checkpoints"],
           let chkData = chkStr.data(using: .utf8),
           let decodedChks = try? decoder.decode([AIResearchCheckpoint].self, from: chkData) {
            chks = decodedChks
        }
        
        let wrDouble = winRate.map { NSDecimalNumber(decimal: $0).doubleValue }
        let pfDouble = profitFactor.map { NSDecimalNumber(decimal: $0).doubleValue }
        
        return AIResearchProject(
            id: id,
            title: title,
            hypothesis: hypothesis,
            status: AIResearchProjectStatus(rawValue: status) ?? .active,
            criteria: criteria,
            checkpoints: chks,
            sampleCount: sampleCount,
            winRate: wrDouble,
            profitFactor: pfDouble,
            conclusion: conclusion,
            metadataJson: metadataJson,
            createdAt: cDate,
            updatedAt: uDate
        )
    }
}