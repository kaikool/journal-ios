import XCTest
@testable import TradeJournal

final class AIToolDispatcherTests: XCTestCase {
    
    func testToolDefinitionsAndDescriptions() {
        XCTAssertEqual(AIToolName.allCases.count, 6)
        for tool in AIToolName.allCases {
            XCTAssertFalse(tool.description.isEmpty)
        }
    }
    
    func testQueryMemoriesToolExecution() async {
        // Save a test memory
        let mem = AIMemoryRecord(
            category: .preference,
            symbol: "EURUSD",
            title: "Test Pref",
            content: "Never risk > 1%",
            confidence: 1.0,
            status: .active,
            sourceType: .manual
        )
        AIAdvisorMemoryEngine.shared.saveMemory(mem)
        
        let call = AIToolCall(
            name: .queryMemories,
            argumentsJson: "{\"symbol\":\"EURUSD\",\"maxItems\":5}"
        )
        let result = await AIToolDispatcher.execute(call: call)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.toolName, .queryMemories)
        XCTAssertTrue(result.formattedMarkdown.contains("EURUSD"))
        XCTAssertTrue(result.formattedMarkdown.contains("Test Pref"))
    }
    
    func testQueryResearchProjectsToolExecution() async {
        AIResearchWorkspaceEngine.shared.createProject(
            title: "H4 Liquidity Study",
            hypothesis: "Sweeps produce 2R targets",
            criteria: AIResearchSampleCriteria(symbols: ["XAUUSD"], minSampleSize: 20)
        )
        
        let call = AIToolCall(
            name: .queryResearchProjects,
            argumentsJson: "{\"symbol\":\"XAUUSD\"}"
        )
        let result = await AIToolDispatcher.execute(call: call)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.toolName, .queryResearchProjects)
        XCTAssertTrue(result.formattedMarkdown.contains("H4 Liquidity Study"))
    }
    
    func testQueryTradesToolExecutionWithEmptyDataset() async {
        let call = AIToolCall(
            name: .queryTrades,
            argumentsJson: "{\"symbol\":\"XAUUSD\",\"direction\":\"long\"}"
        )
        let result = await AIToolDispatcher.execute(call: call)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.toolName, .queryTrades)
        XCTAssertTrue(result.formattedMarkdown.contains("Tổng số lệnh"))
    }
    
    func testFormatToolCapabilitiesZeroHardcoding() {
        let vi = AIPromptBuilder.formatToolCapabilities(isVi: true)
        XCTAssertTrue(vi.contains("CÔNG CỤ TÍNH TOÁN XÁC THỰC SỐ LIỆU"))
        XCTAssertTrue(vi.contains("query_trades"))
        XCTAssertTrue(vi.contains("query_market_structure"))
        
        let en = AIPromptBuilder.formatToolCapabilities(isVi: false)
        XCTAssertTrue(en.contains("DETERMINISTIC FACTUAL TOOLS"))
        XCTAssertTrue(en.contains("query_trades"))
    }
}
