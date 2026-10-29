import Foundation

// MARK: - AI Research Project Status
public enum AIResearchProjectStatus: String, Codable, CaseIterable, Sendable {
    case active       = "active"
    case paused       = "paused"
    case validated    = "validated"
    case invalidated  = "invalidated"
    case archived     = "archived"
    
    public var titleVi: String {
        switch self {
        case .active:      return "Đang nghiên cứu"
        case .paused:      return "Tạm dừng"
        case .validated:   return "Đã xác nhận"
        case .invalidated: return "Đã bác bỏ"
        case .archived:    return "Lưu trữ"
        }
    }
    
    public var titleEn: String {
        switch self {
        case .active:      return "Active Research"
        case .paused:      return "Paused"
        case .validated:   return "Validated"
        case .invalidated: return "Invalidated"
        case .archived:    return "Archived"
        }
    }
}

// MARK: - Sample Selection Criteria Form
public struct AIResearchSampleCriteria: Codable, Equatable, Sendable {
    public var symbols: [String]
    public var timeframes: [String]
    public var playbook: String?
    public var startDate: Date?
    public var endDate: Date?
    public var minSampleSize: Int
    
    public init(
        symbols: [String] = [],
        timeframes: [String] = [],
        playbook: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        minSampleSize: Int = 20
    ) {
        self.symbols = symbols.map { $0.uppercased() }
        self.timeframes = timeframes
        self.playbook = playbook
        self.startDate = startDate
        self.endDate = endDate
        self.minSampleSize = minSampleSize
    }
}

// MARK: - Research Checkpoint Form
public struct AIResearchCheckpoint: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let sampleCount: Int
    public let winRate: Double?
    public let profitFactor: Double?
    public let avgMAE: Decimal?
    public let avgMFE: Decimal?
    public let notes: String
    
    public init(
        id: String = JournalIds.prefixed("chk_"),
        timestamp: Date = Date(),
        sampleCount: Int,
        winRate: Double? = nil,
        profitFactor: Double? = nil,
        avgMAE: Decimal? = nil,
        avgMFE: Decimal? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sampleCount = sampleCount
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.avgMAE = avgMAE
        self.avgMFE = avgMFE
        self.notes = notes
    }
}

// MARK: - AI Research Project Model
/// Structured research workspace enabling multi-session, multi-week hypothesis validation.
/// Zero hardcoded conclusions; the form stores objective metrics, while AI interprets statistical significance.
public struct AIResearchProject: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var hypothesis: String
    public var status: AIResearchProjectStatus
    public var criteria: AIResearchSampleCriteria
    public var checkpoints: [AIResearchCheckpoint]
    public var sampleCount: Int
    public var winRate: Double?
    public var profitFactor: Double?
    public var conclusion: String?
    public var metadataJson: String
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = JournalIds.prefixed("res_"),
        title: String,
        hypothesis: String,
        status: AIResearchProjectStatus = .active,
        criteria: AIResearchSampleCriteria = AIResearchSampleCriteria(),
        checkpoints: [AIResearchCheckpoint] = [],
        sampleCount: Int = 0,
        winRate: Double? = nil,
        profitFactor: Double? = nil,
        conclusion: String? = nil,
        metadataJson: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.hypothesis = hypothesis
        self.status = status
        self.criteria = criteria
        self.checkpoints = checkpoints
        self.sampleCount = sampleCount
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.conclusion = conclusion
        self.metadataJson = metadataJson
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
