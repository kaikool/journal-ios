import XCTest
@testable import TradeJournal

final class AIResearchWorkspaceTests: XCTestCase {
    
    func testResearchProjectInitializationAndCheckpoints() {
        let criteria = AIResearchSampleCriteria(
            symbols: ["XAUUSD", "EURUSD"],
            timeframes: ["H4", "M15"],
            playbook: "London Sweep",
            minSampleSize: 30
        )
        
        var project = AIResearchProject(
            id: "res_test_1",
            title: "London Open Liquidity Sweep Study",
            hypothesis: "M15 wick sweep of Asian high before 09:00 UTC yields > 2.0 RR",
            status: .active,
            criteria: criteria
        )
        
        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(project.criteria.symbols, ["XAUUSD", "EURUSD"])
        XCTAssertEqual(project.sampleCount, 0)
        XCTAssertNil(project.winRate)
        
        let checkpoint = AIResearchCheckpoint(
            sampleCount: 15,
            winRate: 66.7,
            profitFactor: 2.15,
            avgMAE: Decimal(12.5),
            avgMFE: Decimal(38.0),
            notes: "First 15 trades verified; high consistency during high volatility days."
        )
        
        project.checkpoints.append(checkpoint)
        project.sampleCount = checkpoint.sampleCount
        project.winRate = checkpoint.winRate
        project.profitFactor = checkpoint.profitFactor
        
        XCTAssertEqual(project.checkpoints.count, 1)
        XCTAssertEqual(project.sampleCount, 15)
        XCTAssertEqual(project.winRate, 66.7)
        XCTAssertEqual(project.profitFactor, 2.15)
    }
    
    func testFormatProjectsForPromptZeroHardcoding() {
        let criteria = AIResearchSampleCriteria(
            symbols: ["BTCUSD"],
            timeframes: ["M15"],
            minSampleSize: 25
        )
        let chk = AIResearchCheckpoint(
            sampleCount: 10,
            winRate: 60.0,
            profitFactor: 1.85,
            notes: "Observed clean reaction at Monday high"
        )
        let project = AIResearchProject(
            id: "res_btc",
            title: "BTC Monday Range Breakout",
            hypothesis: "Sweep of Monday low during NY session produces continuation",
            status: .active,
            criteria: criteria,
            checkpoints: [chk],
            sampleCount: 10,
            winRate: 60.0,
            profitFactor: 1.85
        )
        
        AIResearchWorkspaceEngine.shared.createProject(
            title: project.title,
            hypothesis: project.hypothesis,
            criteria: project.criteria
        )
        AIResearchWorkspaceEngine.shared.addCheckpoint(projectId: project.id, checkpoint: chk)
        
        let promptVi = AIResearchWorkspaceEngine.shared.formatProjectsForPrompt(symbol: "BTCUSD", isVi: true)
        XCTAssertTrue(promptVi.contains("DỰ ÁN NGHIÊN CỨU DÀI HẠN ĐANG TRIỂN KHAI"))
        
        let promptEn = AIResearchWorkspaceEngine.shared.formatProjectsForPrompt(symbol: "BTCUSD", isVi: false)
        XCTAssertTrue(promptEn.contains("ACTIVE RESEARCH WORKSPACE & HYPOTHESIS TESTING"))
    }
    
    func testSupabaseAIResearchProjectRecordBidirectional() {
        let criteria = AIResearchSampleCriteria(
            symbols: ["US500"],
            timeframes: ["H1"],
            minSampleSize: 40
        )
        let original = AIResearchProject(
            id: "res_dto_test",
            title: "US500 NY Open Gap Fill",
            hypothesis: "Unfilled opening gap fills 70% of the time before 16:00 UTC",
            status: .validated,
            criteria: criteria,
            sampleCount: 40,
            winRate: 72.5,
            profitFactor: 2.45,
            conclusion: "Empirically validated over 40 samples"
        )
        
        let dto = SupabaseAIResearchProjectRecord(project: original)
        XCTAssertEqual(dto.id, "res_dto_test")
        XCTAssertEqual(dto.status, "validated")
        XCTAssertEqual(dto.sampleCount, 40)
        XCTAssertEqual(dto.conclusion, "Empirically validated over 40 samples")
        
        let reconstructed = dto.toProject()
        XCTAssertEqual(reconstructed.id, original.id)
        XCTAssertEqual(reconstructed.title, original.title)
        XCTAssertEqual(reconstructed.hypothesis, original.hypothesis)
        XCTAssertEqual(reconstructed.status, .validated)
        XCTAssertEqual(reconstructed.criteria.symbols, ["US500"])
        XCTAssertEqual(reconstructed.sampleCount, 40)
        XCTAssertEqual(reconstructed.winRate, 72.5)
        XCTAssertEqual(reconstructed.profitFactor, 2.45)
        XCTAssertEqual(reconstructed.conclusion, original.conclusion)
    }
}
