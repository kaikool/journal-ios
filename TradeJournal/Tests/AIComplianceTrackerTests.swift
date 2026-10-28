import XCTest
@testable import TradeJournal

final class AIComplianceTrackerTests: XCTestCase {
    
    func testTradeLessonEvaluationAdherenceRate() {
        let eval = TradeLessonEvaluation(
            tradeId: "tr_1",
            symbol: "XAUUSD",
            taxonomy: .badExecution,
            deviationPoints: Decimal(1.5),
            plannedRR: Decimal(2.0),
            realizedRR: Decimal(-1.0),
            ruleBroken: "Chasing price after breakout",
            lessonText: "Wait for M15 candle close confirmation",
            verifiedCount: 3,
            violatedCount: 1
        )
        
        XCTAssertEqual(eval.symbol, "XAUUSD")
        XCTAssertEqual(eval.taxonomy, .badExecution)
        XCTAssertEqual(eval.verifiedCount, 3)
        XCTAssertEqual(eval.violatedCount, 1)
        // 3 / (3 + 1) = 75.0%
        XCTAssertEqual(eval.adherenceRate, 75.0)
    }
    
    func testComplianceTrackerSummaryPureMath() {
        let e1 = TradeLessonEvaluation(
            tradeId: "t1",
            symbol: "EURUSD",
            taxonomy: .badExecution,
            ruleBroken: "FOMO Entry",
            lessonText: "Wait for MSS",
            verifiedCount: 2,
            violatedCount: 1
        )
        let e2 = TradeLessonEvaluation(
            tradeId: "t2",
            symbol: "EURUSD",
            taxonomy: .flawedPlan,
            ruleBroken: "Ignored HTF Order Block",
            lessonText: "Check D1 OB before entering M15",
            verifiedCount: 4,
            violatedCount: 0
        )
        let e3 = TradeLessonEvaluation(
            tradeId: "t3",
            symbol: "EURUSD",
            taxonomy: .regimeShift,
            ruleBroken: "Traded into NFP news",
            lessonText: "Check economic calendar 30m prior",
            verifiedCount: 1,
            violatedCount: 2
        )
        
        let summary = AIComplianceTracker.computeSummary(evaluations: [e1, e2, e3])
        
        XCTAssertEqual(summary.totalLessons, 3)
        XCTAssertEqual(summary.totalVerified, 7) // 2 + 4 + 1
        XCTAssertEqual(summary.totalViolated, 3) // 1 + 0 + 2
        // 7 / (7 + 3) = 70.0%
        XCTAssertEqual(summary.adherenceRate, 70.0)
        XCTAssertEqual(summary.taxonomyDistribution[.badExecution], 1)
        XCTAssertEqual(summary.taxonomyDistribution[.flawedPlan], 1)
        XCTAssertEqual(summary.taxonomyDistribution[.regimeShift], 1)
        XCTAssertEqual(summary.taxonomyDistribution[.randomLoss], 0)
        
        // Recurring violations sorted by count descending
        XCTAssertEqual(summary.recurringViolations.count, 2)
        XCTAssertEqual(summary.recurringViolations.first?.rule, "Traded into NFP news")
        XCTAssertEqual(summary.recurringViolations.first?.count, 2)
    }
    
    func testFormatComplianceForPromptZeroHardcoding() {
        let e = TradeLessonEvaluation(
            tradeId: "t1",
            symbol: "GBPUSD",
            taxonomy: .badExecution,
            ruleBroken: "Front-running candle close",
            lessonText: "Wait for close",
            verifiedCount: 4,
            violatedCount: 1
        )
        let summary = AIComplianceTracker.computeSummary(evaluations: [e])
        
        let vi = AIComplianceTracker.formatComplianceForPrompt(summary, isVi: true)
        XCTAssertTrue(vi.contains("LỊCH SỬ TUÂN THỦ KỶ LUẬT & SAI LẦM QUÁ KHỨ"))
        XCTAssertTrue(vi.contains("Front-running candle close"))
        XCTAssertTrue(vi.contains("80.0%"))
        
        let en = AIComplianceTracker.formatComplianceForPrompt(summary, isVi: false)
        XCTAssertTrue(en.contains("LESSON COMPLIANCE & HISTORICAL ERROR AUDIT"))
        XCTAssertTrue(en.contains("Front-running candle close"))
        XCTAssertTrue(en.contains("80.0%"))
    }
    
    func testBidirectionalConversionWithAIMemoryRecord() {
        let eval = TradeLessonEvaluation(
            id: "les_test_123",
            tradeId: "tr_456",
            symbol: "USDJPY",
            taxonomy: .flawedPlan,
            deviationPoints: Decimal(2.5),
            plannedRR: Decimal(3.0),
            realizedRR: Decimal(-1.0),
            ruleBroken: "Counter-trend into H4 Supply",
            lessonText: "Do not short into H4 demand",
            verifiedCount: 5,
            violatedCount: 1
        )
        
        let memory = AIMemoryRecord.from(evaluation: eval)
        XCTAssertEqual(memory.id, "les_test_123")
        XCTAssertEqual(memory.category, .failure)
        XCTAssertEqual(memory.symbol, "USDJPY")
        XCTAssertEqual(memory.status, .verified) // 5/6 = 83.3% >= 80%
        
        let reconstructed = memory.toTradeLessonEvaluation()
        XCTAssertEqual(reconstructed.id, eval.id)
        XCTAssertEqual(reconstructed.tradeId, eval.tradeId)
        XCTAssertEqual(reconstructed.symbol, eval.symbol)
        XCTAssertEqual(reconstructed.taxonomy, .flawedPlan)
        XCTAssertEqual(reconstructed.deviationPoints, eval.deviationPoints)
        XCTAssertEqual(reconstructed.plannedRR, eval.plannedRR)
        XCTAssertEqual(reconstructed.realizedRR, eval.realizedRR)
        XCTAssertEqual(reconstructed.ruleBroken, eval.ruleBroken)
        XCTAssertEqual(reconstructed.lessonText, eval.lessonText)
        XCTAssertEqual(reconstructed.verifiedCount, 5)
        XCTAssertEqual(reconstructed.violatedCount, 1)
    }
}
