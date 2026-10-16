import XCTest
@testable import TradeJournalKit

final class DomainEngineTests: XCTestCase {
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private func parseDate(_ iso: String) -> Date {
        if let d = isoFormatter.date(from: iso) { return d }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: iso)!
    }
    
    // MARK: - 1. TRADE RECONSTRUCTION TESTS (MATCHING round-trips.test.ts)
    
    func testLongTradeFullCycle() {
        let executions = [
            Execution(
                id: "e1",
                accountId: "acc-1",
                symbol: "AAPL",
                side: .buy,
                quantity: 100,
                price: 10,
                fee: 1,
                executedAt: parseDate("2026-01-05T14:30:00Z")
            ),
            Execution(
                id: "e2",
                accountId: "acc-1",
                symbol: "AAPL",
                side: .sell,
                quantity: 100,
                price: 12,
                fee: 1,
                executedAt: parseDate("2026-01-05T15:30:00Z")
            )
        ]
        
        let trips = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        XCTAssertEqual(trips.count, 1)
        
        let trade = trips[0]
        XCTAssertEqual(trade.direction, .long)
        XCTAssertEqual(trade.status, .win)
        XCTAssertEqual(trade.grossPnl, 200)
        XCTAssertEqual(trade.fees, 2)
        XCTAssertEqual(trade.netPnl, 198)
        XCTAssertEqual(trade.avgEntry, 10)
        XCTAssertEqual(trade.avgExit, 12)
        XCTAssertEqual(trade.durationMs, 3_600_000)
    }
    
    func testShortTradeFullCycle() {
        let executions = [
            Execution(
                id: "e1",
                accountId: "acc-1",
                symbol: "EURUSD",
                side: .sell,
                quantity: 10_000,
                price: Decimal(string: "1.10")!,
                fee: 0,
                executedAt: parseDate("2026-02-02T08:00:00Z")
            ),
            Execution(
                id: "e2",
                accountId: "acc-1",
                symbol: "EURUSD",
                side: .buy,
                quantity: 10_000,
                price: Decimal(string: "1.09")!,
                fee: 0,
                executedAt: parseDate("2026-02-02T09:00:00Z")
            )
        ]
        
        let trips = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        XCTAssertEqual(trips.count, 1)
        
        let trade = trips[0]
        XCTAssertEqual(trade.direction, .short)
        XCTAssertEqual(trade.status, .win)
        XCTAssertEqual(trade.netPnl, 100)
    }
    
    func testOpenPosition() {
        let executions = [
            Execution(
                id: "e1",
                accountId: "acc-1",
                symbol: "BTC",
                side: .buy,
                quantity: Decimal(string: "0.5")!,
                price: 60_000,
                fee: 0,
                executedAt: parseDate("2026-03-01T00:00:00Z")
            ),
            Execution(
                id: "e2",
                accountId: "acc-1",
                symbol: "BTC",
                side: .buy,
                quantity: Decimal(string: "0.5")!,
                price: 62_000,
                fee: 0,
                executedAt: parseDate("2026-03-02T00:00:00Z")
            )
        ]
        
        let trips = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        XCTAssertEqual(trips.count, 1)
        
        let trade = trips[0]
        XCTAssertEqual(trade.status, .open)
        XCTAssertEqual(trade.openQuantity, 1.0)
        XCTAssertEqual(trade.avgEntry, 61_000)
        XCTAssertNil(trade.avgExit)
        XCTAssertNil(trade.closedAt)
    }
    
    func testCrossingFlatSplitAndFeeProRata() {
        let executions = [
            Execution(
                id: "e1",
                accountId: "acc-1",
                symbol: "ES",
                side: .buy,
                quantity: 2,
                price: 5000,
                fee: 0,
                executedAt: parseDate("2026-04-01T14:00:00Z")
            ),
            // Sell 6: 2 close long, 4 open short. Fee 3 -> 1 to close, 2 to open.
            Execution(
                id: "e2",
                accountId: "acc-1",
                symbol: "ES",
                side: .sell,
                quantity: 6,
                price: 5010,
                fee: 3,
                executedAt: parseDate("2026-04-01T15:00:00Z")
            ),
            Execution(
                id: "e3",
                accountId: "acc-1",
                symbol: "ES",
                side: .buy,
                quantity: 4,
                price: 5005,
                fee: 0,
                executedAt: parseDate("2026-04-01T16:00:00Z")
            )
        ]
        
        let trips = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        XCTAssertEqual(trips.count, 2)
        
        let longTrade = trips[0]
        let shortTrade = trips[1]
        
        XCTAssertEqual(longTrade.direction, .long)
        XCTAssertEqual(longTrade.grossPnl, 20)
        XCTAssertEqual(longTrade.fees, 1)
        XCTAssertEqual(longTrade.netPnl, 19)
        
        XCTAssertEqual(shortTrade.direction, .short)
        XCTAssertEqual(shortTrade.grossPnl, 20)
        XCTAssertEqual(shortTrade.fees, 2)
        XCTAssertEqual(shortTrade.netPnl, 18)
    }
    
    func testFifoLifoWavgTotalPnlInvariant() {
        let executions = [
            Execution(id: "e1", accountId: "acc-1", symbol: "TSLA", side: .buy, quantity: 100, price: 200, fee: 0, executedAt: parseDate("2026-05-01T14:00:00Z")),
            Execution(id: "e2", accountId: "acc-1", symbol: "TSLA", side: .buy, quantity: 100, price: 210, fee: 0, executedAt: parseDate("2026-05-01T14:30:00Z")),
            Execution(id: "e3", accountId: "acc-1", symbol: "TSLA", side: .sell, quantity: 50, price: 215, fee: 0, executedAt: parseDate("2026-05-01T15:00:00Z")),
            Execution(id: "e4", accountId: "acc-1", symbol: "TSLA", side: .sell, quantity: 150, price: 220, fee: 0, executedAt: parseDate("2026-05-01T16:00:00Z"))
        ]
        
        let methods: [ProfitCalcMethod] = [.fifo, .lifo, .wavg]
        let results = methods.map { method in
            TradeReconstructionEngine.buildRoundTrips(
                executions: executions,
                options: .init(method: method)
            )[0].netPnl
        }
        
        // Bất biến: Tổng P&L phải bằng 2750 dưới mọi phương pháp
        XCTAssertEqual(results[0], 2750)
        XCTAssertEqual(results[1], 2750)
        XCTAssertEqual(results[2], 2750)
    }
    
    // MARK: - 2. FINANCIAL METRICS TESTS (MATCHING metrics.test.ts)
    
    private func sampleTrades() -> [Trade] {
        let executions = [
            Execution(id: "1", accountId: "a", symbol: "AAPL", side: .buy, quantity: 10, price: 100, executedAt: parseDate("2026-01-05T14:30:00Z")),
            Execution(id: "2", accountId: "a", symbol: "AAPL", side: .sell, quantity: 10, price: 110, executedAt: parseDate("2026-01-05T15:30:00Z")), // +100
            Execution(id: "3", accountId: "a", symbol: "TSLA", side: .buy, quantity: 5, price: 200, executedAt: parseDate("2026-01-05T16:00:00Z")),
            Execution(id: "4", accountId: "a", symbol: "TSLA", side: .sell, quantity: 5, price: 190, executedAt: parseDate("2026-01-05T17:00:00Z")), // -50
            Execution(id: "5", accountId: "a", symbol: "SPY", side: .buy, quantity: 20, price: 500, executedAt: parseDate("2026-01-06T14:30:00Z")),
            Execution(id: "6", accountId: "a", symbol: "SPY", side: .sell, quantity: 20, price: 505, executedAt: parseDate("2026-01-06T15:30:00Z")), // +100
            Execution(id: "7", accountId: "a", symbol: "AMD", side: .buy, quantity: 10, price: 150, executedAt: parseDate("2026-01-07T14:30:00Z")),
            Execution(id: "8", accountId: "a", symbol: "AMD", side: .sell, quantity: 10, price: 140, executedAt: parseDate("2026-01-07T15:30:00Z"))  // -100
        ]
        return TradeReconstructionEngine.buildRoundTrips(executions: executions)
    }
    
    func testMetricsCalculationSample() {
        let trades = sampleTrades()
        let utc = TimeZone(identifier: "UTC")!
        let m = FinancialMetricsEngine.computeMetrics(trades: trades, initialBalance: 1000, timeZone: utc)
        
        XCTAssertEqual(m.closedTrades, 4)
        XCTAssertEqual(m.wins, 2)
        XCTAssertEqual(m.losses, 2)
        XCTAssertEqual(m.netPnl, 50)
        XCTAssertEqual(m.winRate, 0.5)
        XCTAssertEqual(m.avgWin, 100)
        XCTAssertEqual(m.avgLoss, 75)
        XCTAssertEqual(m.expectancy, 12.5)
        
        // Profit factor: 200 / 150 = 1.333333
        XCTAssertEqual(m.profitFactor!, 200.0 / 150.0, accuracy: 1e-6)
        
        // Trading days: Jan 5 (+50), Jan 6 (+100), Jan 7 (-100) -> 3 days, 2 winning days
        XCTAssertEqual(m.tradingDays, 3)
        XCTAssertEqual(m.dayWinRate!, 2.0 / 3.0, accuracy: 1e-6)
        
        // Streaks: win, loss, win, loss -> maxWin: 1, maxLoss: 1, current: -1
        XCTAssertEqual(m.maxWinStreak, 1)
        XCTAssertEqual(m.maxLossStreak, 1)
        XCTAssertEqual(m.currentStreak, -1)
        
        // Drawdown: Cumulative [100, 50, 150, 50] -> Peak 150, Trough 50 -> MaxDD = 100
        XCTAssertEqual(m.maxDrawdown, 100)
        // MaxDDPct: 100 / (1000 + 150) = 100 / 1150
        XCTAssertEqual(m.maxDrawdownPct!, 100.0 / 1150.0, accuracy: 1e-6)
    }
    
    func testInfiniteProfitFactor() {
        let executions = [
            Execution(id: "1", accountId: "a", symbol: "AAPL", side: .buy, quantity: 1, price: 10, executedAt: parseDate("2026-01-05T14:30:00Z")),
            Execution(id: "2", accountId: "a", symbol: "AAPL", side: .sell, quantity: 1, price: 12, executedAt: parseDate("2026-01-05T15:30:00Z"))
        ]
        let trades = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        let m = FinancialMetricsEngine.computeMetrics(trades: trades)
        
        XCTAssertNil(m.profitFactor)
        XCTAssertTrue(m.profitFactorIsInfinite)
    }
    
    // MARK: - 3. EDGE SCORE V2 TESTS (MATCHING edge-score.ts)
    
    func testEdgeScoreCalculation() {
        let trades = sampleTrades()
        let m = FinancialMetricsEngine.computeMetrics(trades: trades, initialBalance: 1000)
        let score = EdgeScoreEngine.computeEdgeScore(metrics: m)
        
        XCTAssertEqual(score.version, 2)
        // ít hơn 5 trades đã đóng -> score = nil
        XCTAssertNil(score.score)
        XCTAssertEqual(score.closedTrades, 4)
        
        // Kiểm tra từng component
        // winRate: (0.5 / 0.6) * 100 = 83.3333%
        XCTAssertEqual(score.components.winRate, (0.5 / 0.6) * 100, accuracy: 1e-4)
        // profitFactor: (1.333333 / 3.0) * 100 = 44.4444%
        XCTAssertEqual(score.components.profitFactor, ((200.0 / 150.0) / 3.0) * 100, accuracy: 1e-4)
    }
    
    // MARK: - 4. R-MULTIPLE & RISK TESTS (MATCHING analysis.test.ts)
    
    func testRealizedRMultiple() {
        var trade = sampleTrades()[0] // AAPL: Entry 100, Exit 110, Qty 10, Net PnL +100
        // Long từ 100, Stoploss 95 -> Rủi ro = (100 - 95) * 10 = $50. Làm ra $100 -> 2R
        trade.stopLoss = 95
        
        let risk = TradeAnalysisEngine.tradeRisk(trade: trade)
        XCTAssertEqual(risk, 50)
        
        let r = TradeAnalysisEngine.tradeR(trade: trade)
        XCTAssertEqual(r!, 2.0, accuracy: 1e-6)
    }
    
    func testFuturesRealizedRWithMultiplier() {
        let executions = [
            Execution(id: "1", accountId: "a", symbol: "ES", side: .buy, quantity: 2, price: 5000, assetClass: "futures", executedAt: parseDate("2026-04-01T14:00:00Z")),
            Execution(id: "2", accountId: "a", symbol: "ES", side: .sell, quantity: 2, price: 5010, assetClass: "futures", executedAt: parseDate("2026-04-01T15:00:00Z"))
        ]
        var trade = TradeReconstructionEngine.buildRoundTrips(
            executions: executions,
            options: .init(multipliers: ["ES": 50])
        )[0]
        
        // Làm ra: (5010 - 5000) * 2 * 50 = $1,000
        XCTAssertEqual(trade.netPnl, 1000)
        
        // Stoploss 4995 -> 5 points * 2 contracts * $50 = $500 rủi ro -> 2R
        trade.stopLoss = 4995
        let r = TradeAnalysisEngine.tradeR(trade: trade)
        XCTAssertEqual(r!, 2.0, accuracy: 1e-6)
    }
}

