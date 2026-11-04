import XCTest
@testable import TradeJournal

final class SessionFootprintAndPatternTests: XCTestCase {
    
    // MARK: - 1. Test Session Intervals in GMT+7
    func testSessionIntervalsGMT7() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        
        let date = Date(timeIntervalSince1970: 1730700000) // Fixed point in time
        
        guard let tyo = SessionFootprintEngine.sessionInterval(for: .tokyo, on: date),
              let ldn = SessionFootprintEngine.sessionInterval(for: .london, on: date),
              let ny = SessionFootprintEngine.sessionInterval(for: .newYork, on: date) else {
            XCTFail("Failed to compute session intervals")
            return
        }
        
        let tyoStartH = cal.component(.hour, from: tyo.start)
        let tyoEndH = cal.component(.hour, from: tyo.end)
        XCTAssertEqual(tyoStartH, 7)
        XCTAssertEqual(tyoEndH, 16)
        
        let ldnStartH = cal.component(.hour, from: ldn.start)
        let ldnEndH = cal.component(.hour, from: ldn.end)
        XCTAssertEqual(ldnStartH, 14)
        XCTAssertEqual(ldnEndH, 23)
        
        let nyStartH = cal.component(.hour, from: ny.start)
        let nyEndH = cal.component(.hour, from: ny.end)
        XCTAssertEqual(nyStartH, 19)
        XCTAssertEqual(nyEndH, 4)
    }

    // MARK: - 2. Test Footprint Binning and 70% Value Area
    func testFootprintBinningAndPoc() {
        let baseDate = Date()
        var bars: [MarketBar] = []
        
        // Bar 1: Light volume at 2640
        bars.append(MarketBar(
            timestamp: baseDate,
            open: 2640,
            high: 2642,
            low: 2639,
            close: 2641,
            volume: 100
        ))
        
        // Bar 2: Heavy volume at 2650 (Point of Control cluster)
        bars.append(MarketBar(
            timestamp: baseDate.addingTimeInterval(900),
            open: 2649,
            high: 2651,
            low: 2649,
            close: 2650,
            volume: 800
        ))
        
        // Bar 3: Moderate volume at 2655
        bars.append(MarketBar(
            timestamp: baseDate.addingTimeInterval(1800),
            open: 2653,
            high: 2656,
            low: 2652,
            close: 2655,
            volume: 200
        ))
        
        let snapshot = SessionFootprintEngine.computeProfile(
            bars: bars,
            symbol: "XAUUSD",
            sessionType: .tokyo,
            sessionDate: "2026-11-04",
            startTime: baseDate,
            endTime: baseDate.addingTimeInterval(3600),
            rowSize: 1.0
        )
        
        XCTAssertNotNil(snapshot)
        guard let snap = snapshot else { return }
        
        XCTAssertEqual(snap.totalVolume, 1100)
        // POC should be around 2650.5 (midpoint of bin 2650)
        XCTAssertEqual(snap.pocPrice, 2650.5)
        XCTAssertTrue(snap.vahPrice >= snap.pocPrice)
        XCTAssertTrue(snap.valPrice <= snap.pocPrice)
        XCTAssertTrue(snap.isNaked)
    }

    // MARK: - 3. Test Naked POC Mitigation Tracking
    func testNakedPocMitigation() {
        let startTime = Date(timeIntervalSince1970: 1730000000)
        let endTime = startTime.addingTimeInterval(32400) // 9 hours
        
        var snapshots = [
            SessionProfileSnapshot(
                symbol: "XAUUSD",
                sessionType: .tokyo,
                sessionDate: "2026-11-04",
                startTime: startTime,
                endTime: endTime,
                pocPrice: 2650.0,
                vahPrice: 2655.0,
                valPrice: 2645.0,
                profileHigh: 2660.0,
                profileLow: 2640.0,
                totalVolume: 5000,
                isNaked: true
            )
        ]
        
        // Subsequent bar that does NOT touch 2650
        let bar1 = MarketBar(
            timestamp: endTime.addingTimeInterval(900),
            open: 2670,
            high: 2675,
            low: 2668,
            close: 2672,
            volume: 100
        )
        
        SessionFootprintEngine.updateMitigations(snapshots: &snapshots, subsequentBars: [bar1])
        XCTAssertTrue(snapshots[0].isNaked, "POC should remain naked when subsequent bar does not touch it")
        
        // Subsequent bar that sweeps through 2650 (low: 2648, high: 2655)
        let bar2 = MarketBar(
            timestamp: endTime.addingTimeInterval(1800),
            open: 2655,
            high: 2658,
            low: 2648,
            close: 2652,
            volume: 250
        )
        
        SessionFootprintEngine.updateMitigations(snapshots: &snapshots, subsequentBars: [bar1, bar2])
        XCTAssertFalse(snapshots[0].isNaked, "POC should be marked mitigated after price sweeps it")
        XCTAssertNotNil(snapshots[0].mitigatedAt)
    }

    // MARK: - 4. Test Candlestick Pattern Recognition
    func testSingleBarPinbars() {
        let baseDate = Date()
        
        // Bullish Pinbar: Open 2650, High 2652, Low 2630 (Wick 20), Close 2651
        // Range = 22, Lower wick = 20 (90.9%), Body = 1 (4.5%), Upper wick = 1 (4.5%)
        let hammerBar = MarketBar(
            timestamp: baseDate,
            open: 2650,
            high: 2652,
            low: 2630,
            close: 2651,
            volume: 300
        )
        
        let hammerPatterns = CandlePatternEngine.detectSingleBarPattern(bar: hammerBar)
        XCTAssertTrue(hammerPatterns.contains(.bullishPinbar), "Expected Bullish Pinbar / Hammer pattern")
        
        // Bearish Shooting Star: Open 2640, High 2660 (Wick 19), Low 2638, Close 2639
        // Range = 22, Upper wick = 20 (90.9%), Body = 1 (4.5%), Lower wick = 1 (4.5%)
        let shootingStarBar = MarketBar(
            timestamp: baseDate.addingTimeInterval(900),
            open: 2640,
            high: 2660,
            low: 2638,
            close: 2639,
            volume: 300
        )
        
        let starPatterns = CandlePatternEngine.detectSingleBarPattern(bar: shootingStarBar)
        XCTAssertTrue(starPatterns.contains(.bearishPinbar), "Expected Bearish Pinbar / Shooting Star pattern")
    }

    func testPatternConfluenceWithKeyLevel() {
        let baseDate = Date()
        
        let hammerBar = MarketBar(
            timestamp: baseDate,
            open: 2650,
            high: 2652,
            low: 2630,
            close: 2651,
            volume: 300
        )
        
        let keyLevels = [
            KeyLevel(type: .sessionPoc(.tokyo), price: 2630.0, label: "Tokyo POC", isNaked: false)
        ]
        
        let detected = CandlePatternEngine.scanPatternsWithKeyLevelConfluence(
            bars: [hammerBar, hammerBar],
            keyLevels: keyLevels,
            atr: 5.0
        )
        
        XCTAssertFalse(detected.isEmpty)
        XCTAssertEqual(detected.first?.confluenceKeyLevel?.label, "Tokyo POC")
    }

    // MARK: - 5. Test Prior Staircase Step Retention (Even If Mitigated)
    func testPriorStaircaseStepEvenIfMitigated() {
        let yesterday = Date(timeIntervalSince1970: 1730000000)
        
        // Yesterday's Daily POC = 239.0 (Already touched / mitigated by price)
        let priorDailySnapshot = SessionProfileSnapshot(
            symbol: "XAUUSD",
            sessionType: .daily,
            sessionDate: "2026-11-03",
            startTime: yesterday,
            endTime: yesterday.addingTimeInterval(86400),
            pocPrice: 239.0,
            vahPrice: 245.0,
            valPrice: 235.0,
            profileHigh: 250.0,
            profileLow: 230.0,
            totalVolume: 10000,
            isNaked: false, // NOT naked
            mitigatedAt: yesterday.addingTimeInterval(43200)
        )
        
        // Today's developing POC = 213.0
        let keyLevels = SessionFootprintEngine.extractKeyLevels(
            snapshots: [priorDailySnapshot],
            developingPoc: 213.0,
            developingSession: .daily
        )
        
        // Verify developing POC (213.0) exists
        let liveLevel = keyLevels.first(where: { $0.price == 213.0 })
        XCTAssertNotNil(liveLevel, "Expected Live D1 POC at 213.0")
        
        // Verify prior staircase step (239.0) is retained with explicit Prior D1 POC label
        let priorLevel = keyLevels.first(where: { $0.price == 239.0 })
        XCTAssertNotNil(priorLevel, "Expected Prior D1 POC at 239.0 even though it is mitigated")
        XCTAssertEqual(priorLevel?.label, "Prior D1 POC")
        XCTAssertFalse(priorLevel?.isNaked ?? true)
        
        // Test staircase comparison: 213 < 239 (LOWER STEP)
        let staircase = SessionFootprintEngine.compareStaircaseSteps(
            snapshots: [priorDailySnapshot],
            developingPoc: 213.0,
            developingSession: .daily
        )
        
        let dailyStep = staircase[.daily]
        XCTAssertNotNil(dailyStep)
        XCTAssertEqual(dailyStep?.currentPoc, 213.0)
        XCTAssertEqual(dailyStep?.priorPoc, 239.0)
        XCTAssertTrue(dailyStep?.stepDirection.contains("LOWER STEP") ?? false)
    }
}

