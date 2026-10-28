import XCTest
@testable import TradeJournal

final class TradeAnalyticsAggregatorTests: XCTestCase {
    
    private func makeSampleTrade(
        key: String,
        symbol: String = "XAUUSD",
        direction: TradeDirection = .long,
        status: TradeStatus = .win,
        openedAt: Date,
        closedAt: Date,
        netPnl: Decimal,
        quantity: Decimal = 1.0,
        entry: Decimal = 2700.0,
        exit: Decimal = 2710.0
    ) -> Trade {
        Trade(
            key: key,
            accountId: "acc-1",
            symbol: symbol,
            direction: direction,
            status: status,
            openedAt: openedAt,
            closedAt: closedAt,
            quantity: quantity,
            avgEntry: entry,
            avgExit: exit,
            grossPnl: netPnl,
            netPnl: netPnl
        )
    }
    
    func testMultiDimensionalAggregations() {
        let calendar = Calendar(identifier: .gregorian)
        var utcCal = calendar
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        
        // 2026-10-26 is a Monday
        var comps1 = DateComponents(year: 2026, month: 10, day: 26, hour: 4, minute: 0) // Asian
        let date1 = utcCal.date(from: comps1)!
        let close1 = date1.addingTimeInterval(600) // 10 mins (Scalp)
        
        var comps2 = DateComponents(year: 2026, month: 10, day: 26, hour: 10, minute: 0) // London
        let date2 = utcCal.date(from: comps2)!
        let close2 = date2.addingTimeInterval(3600) // 1 hour (Intraday)
        
        var comps3 = DateComponents(year: 2026, month: 10, day: 27, hour: 15, minute: 0) // NY (Tuesday)
        let date3 = utcCal.date(from: comps3)!
        let close3 = date3.addingTimeInterval(5 * 3600) // 5 hours (Swing)
        
        let t1 = makeSampleTrade(key: "t1", direction: .long, status: .win, openedAt: date1, closedAt: close1, netPnl: 150)
        let t2 = makeSampleTrade(key: "t2", direction: .short, status: .loss, openedAt: date2, closedAt: close2, netPnl: -80)
        let t3 = makeSampleTrade(key: "t3", direction: .long, status: .win, openedAt: date3, closedAt: close3, netPnl: 300)
        
        let excEstimate = ExcursionEstimate(mae: -50, mfe: 200, sampledBars: 10, excludedBars: 0)
        let excJson = (try? String(data: JSONEncoder().encode(excEstimate), encoding: .utf8)) ?? "{}"
        let exc = TradeExcursion(tradeKey: "t1", fingerprint: "fp1", provider: "oanda", symbol: "XAUUSD", resolution: "15m", estimateJson: excJson)
        
        let snapshot = TradeAnalyticsAggregator.computeSnapshot(
            trades: [t1, t2, t3],
            excursions: [exc],
            timeZone: TimeZone(identifier: "UTC")!
        )
        
        // Assert overall metrics
        XCTAssertEqual(snapshot.totalTrades, 3)
        XCTAssertEqual(snapshot.closedTrades, 3)
        XCTAssertEqual(snapshot.overallNetPnl, 370) // 150 - 80 + 300
        XCTAssertEqual(snapshot.overallWinRate, 66.66666666666666, accuracy: 0.1)
        
        // Assert session breakdown
        XCTAssertFalse(snapshot.bySession.isEmpty)
        let asian = snapshot.bySession.first(where: { $0.label.contains("Asian") })
        XCTAssertEqual(asian?.totalTrades, 1)
        XCTAssertEqual(asian?.netPnl, 150)
        
        let london = snapshot.bySession.first(where: { $0.label.contains("London") })
        XCTAssertEqual(london?.totalTrades, 1)
        XCTAssertEqual(london?.netPnl, -80)
        
        // Assert direction breakdown
        let longs = snapshot.byDirection.first(where: { $0.label.contains("LONG") })
        XCTAssertEqual(longs?.totalTrades, 2)
        XCTAssertEqual(longs?.netPnl, 450)
        
        let shorts = snapshot.byDirection.first(where: { $0.label.contains("SHORT") })
        XCTAssertEqual(shorts?.totalTrades, 1)
        XCTAssertEqual(shorts?.netPnl, -80)
        
        // Assert duration breakdown
        let scalp = snapshot.byDurationBucket.first(where: { $0.label.contains("Scalp") })
        XCTAssertEqual(scalp?.totalTrades, 1)
        
        let intraday = snapshot.byDurationBucket.first(where: { $0.label.contains("Intraday") })
        XCTAssertEqual(intraday?.totalTrades, 1)
        
        let swing = snapshot.byDurationBucket.first(where: { $0.label.contains("Swing") })
        XCTAssertEqual(swing?.totalTrades, 1)
        
        // Assert excursion summary
        XCTAssertNotNil(snapshot.excursionSummary)
        XCTAssertEqual(snapshot.excursionSummary?.avgMaeDollar, -50)
        XCTAssertEqual(snapshot.excursionSummary?.avgMfeDollar, 200)
        
        // Assert prompt formatting contains pure numeric tables
        let promptText = TradeAnalyticsAggregator.formatSnapshotForPrompt(snapshot, isVi: true)
        XCTAssertTrue(promptText.contains("[THỐNG KÊ HIỆU SUẤT ĐA CHIỀU (MULTI-DIMENSIONAL PERFORMANCE DATA)]"))
        XCTAssertTrue(promptText.contains("Asian (00:00 - 08:00 UTC)"))
        XCTAssertTrue(promptText.contains("LONG (Mua)"))
        XCTAssertTrue(promptText.contains("SHORT (Bán)"))
        XCTAssertTrue(promptText.contains("Scalp (< 15 phút)"))
    }
}
