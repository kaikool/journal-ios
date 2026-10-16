import XCTest
@testable import TradeJournal

/// Port 1:1 từ `packages/core/tests/analysis.test.ts`.
final class AnalysisTests: XCTestCase {
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private func parseDate(_ iso: String) -> Date {
        if let d = isoFormatter.date(from: iso) { return d }
        return ISO8601DateFormatter().date(from: iso)!
    }
    
    private func createSampleTrade() -> Trade {
        let executions = [
            Execution(
                id: "e1",
                accountId: "acct-1",
                symbol: "ES",
                side: .buy,
                quantity: 2,
                price: 5000,
                fee: 0,
                executedAt: parseDate("2026-03-09T03:30:00Z"),
                assetClass: "futures"
            ),
            Execution(
                id: "e2",
                accountId: "acct-1",
                symbol: "ES",
                side: .sell,
                quantity: 2,
                price: 5010,
                fee: 0,
                executedAt: parseDate("2026-03-09T04:30:00Z"),
                assetClass: "futures"
            )
        ]
        var trips = TradeReconstructionEngine.buildRoundTrips(
            executions: executions,
            options: .init(method: .fifo, multipliers: ["ES": 50])
        )
        var t = trips[0]
        t.stopLoss = 4995
        t.profitTarget = 5015
        t.tags = ["A+", "trend"]
        t.rating = 4
        t.reviewedAt = Date()
        t.playbookId = "orb"
        return t
    }
    
    func testPointValueForFuturesRAndInvalidRisk() {
        let t = createSampleTrade()
        XCTAssertEqual(TradeAnalysisEngine.tradeRisk(trade: t), 500)
        XCTAssertEqual(TradeAnalysisEngine.tradeR(trade: t)!, 2.0, accuracy: 1e-9)
        XCTAssertEqual(TradeAnalysisEngine.plannedR(trade: t)!, 3.0, accuracy: 1e-9)
        
        var noMult = t
        noMult.contractMultiplier = nil
        XCTAssertNil(TradeAnalysisEngine.tradeR(trade: noMult))
        
        var badStop = t
        badStop.stopLoss = 5001 // Stop above entry for a long trade
        XCTAssertNil(TradeAnalysisEngine.tradeRisk(trade: badStop))
        
        var openTrade = t
        openTrade.status = .open
        XCTAssertNil(TradeAnalysisEngine.tradeR(trade: openTrade))
    }
    
    func testShortRiskAndRewardDirection() {
        var t = createSampleTrade()
        t.direction = .short
        t.stopLoss = 5005
        t.profitTarget = 4985
        t.netPnl = 1000 // In the JS test, gross profit for short when price falls
        
        XCTAssertEqual(TradeAnalysisEngine.tradeR(trade: t)!, 2.0, accuracy: 1e-9)
        XCTAssertEqual(TradeAnalysisEngine.plannedR(trade: t)!, 3.0, accuracy: 1e-9)
        
        var invalidShort = t
        invalidShort.stopLoss = 5005
        invalidShort.profitTarget = 5010 // Target above entry for short
        XCTAssertNil(TradeAnalysisEngine.plannedR(trade: invalidShort))
    }
    
    func testMatchesFiltersAndNumericBounds() {
        let t = createSampleTrade()
        
        var filters: AnalysisFilters = [
            "symbol": "es",
            "tag": "A+,trend",
            "playbookId": "orb",
            "reviewed": "yes",
            "quantityMin": "2",
            "quantityMax": "2",
            "rMin": "2",
            "plannedRMin": "3",
            "ratingMin": "4",
            "durationMin": "60"
        ]
        XCTAssertTrue(TradeAnalysisEngine.matchesFilters(trade: t, filters: filters))
        
        filters["excludeSymbol"] = "ES"
        XCTAssertFalse(TradeAnalysisEngine.matchesFilters(trade: t, filters: filters))
        
        filters.removeValue(forKey: "excludeSymbol")
        filters["ratingMin"] = "5"
        XCTAssertFalse(TradeAnalysisEngine.matchesFilters(trade: t, filters: filters))
        
        filters["ratingMin"] = "4"
        filters["reviewed"] = "no"
        XCTAssertFalse(TradeAnalysisEngine.matchesFilters(trade: t, filters: filters))
    }
    
    func testDimensionKeys() {
        let t = createSampleTrade()
        let tags = TradeAnalysisEngine.dimensionKeys(trade: t, dimension: .tag, timeZone: "UTC")
        XCTAssertEqual(tags, ["A+", "trend"])
        
        let symbol = TradeAnalysisEngine.dimensionKeys(trade: t, dimension: .symbol, timeZone: "UTC")
        XCTAssertEqual(symbol, ["ES"])
        
        let direction = TradeAnalysisEngine.dimensionKeys(trade: t, dimension: .direction, timeZone: "UTC")
        XCTAssertEqual(direction, ["long"])
    }
}
