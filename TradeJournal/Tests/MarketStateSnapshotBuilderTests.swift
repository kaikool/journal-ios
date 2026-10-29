import XCTest
@testable import TradeJournal

final class MarketStateSnapshotBuilderTests: XCTestCase {
    
    private func makeBar(timestamp: Date, open: Decimal, high: Decimal, low: Decimal, close: Decimal) -> MarketBar {
        MarketBar(
            timestamp: timestamp,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: 100
        )
    }
    
    func testComputeSnapshotPureCalculation() {
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        
        // Create 20 synthetic H4 bars with an uptrend
        var h4Bars: [MarketBar] = []
        for i in 0..<20 {
            let t = baseDate.addingTimeInterval(Double(i * 14400))
            let p = Decimal(2000 + i * 5)
            h4Bars.append(makeBar(timestamp: t, open: p, high: p + 3, low: p - 2, close: p + 2))
        }
        
        // Create 20 synthetic M15 bars
        var m15Bars: [MarketBar] = []
        for i in 0..<20 {
            let t = baseDate.addingTimeInterval(Double(i * 900))
            let p = Decimal(2050 + i * 2)
            m15Bars.append(makeBar(timestamp: t, open: p, high: p + 1, low: p - 1, close: p + 1))
        }
        
        // High impact news 30 minutes in the future
        let futureNewsDate = baseDate.addingTimeInterval(1800)
        let event = ForexFactoryEvent(
            id: "news-1",
            title: "CPI m/m",
            country: "USD",
            date: futureNewsDate,
            impact: .high,
            forecast: "0.3%",
            previous: "0.2%"
        )
        
        let snapshot = MarketStateSnapshotBuilder.computeSnapshot(
            symbol: "XAUUSD",
            barsH4: h4Bars,
            barsM15: m15Bars,
            events: [event],
            referenceDate: baseDate
        )
        
        XCTAssertEqual(snapshot.symbol, "XAUUSD")
        XCTAssertEqual(snapshot.currentPrice, m15Bars.last?.close)
        XCTAssertNotNil(snapshot.h4OrderFlow)
        XCTAssertNotNil(snapshot.m15OrderFlow)
        XCTAssertNotNil(snapshot.rsi14)
        XCTAssertEqual(snapshot.nearestHighImpactNewsTitle, "USD CPI m/m")
        XCTAssertEqual(snapshot.newsCountdownMinutes, 30)
    }
    
    func testFormatForPromptZeroHardcoding() {
        let snapshot = MarketStateSnapshot(
            symbol: "EURUSD",
            currentPrice: 1.0850,
            h4OrderFlow: "BULLISH",
            h4SwingHigh: 1.0920,
            h4SwingLow: 1.0780,
            h4BrokenLevel: 1.0820,
            m15OrderFlow: "BEARISH",
            m15MssState: "CHoCH",
            m15TriggerLevel: 1.0835,
            m15NearestSweep: "BUY_SIDE tại 1.0860",
            m15NearestUnsweptPool: 1.0810,
            rsi14: 62.4,
            ema9: 58.1,
            wma45: 54.3,
            emaVsWmaGap: 3.8,
            nearestHighImpactNewsTitle: "USD Non-Farm Payrolls",
            newsCountdownMinutes: 45,
            timestamp: Date()
        )
        
        let formattedVi = MarketStateSnapshotBuilder.formatForPrompt(snapshot, isVi: true)
        XCTAssertTrue(formattedVi.contains("DỮ LIỆU ĐO LƯỜNG THỊ TRƯỜNG THỰC TẾ"))
        XCTAssertTrue(formattedVi.contains("EURUSD"))
        XCTAssertTrue(formattedVi.contains("1.085"))
        XCTAssertTrue(formattedVi.contains("BULLISH"))
        XCTAssertTrue(formattedVi.contains("BEARISH"))
        XCTAssertTrue(formattedVi.contains("CHoCH"))
        XCTAssertTrue(formattedVi.contains("62.4"))
        XCTAssertTrue(formattedVi.contains("Non-Farm Payrolls"))
        
        let formattedEn = MarketStateSnapshotBuilder.formatForPrompt(snapshot, isVi: false)
        XCTAssertTrue(formattedEn.contains("OBJECTIVE MARKET FACTS & MULTI-TIMEFRAME MEASUREMENTS"))
        XCTAssertTrue(formattedEn.contains("EURUSD"))
        XCTAssertTrue(formattedEn.contains("BULLISH"))
        XCTAssertTrue(formattedEn.contains("BEARISH"))
    }
    
    func testPreTradePromptContainsObjectiveFacts() {
        let baseDate = Date()
        var bars: [MarketBar] = []
        for i in 0..<20 {
            let t = baseDate.addingTimeInterval(Double(i * 900))
            let p = Decimal(100 + i)
            bars.append(MarketBar(timestamp: t, open: p, high: p + 1, low: p - 1, close: p + Decimal(0.5), volume: 10))
        }
        
        let prompt = AIPromptBuilder.buildPreTradeAnalysisPrompt(
            symbol: "US500",
            d1Bars: bars,
            h4Bars: bars,
            m15Bars: bars,
            language: "vi"
        )
        
        XCTAssertTrue(prompt.contains("[DỮ LIỆU ĐO LƯỜNG THỊ TRƯỜNG THỰC TẾ (OBJECTIVE MARKET FACTS)]"))
        XCTAssertTrue(prompt.contains("US500"))
    }
}
