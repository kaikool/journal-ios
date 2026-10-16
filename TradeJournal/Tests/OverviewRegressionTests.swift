import XCTest
@testable import TradeJournal

final class OverviewRegressionTests: XCTestCase {
    
    private func makeSampleTrade(
        key: String,
        netPnl: Decimal,
        status: TradeStatus? = nil,
        openedAt: Date,
        closedAt: Date
    ) -> Trade {
        let actualStatus = status ?? (netPnl > 0 ? .win : .loss)
        return Trade(
            key: key,
            accountId: "acc-1",
            symbol: "TEST",
            direction: .long,
            status: actualStatus,
            openedAt: openedAt,
            closedAt: closedAt,
            quantity: 10,
            avgEntry: 100,
            avgExit: 110,
            grossPnl: netPnl,
            fees: 0,
            netPnl: netPnl,
            executionCount: 2,
            annotations: TradeAnnotations(
                notes: nil,
                tags: nil,
                mistakes: nil,
                playbook: "plan",
                rating: nil,
                stopLoss: 98,
                profitTarget: 104,
                reviewedAt: nil
            )
        )
    }

    func testSymbolBucketsCountOpenVolumeAndExcludeFromWinRate() {
        let iso = ISO8601DateFormatter()
        let t1 = iso.date(from: "2026-09-01T23:30:00Z")!
        let t2 = iso.date(from: "2026-09-02T00:30:00Z")!
        
        let trades = [
            makeSampleTrade(key: "win", netPnl: 100, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "loss", netPnl: -20, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "near-flat", netPnl: 3, status: .breakeven, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "open", netPnl: 500, status: .open, openedAt: t1, closedAt: t2)
        ]
        
        let symbolStats = AggregateEngine.bySymbol(trades: trades)
        XCTAssertEqual(symbolStats.count, 1)
        let s = symbolStats[0]
        XCTAssertEqual(s.key, "TEST")
        XCTAssertEqual(s.trades, 4)
        XCTAssertEqual(s.netPnl, 83)
        XCTAssertEqual(s.volume, 40)
        
        let expectedWinRate = Decimal(1) / Decimal(3)
        XCTAssertEqual(s.winRate, expectedWinRate)
        let expectedPF = Decimal(103) / Decimal(20)
        XCTAssertEqual(s.profitFactor, expectedPF)
        
        let openOnly = AggregateEngine.bySymbol(trades: [
            makeSampleTrade(key: "open", netPnl: 500, status: .open, openedAt: t1, closedAt: t2)
        ])
        XCTAssertEqual(openOnly.count, 1)
        XCTAssertEqual(openOnly[0].netPnl, 0)
        XCTAssertNil(openOnly[0].winRate)
        XCTAssertNil(openOnly[0].profitFactor)
        XCTAssertEqual(openOnly[0].volume, 10)
    }

    func testCachedDailyTotalsProduceIdenticalMetricsCurvesAndCalendar() {
        let iso = ISO8601DateFormatter()
        let t1 = iso.date(from: "2026-09-01T23:30:00Z")!
        let t2 = iso.date(from: "2026-09-02T00:30:00Z")!
        
        let trades = [
            makeSampleTrade(key: "win", netPnl: 100, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "loss", netPnl: -20, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "open", netPnl: 0, status: .open, openedAt: t1, closedAt: t2)
        ]
        
        let tzIdentifiers = ["UTC", "America/New_York", "Pacific/Auckland"]
        for tzId in tzIdentifiers {
            guard let timeZone = TimeZone(identifier: tzId) else { continue }
            let overview = FinancialMetricsEngine.computeOverview(trades: trades, timeZone: timeZone, initialBalance: 1000)
            let directMetrics = FinancialMetricsEngine.computeMetrics(trades: trades, timeZone: timeZone, initialBalance: 1000)
            XCTAssertEqual(overview.metrics, directMetrics)
            
            let dailyFromDays = FinancialMetricsEngine.dailyCumulativeFromDays(days: overview.days)
            let dailyDirect = FinancialMetricsEngine.dailyCumulative(trades: trades, timeZone: timeZone)
            XCTAssertEqual(dailyFromDays.map { $0.cumNetPnl }, dailyDirect.map { $0.cumNetPnl })
            
            let calFromDays = AggregateEngine.calendarMonthFromDays(dayStats: overview.days, year: 2026, month: 9)
            let calDirect = AggregateEngine.calendarMonth(trades: trades, year: 2026, month: 9, timeZone: timeZone)
            XCTAssertEqual(calFromDays, calDirect)
        }
    }

    func testRuleCoverageAndPerformance() {
        let iso = ISO8601DateFormatter()
        let t1 = iso.date(from: "2026-09-01T23:30:00Z")!
        let t2 = iso.date(from: "2026-09-02T00:30:00Z")!
        
        let trades = [
            makeSampleTrade(key: "complete", netPnl: 100, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "broken", netPnl: -20, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "partial", netPnl: 50, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "empty", netPnl: -10, openedAt: t1, closedAt: t2),
            makeSampleTrade(key: "open", netPnl: 200, status: .open, openedAt: t1, closedAt: t2)
        ]
        
        let checks = [
            RuleCheck(tradeKey: "complete", playbookId: "plan", rule: "Entry", followed: true),
            RuleCheck(tradeKey: "complete", playbookId: "plan", rule: "Risk", followed: true),
            RuleCheck(tradeKey: "broken", playbookId: "plan", rule: "Risk", followed: false),
            RuleCheck(tradeKey: "partial", playbookId: "plan", rule: "Entry", followed: true),
            RuleCheck(tradeKey: "empty", playbookId: "plan", rule: "Removed rule", followed: false),
            RuleCheck(tradeKey: "open", playbookId: "plan", rule: "Risk", followed: false),
            RuleCheck(tradeKey: "outside-filter", playbookId: "plan", rule: "Risk", followed: false)
        ]
        
        let reports = AdherenceEngine.analyzeAdherence(
            trades: trades,
            playbooks: [PlaybookRuleSet(id: "plan", rules: ["Entry", "Risk", "Risk"])],
            checks: checks
        )
        
        XCTAssertEqual(reports.count, 1)
        let report = reports[0]
        XCTAssertEqual(report.total, 4)
        XCTAssertEqual(report.evaluated, 4)
        XCTAssertEqual(report.possible, 8)
        XCTAssertEqual(report.rate, 0.75)
        XCTAssertEqual(report.unassessed, 2)
        
        XCTAssertEqual(report.followed.trades, 1)
        XCTAssertEqual(report.followed.netPnl, 100)
        XCTAssertEqual(report.broken.trades, 1)
        XCTAssertEqual(report.broken.netPnl, -20)
        
        XCTAssertEqual(report.rules[0].rule, "Entry")
        XCTAssertEqual(report.rules[0].evaluated, 2)
        XCTAssertEqual(report.rules[0].rate, 1.0)
        XCTAssertEqual(report.rules[0].followed.netPnl, 150)
        
        XCTAssertEqual(report.rules[1].rule, "Risk")
        XCTAssertEqual(report.rules[1].evaluated, 2)
        XCTAssertEqual(report.rules[1].rate, 0.5)
    }

    func testDoesNotTreatEmptyChecklistOrDifferentPlaybookAsAdherence() {
        let iso = ISO8601DateFormatter()
        let t1 = iso.date(from: "2026-09-01T23:30:00Z")!
        let t2 = iso.date(from: "2026-09-02T00:30:00Z")!
        
        let trades = [makeSampleTrade(key: "one", netPnl: 10, openedAt: t1, closedAt: t2)]
        let playbooks = [
            PlaybookRuleSet(id: "plan", rules: []),
            PlaybookRuleSet(id: "other", rules: ["Entry"])
        ]
        let checks = [
            RuleCheck(tradeKey: "one", playbookId: "other", rule: "Entry", followed: true)
        ]
        
        let reports = AdherenceEngine.analyzeAdherence(
            trades: trades,
            playbooks: playbooks,
            checks: checks
        )
        
        XCTAssertEqual(reports.count, 2)
        let empty = reports[0]
        let other = reports[1]
        
        XCTAssertNil(empty.rate)
        XCTAssertEqual(empty.possible, 0)
        XCTAssertEqual(empty.unassessed, 1)
        XCTAssertEqual(empty.followed.trades, 0)
        
        XCTAssertEqual(other.total, 0)
        XCTAssertEqual(other.evaluated, 0)
        XCTAssertNil(other.rate)
    }
}
