import Foundation

// MARK: - AI Tool Definitions (Module F: Tool-Using Intelligence)
/// Supported deterministic tool types available to the AI Coach.
public enum AIToolName: String, Codable, CaseIterable, Sendable {
    case queryTrades            = "query_trades"
    case queryMarketStructure   = "query_market_structure"
    case queryTradeExcursions   = "query_trade_excursions"
    case queryMemories          = "query_memories"
    case queryResearchProjects  = "query_research_projects"
    case queryEconomicCalendar  = "query_economic_calendar"
    
    public var description: String {
        switch self {
        case .queryTrades:
            return "Queries historical closed and open trades with exact mathematical metrics (Win Rate, Profit Factor, R-multiples)."
        case .queryMarketStructure:
            return "Analyzes deterministic SMC market structure (Swings, MSS, Liquidity Sweeps) on candle series."
        case .queryTradeExcursions:
            return "Computes exact Maximum Adverse Excursion (MAE) and Maximum Favorable Excursion (MFE) for a trade."
        case .queryMemories:
            return "Retrieves long-term trader memories, past failure lessons, and verified preferences."
        case .queryResearchProjects:
            return "Queries active empirical research projects, hypothesis status, and validation checkpoints."
        case .queryEconomicCalendar:
            return "Retrieves high-impact economic news releases and catalyst countdowns."
        }
    }
}

// MARK: - Tool Call Request Form
public struct AIToolCall: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: AIToolName
    public let argumentsJson: String
    
    public init(id: String = JournalIds.prefixed("tc_"), name: AIToolName, argumentsJson: String) {
        self.id = id
        self.name = name
        self.argumentsJson = argumentsJson
    }
}

// MARK: - Tool Execution Result Form
public struct AIToolResult: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let callId: String
    public let toolName: AIToolName
    public let isSuccess: Bool
    public let outputJson: String
    public let formattedMarkdown: String
    
    public init(
        id: String = JournalIds.prefixed("res_"),
        callId: String,
        toolName: AIToolName,
        isSuccess: Bool,
        outputJson: String,
        formattedMarkdown: String
    ) {
        self.id = id
        self.callId = callId
        self.toolName = toolName
        self.isSuccess = isSuccess
        self.outputJson = outputJson
        self.formattedMarkdown = formattedMarkdown
    }
}
