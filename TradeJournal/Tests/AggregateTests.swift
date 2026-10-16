import XCTest
@testable import TradeJournalKit

final class AggregateTests: XCTestCase {
    
    func testTradingSessionBoundaries() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        
        let dateComponents = DateComponents(year: 2026, month: 10, day: 16)
        
        // Asian: 00:00 - 08:00 UTC
        var cAsian = dateComponents; cAsian.hour = 3
        let dAsian = cal.date(from: cAsian)!
        XCTAssertEqual(AggregateEngine.session(for: dAsian), .asian)
        
        // London: 08:00 - 13:00 UTC
        var cLondon = dateComponents; cLondon.hour = 9
        let dLondon = cal.date(from: cLondon)!
        XCTAssertEqual(AggregateEngine.session(for: dLondon), .london)
        
        // London/NY Overlap: 13:00 - 16:00 UTC
        var cOverlap = dateComponents; cOverlap.hour = 14
        let dOverlap = cal.date(from: cOverlap)!
        XCTAssertEqual(AggregateEngine.session(for: dOverlap), .londonNyOverlap)
        
        // New York: 16:00 - 21:00 UTC
        var cNY = dateComponents; cNY.hour = 17
        let dNY = cal.date(from: cNY)!
        XCTAssertEqual(AggregateEngine.session(for: dNY), .newYork)
        
        // Off-hours: 21:00 - 24:00 UTC
        var cOff = dateComponents; cOff.hour = 22
        let dOff = cal.date(from: cOff)!
        XCTAssertEqual(AggregateEngine.session(for: dOff), .offHours)
    }
    
    func testBySymbolAggregation() {
        let t1 = Trade(
            key: "t1", accountId: "acc-1", symbol: "NQ",
            direction: .long, status: .win, openedAt: Date(),
            quantity: 2, openQuantity: 0, avgEntry: 20000,
            grossPnl: 500, fees: 5, netPnl: 495, executionCount: 2, executionIds: ["e1", "e2"]
        )
        let t2 = Trade(
            key: "t2", accountId: "acc-1", symbol: "ES",
            direction: .short, status: .loss, openedAt: Date(),
            quantity: 1, openQuantity: 0, avgEntry: 5800,
            grossPnl: -200, fees: 5, netPnl: -205, executionCount: 2, executionIds: ["e3", "e4"]
        )
        let t3 = Trade(
            key: "t3", accountId: "acc-1", symbol: "NQ",
            direction: .long, status: .win, openedAt: Date(),
            quantity: 1, openQuantity: 0, avgEntry: 20100,
            grossPnl: 300, fees: 5, netPnl: 295, executionCount: 2, executionIds: ["e5", "e6"]
        )
        
        let symbols = AggregateEngine.bySymbol(trades: [t1, t2, t3])
        XCTAssertEqual(symbols.count, 2)
        
        // NQ should be first due to highest net PnL (495 + 295 = 790)
        XCTAssertEqual(symbols[0].key, "NQ")
        XCTAssertEqual(symbols[0].trades, 2)
        XCTAssertEqual(symbols[0].netPnl, 790)
        XCTAssertEqual(symbols[0].winRate, 1.0)
        XCTAssertEqual(symbols[0].volume, 3)
        
        // ES second (-205)
        XCTAssertEqual(symbols[1].key, "ES")
        XCTAssertEqual(symbols[1].trades, 1)
        XCTAssertEqual(symbols[1].netPnl, -205)
        XCTAssertEqual(symbols[1].winRate, 0.0)
    }
}
