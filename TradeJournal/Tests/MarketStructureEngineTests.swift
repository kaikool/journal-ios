import XCTest
@testable import TradeJournal

final class MarketStructureEngineTests: XCTestCase {
    
    private func makeBar(
        index: Int,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        baseTimestamp: Int64 = 1719324000000 // 2024-06-25 14:00 UTC
    ) -> MarketBar {
        let ts = baseTimestamp + Int64(index * 900_000)
        return MarketBar(
            timestamp: ts,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: 100
        )
    }
    
    // MARK: - 1. Causal Fractal Confirmation & Anti-Lookahead Guarantee
    
    func testCausalFractalConfirmation() {
        // Swing high forms at index 2 with window = 2.
        // It requires bar 3 and bar 4 to close before it is confirmed at index 4!
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2640, high: 2642, low: 2638, close: 2641),
            makeBar(index: 1, open: 2641, high: 2645, low: 2640, close: 2644),
            makeBar(index: 2, open: 2644, high: 2650, low: 2643, close: 2648), // Peak formed here
            makeBar(index: 3, open: 2648, high: 2646, low: 2635, close: 2636),
            makeBar(index: 4, open: 2636, high: 2639, low: 2630, close: 2632)  // Confirmed here!
        ]
        
        let allSwings = SwingDetector.detectSwings(bars: bars, window: 2)
        XCTAssertEqual(allSwings.count, 1)
        
        let high = allSwings.first!
        XCTAssertEqual(high.formationIndex, 2, "Formation index must be 2")
        XCTAssertEqual(high.confirmedAtIndex, 4, "Confirmation index must be formationIndex + window = 4")
        
        // Anti-lookahead test:
        // At bar index 2 or 3, this swing MUST NOT exist in the causal set
        let swingsAtBar2 = SwingDetector.swingsConfirmed(swings: allSwings, upToBarIndex: 2)
        XCTAssertTrue(swingsAtBar2.isEmpty, "Swing must NOT be known at bar 2")
        
        let swingsAtBar3 = SwingDetector.swingsConfirmed(swings: allSwings, upToBarIndex: 3)
        XCTAssertTrue(swingsAtBar3.isEmpty, "Swing must NOT be known at bar 3")
        
        let swingsAtBar4 = SwingDetector.swingsConfirmed(swings: allSwings, upToBarIndex: 4)
        XCTAssertEqual(swingsAtBar4.count, 1, "Swing becomes known ONLY at bar 4 close")
    }
    
    // MARK: - 2. Bullish MSS: Reversal from Downtrend
    
    func testBullishMSS_ReversalFromBearish() {
        // Construct a Bearish structure: Lower High (2646) and Lower Low (2630)
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2650, high: 2652, low: 2648, close: 2650),
            makeBar(index: 1, open: 2650, high: 2655, low: 2649, close: 2654),
            makeBar(index: 2, open: 2654, high: 2656, low: 2652, close: 2655), // High 2656
            makeBar(index: 3, open: 2655, high: 2653, low: 2646, close: 2647),
            makeBar(index: 4, open: 2647, high: 2648, low: 2640, close: 2642),
            makeBar(index: 5, open: 2642, high: 2644, low: 2636, close: 2638), // Low 2636
            makeBar(index: 6, open: 2638, high: 2645, low: 2637, close: 2644),
            makeBar(index: 7, open: 2644, high: 2646, low: 2641, close: 2645), // Lower High 2646
            makeBar(index: 8, open: 2645, high: 2643, low: 2634, close: 2635),
            makeBar(index: 9, open: 2635, high: 2636, low: 2630, close: 2631), // Lower Low 2630
            makeBar(index: 10, open: 2631, high: 2638, low: 2630, close: 2637),
            makeBar(index: 11, open: 2637, high: 2643, low: 2636, close: 2642),
            // Bar 12: Big Bullish candle CLOSING ABOVE Lower High (2646) at 2648.50!
            makeBar(index: 12, open: 2642, high: 2650, low: 2641, close: 2648.50),
            makeBar(index: 13, open: 2648.50, high: 2652, low: 2647, close: 2650)
        ]
        
        let analysis = MarketStructureEngine.analyzeStructure(bars: bars)
        
        XCTAssertEqual(analysis.mss.state, .bullishMSS, "Closing above Lower High must confirm Bullish MSS")
        XCTAssertEqual(analysis.mss.brokenLevelPrice, 2646, "Broken level must be the Lower High (2646)")
        XCTAssertEqual(analysis.mss.breakClosePrice, 2648.50)
        XCTAssertEqual(analysis.mss.confirmedCandleIndex, 12)
        XCTAssertEqual(analysis.mss.trendRegime, .bullish, "Regime must transition to Bullish upon MSS")
    }
    
    // MARK: - 3. Bearish MSS: Reversal from Uptrend
    
    func testBearishMSS_ReversalFromBullish() {
        // Construct a Bullish structure: Higher Low (2638) and Higher High (2655)
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2630, high: 2632, low: 2628, close: 2630),
            makeBar(index: 1, open: 2630, high: 2635, low: 2629, close: 2634),
            makeBar(index: 2, open: 2634, high: 2636, low: 2630, close: 2632), // Low 2630
            makeBar(index: 3, open: 2632, high: 2644, low: 2631, close: 2642),
            makeBar(index: 4, open: 2642, high: 2646, low: 2640, close: 2645), // High 2646
            makeBar(index: 5, open: 2645, high: 2643, low: 2637, close: 2639),
            makeBar(index: 6, open: 2639, high: 2642, low: 2638, close: 2640), // Higher Low 2638
            makeBar(index: 7, open: 2640, high: 2652, low: 2639, close: 2650),
            makeBar(index: 8, open: 2650, high: 2655, low: 2648, close: 2653), // Higher High 2655
            makeBar(index: 9, open: 2653, high: 2651, low: 2642, close: 2643),
            makeBar(index: 10, open: 2643, high: 2644, low: 2639, close: 2640),
            // Bar 11: Bearish candle CLOSING BELOW Higher Low (2638) at 2635!
            makeBar(index: 11, open: 2640, high: 2641, low: 2634, close: 2635),
            makeBar(index: 12, open: 2635, high: 2636, low: 2630, close: 2632)
        ]
        
        let analysis = MarketStructureEngine.analyzeStructure(bars: bars)
        
        XCTAssertEqual(analysis.mss.state, .bearishMSS, "Closing below Higher Low must confirm Bearish MSS")
        XCTAssertEqual(analysis.mss.brokenLevelPrice, 2638, "Broken level must be Higher Low (2638)")
        XCTAssertEqual(analysis.mss.breakClosePrice, 2635)
        XCTAssertEqual(analysis.mss.confirmedCandleIndex, 11)
        XCTAssertEqual(analysis.mss.trendRegime, .bearish, "Regime must transition to Bearish upon MSS")
    }
    
    // MARK: - 4. Bullish BOS: Continuation (Not MSS)
    
    func testBullishBOS_Continuation() {
        // Construct an established Bullish structure, then break the previous Higher High
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2630, high: 2632, low: 2628, close: 2630),
            makeBar(index: 1, open: 2630, high: 2635, low: 2629, close: 2634),
            makeBar(index: 2, open: 2634, high: 2636, low: 2630, close: 2632), // Low 2630
            makeBar(index: 3, open: 2632, high: 2644, low: 2631, close: 2642),
            makeBar(index: 4, open: 2642, high: 2646, low: 2640, close: 2645), // High 2646
            makeBar(index: 5, open: 2645, high: 2643, low: 2637, close: 2639),
            makeBar(index: 6, open: 2639, high: 2642, low: 2638, close: 2640), // Higher Low 2638
            makeBar(index: 7, open: 2640, high: 2652, low: 2639, close: 2650),
            makeBar(index: 8, open: 2650, high: 2655, low: 2648, close: 2653), // Higher High 2655
            makeBar(index: 9, open: 2653, high: 2652, low: 2648, close: 2650),
            makeBar(index: 10, open: 2650, high: 2654, low: 2649, close: 2652),
            // Bar 11: Closes ABOVE Higher High (2655) at 2658 -> Bullish BOS Continuation!
            makeBar(index: 11, open: 2652, high: 2660, low: 2651, close: 2658)
        ]
        
        let analysis = MarketStructureEngine.analyzeStructure(bars: bars)
        
        XCTAssertEqual(analysis.mss.state, .bullishBOS, "Breaking higher in an uptrend is BOS, not MSS")
        XCTAssertEqual(analysis.mss.brokenLevelPrice, 2655)
        XCTAssertEqual(analysis.mss.breakClosePrice, 2658)
    }
    
    // MARK: - 5. Liquidity Sweep: Wick Rejection Does NOT Trigger MSS
    
    func testLiquiditySweep_WickOnlyDoesNotTriggerMSS() {
        // Swing High at 2650. Bar 8 pierces to 2652 (wick) but CLOSES at 2646 (< 2650)
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2640, high: 2642, low: 2638, close: 2641),
            makeBar(index: 1, open: 2641, high: 2645, low: 2640, close: 2644),
            makeBar(index: 2, open: 2644, high: 2650, low: 2643, close: 2648), // Swing High at 2650 (confirmed bar 4)
            makeBar(index: 3, open: 2648, high: 2646, low: 2638, close: 2640),
            makeBar(index: 4, open: 2640, high: 2642, low: 2634, close: 2636),
            makeBar(index: 5, open: 2636, high: 2640, low: 2633, close: 2638), // Swing Low at 2633
            makeBar(index: 6, open: 2638, high: 2644, low: 2637, close: 2643),
            makeBar(index: 7, open: 2643, high: 2648, low: 2642, close: 2647),
            // Bar 8: High is 2652 (swept 2650!), but CLOSE is 2646 (rejected back inside!)
            makeBar(index: 8, open: 2647, high: 2652, low: 2645, close: 2646),
            makeBar(index: 9, open: 2646, high: 2647, low: 2640, close: 2642)
        ]
        
        let analysis = MarketStructureEngine.analyzeStructure(bars: bars)
        
        XCTAssertFalse(analysis.recentSweeps.isEmpty, "Sweep event must be recorded")
        XCTAssertEqual(analysis.recentSweeps.first?.sweepType, .buySideSwept)
        XCTAssertEqual(analysis.recentSweeps.first?.wickExtreme, 2652)
        
        // Assert: MSS must NOT be confirmed because candle body closed inside!
        XCTAssertNil(analysis.mss.state, "Wick rejection must keep MSS in pending state")
    }
    
    // MARK: - 6. Chronological Event History (No Loop Overwriting)
    
    func testChronologicalEventHistoryNotOverwritten() {
        // Construct market that has:
        // 1) Bullish BOS at bar 8
        // 2) Followed by Bearish MSS at bar 13
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2630, high: 2632, low: 2628, close: 2630),
            makeBar(index: 1, open: 2630, high: 2635, low: 2629, close: 2634),
            makeBar(index: 2, open: 2634, high: 2636, low: 2630, close: 2632), // Low 2630
            makeBar(index: 3, open: 2632, high: 2644, low: 2631, close: 2642),
            makeBar(index: 4, open: 2642, high: 2646, low: 2640, close: 2645), // High 2646
            makeBar(index: 5, open: 2645, high: 2643, low: 2637, close: 2639),
            makeBar(index: 6, open: 2639, high: 2642, low: 2638, close: 2640), // Higher Low 2638
            makeBar(index: 7, open: 2640, high: 2648, low: 2639, close: 2645),
            // Bar 8: Closes at 2649 > High 2646 -> Bullish BOS
            makeBar(index: 8, open: 2645, high: 2650, low: 2644, close: 2649),
            makeBar(index: 9, open: 2649, high: 2655, low: 2648, close: 2653), // Peak High 2655
            makeBar(index: 10, open: 2653, high: 2651, low: 2642, close: 2643),
            makeBar(index: 11, open: 2643, high: 2644, low: 2639, close: 2640),
            makeBar(index: 12, open: 2640, high: 2641, low: 2634, close: 2635), // Closes < 2638 -> Bearish MSS
            makeBar(index: 13, open: 2635, high: 2636, low: 2630, close: 2632)
        ]
        
        let swings = SwingDetector.detectSwings(bars: bars, window: 2)
        let sm = StructureStateMachine.run(bars: bars, swings: swings)
        
        // Assert: Event history contains BOTH events chronologically!
        XCTAssertGreaterThanOrEqual(sm.eventHistory.count, 2, "Event history must preserve all events chronologically")
        XCTAssertEqual(sm.eventHistory.first?.type, .bullishBOS, "First event must be Bullish BOS")
        XCTAssertEqual(sm.eventHistory.last?.type, .bearishMSS, "Last event must be Bearish MSS")
    }
    
    // MARK: - 7. Chronological Mitigation: Broken Level Before Lookback Window
    
    func testBrokenLevelBeforeLookbackNotSweptLater() {
        // Swing high forms at bar 2 (price 2650), confirmed at bar 4.
        // Bar 6 closes at 2652 (> 2650) -> level is broken / mitigated!
        // Bar 10 wicks to 2651 and closes at 2648.
        // Lookback window is 4 bars (so startIndex = 7).
        // Since 2650 was mitigated at bar 6, bar 10 must NOT trigger a sweep!
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2640, high: 2642, low: 2638, close: 2641),
            makeBar(index: 1, open: 2641, high: 2645, low: 2640, close: 2644),
            makeBar(index: 2, open: 2644, high: 2650, low: 2643, close: 2648), // Peak 2650
            makeBar(index: 3, open: 2648, high: 2646, low: 2638, close: 2640),
            makeBar(index: 4, open: 2640, high: 2642, low: 2635, close: 2636), // Confirmed at bar 4
            makeBar(index: 5, open: 2636, high: 2645, low: 2635, close: 2644),
            makeBar(index: 6, open: 2644, high: 2653, low: 2643, close: 2652), // Body closes above 2650!
            makeBar(index: 7, open: 2652, high: 2654, low: 2646, close: 2647),
            makeBar(index: 8, open: 2647, high: 2648, low: 2642, close: 2644),
            makeBar(index: 9, open: 2644, high: 2647, low: 2643, close: 2646),
            makeBar(index: 10, open: 2646, high: 2651, low: 2645, close: 2648)  // Wicks above 2650 in lookback
        ]
        
        let swings = SwingDetector.detectSwings(bars: bars, window: 2)
        let sweeps = LiquidityEngine.detectSweeps(bars: bars, swings: swings, sessionBarsCount: 4)
        
        // Assert: 2650 was already mitigated at bar 6, so no sweep should be reported at bar 10
        let sweepOf2650 = sweeps.filter { $0.sweptPrice == 2650 }
        XCTAssertTrue(sweepOf2650.isEmpty, "Mitigated swing high must not trigger sweeps in subsequent lookback windows")
    }
    
    // MARK: - 8. PDH Level Consumption & Anti-Spam
    
    func testPDHSweptOnceAndNotDuplicatedOnConsecutiveBars() {
        let d1Bar = MarketBar(
            timestamp: 1719237600000, // 2024-06-24 (previous day)
            open: 2640,
            high: 2650,
            low: 2630,
            close: 2645,
            volume: 1000
        )
        
        // Intraday bars on current day (2024-06-25)
        // Bar 0 pierces 2650 with rejection wick (swept)
        // Bar 1 pierces 2650 again with rejection wick
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2646, high: 2652, low: 2645, close: 2647), // High 2652 > 2650, Close 2647 < 2650
            makeBar(index: 1, open: 2647, high: 2651, low: 2646, close: 2648), // High 2651 > 2650, Close 2648 < 2650
            makeBar(index: 2, open: 2648, high: 2649, low: 2644, close: 2645)
        ]
        
        let sweeps = LiquidityEngine.detectSweeps(bars: bars, swings: [], d1Bars: [d1Bar], sessionBarsCount: 3)
        let pdhSweeps = sweeps.filter { $0.levelName == "D1 PDH" }
        
        XCTAssertEqual(pdhSweeps.count, 1, "PDH must be swept exactly once and not spammed across consecutive wicking bars")
        XCTAssertEqual(pdhSweeps.first?.barIndex, 0, "PDH sweep must occur on the first penetrating candle")
        XCTAssertEqual(pdhSweeps.first?.penetration, 2.0, "Penetration must be 2652 - 2650 = 2.0")
    }
    
    func testPDHBrokenByBodyCloseDoesNotTriggerSweep() {
        let d1Bar = MarketBar(
            timestamp: 1719237600000,
            open: 2640,
            high: 2650,
            low: 2630,
            close: 2645,
            volume: 1000
        )
        
        // Bar 0: Body breakout CLOSES above PDH (2652 > 2650)
        // Bar 1: Wicks to 2653 and closes at 2649 (pullback test into broken PDH)
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2645, high: 2654, low: 2644, close: 2652), // Body breakout
            makeBar(index: 1, open: 2652, high: 2653, low: 2648, close: 2649)  // Pullback
        ]
        
        let sweeps = LiquidityEngine.detectSweeps(bars: bars, swings: [], d1Bars: [d1Bar], sessionBarsCount: 2)
        let pdhSweeps = sweeps.filter { $0.levelName == "D1 PDH" }
        
        XCTAssertTrue(pdhSweeps.isEmpty, "PDH broken by candle close must not trigger sweeps on subsequent pullback wicks")
    }
    
    // MARK: - 9. Equal Highs (EQH) Pool Detection & SFP Quality
    
    func testEqualHighsPoolDetectionAndSweep() {
        // Bar 2: Peak at 2650.0 (confirmed bar 4)
        // Bar 8: Peak at 2650.2 (diff 0.2 / 2650.0 = 0.0076% < 0.15% tolerance, confirmed bar 10)
        // Bar 11: High 2653.0, Close 2647.0 (Upper wick = 2653 - 2647 = 6, Range = 2653 - 2645 = 8, Wick Ratio = 75%)
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2640, high: 2642, low: 2638, close: 2641),
            makeBar(index: 1, open: 2641, high: 2645, low: 2640, close: 2644),
            makeBar(index: 2, open: 2644, high: 2650.0, low: 2643, close: 2648), // Peak 1: 2650.0
            makeBar(index: 3, open: 2648, high: 2646, low: 2638, close: 2640),
            makeBar(index: 4, open: 2640, high: 2642, low: 2634, close: 2636), // Confirmed 1
            makeBar(index: 5, open: 2636, high: 2644, low: 2635, close: 2642),
            makeBar(index: 6, open: 2642, high: 2647, low: 2641, close: 2646),
            makeBar(index: 7, open: 2646, high: 2649, low: 2645, close: 2648),
            makeBar(index: 8, open: 2648, high: 2650.2, low: 2646, close: 2649), // Peak 2: 2650.2 (EQH cluster)
            makeBar(index: 9, open: 2649, high: 2647, low: 2640, close: 2642),
            makeBar(index: 10, open: 2642, high: 2644, low: 2638, close: 2640), // Confirmed 2
            // Bar 11: Sweeps EQH cluster with strong SFP rejection!
            makeBar(index: 11, open: 2646, high: 2653.0, low: 2645, close: 2647.0)
        ]
        
        let swings = SwingDetector.detectSwings(bars: bars, window: 2)
        let pools = LiquidityEngine.detectEqualHighsLows(swings: swings)
        
        // Assert: EQH cluster is correctly identified
        XCTAssertFalse(pools.isEmpty, "EQH cluster must be detected")
        XCTAssertEqual(pools.first?.count, 2, "Cluster must have 2 highs")
        XCTAssertEqual(pools.first?.extremePrice, 2650.2)
        
        // Assert: Liquidity sweep detects EQH pool sweep and marks as Strong SFP
        let sweeps = LiquidityEngine.detectSweeps(bars: bars, swings: swings, sessionBarsCount: 5)
        let eqhSweep = sweeps.first(where: { $0.levelName == "EQH (Double Highs)" })
        
        XCTAssertNotNil(eqhSweep, "EQH sweep event must be recorded")
        XCTAssertEqual(eqhSweep?.sweepQuality, .strongSFP, "75% wick ratio must be classified as Strong SFP")
        XCTAssertEqual(eqhSweep?.penetration, 2.8, "Penetration must be 2653.0 - 2650.2 = 2.8")
        XCTAssertGreaterThanOrEqual(eqhSweep?.rejectionWickRatio ?? 0, 0.70)
        
        // Assert: Deduping ensures only 1 sweep event on bar 11, not duplicate single swings
        let sweepsOnBar11 = sweeps.filter { $0.barIndex == 11 }
        XCTAssertEqual(sweepsOnBar11.count, 1, "Only EQH pool sweep must be fired, deduping underlying swing points")
    }
    
    // MARK: - 10. Unswept Liquidity Pools State Extraction
    
    func testDetectUnsweptPools() {
        // Construct market with 1 unmitigated Swing High at 2660 and 1 unmitigated Swing Low at 2620
        let bars: [MarketBar] = [
            makeBar(index: 0, open: 2630, high: 2632, low: 2620, close: 2625), // Low 2620 formed
            makeBar(index: 1, open: 2625, high: 2640, low: 2624, close: 2638),
            makeBar(index: 2, open: 2638, high: 2660, low: 2636, close: 2655), // High 2660 formed
            makeBar(index: 3, open: 2655, high: 2652, low: 2644, close: 2646),
            makeBar(index: 4, open: 2646, high: 2648, low: 2640, close: 2642), // Low 2620 confirmed at bar 2, High 2660 confirmed at bar 4
            makeBar(index: 5, open: 2642, high: 2645, low: 2641, close: 2643)
        ]
        
        let swings = SwingDetector.detectSwings(bars: bars, window: 2)
        let unswept = LiquidityEngine.detectUnsweptPools(bars: bars, swings: swings)
        
        XCTAssertFalse(unswept.isEmpty, "Unswept pools must be extracted")
        let highPool = unswept.first(where: { $0.type == .high })
        let lowPool = unswept.first(where: { $0.type == .low })
        
        XCTAssertEqual(highPool?.extremePrice, 2660)
        XCTAssertEqual(lowPool?.extremePrice, 2620)
    }
    
    // MARK: - 11. MomentumEngine RSI (14) Series Calculation
    
    func testRSISeriesCalculation() {
        // Construct 25 bars with strong upward momentum followed by a pullback
        var bars: [MarketBar] = []
        var currentPrice: Decimal = 100.0
        
        for i in 0..<25 {
            let delta: Decimal = i < 18 ? 2.0 : -1.5
            let open = currentPrice
            let close = currentPrice + delta
            let high = max(open, close) + 0.5
            let low = min(open, close) - 0.5
            currentPrice = close
            
            bars.append(makeBar(index: i, open: open, high: high, low: low, close: close))
        }
        
        let rsiValues = MomentumEngine.computeRSISeries(bars: bars, period: 14)
        
        XCTAssertEqual(rsiValues.count, 25, "RSI series must match bar count")
        
        // Warmup period (first 14 bars: indices 0..13) must be nil
        for i in 0..<14 {
            XCTAssertNil(rsiValues[i], "Bar \(i) is in warmup period and must have nil RSI")
        }
        
        // After warmup period, valid RSI values must be in [0, 100]
        for i in 14..<25 {
            guard let rsi = rsiValues[i] else {
                XCTFail("Bar \(i) should have a valid RSI value")
                return
            }
            XCTAssertGreaterThanOrEqual(rsi, 0.0, "RSI must be >= 0")
            XCTAssertLessThanOrEqual(rsi, 100.0, "RSI must be <= 100")
        }
        
        // At index 17 (after 18 consecutive up bars), RSI must be in overbought territory (> 70)
        if let peakRsi = rsiValues[17] {
            XCTAssertGreaterThan(peakRsi, 70.0, "RSI after strong uptrend must exceed 70")
        }
    }
    
    // MARK: - 12. SMC Structure Alternation & RSI Moving Averages
    
    func testSMCSwingsAlternation() {
        // Construct 30 bars forming a clean wave: Low(0) -> High(8) -> Low(16) -> High(24)
        var bars: [MarketBar] = []
        var p: Decimal = 100
        
        for i in 0..<30 {
            let change: Decimal
            if i < 8 { change = 2.0 }        // Rally to High ~ 116
            else if i < 16 { change = -1.5 }  // Pullback to Low ~ 104
            else if i < 24 { change = 2.5 }   // Higher rally to HH ~ 124
            else { change = -1.0 }            // Retracement
            
            let open = p
            let close = p + change
            let high = max(open, close) + 0.5
            let low = min(open, close) - 0.5
            p = close
            bars.append(makeBar(index: i, open: open, high: high, low: low, close: close))
        }
        
        let smcSwings = SwingDetector.detectSMCSwings(bars: bars, resolution: .h4)
        
        // Assert: Swings strictly alternate (High -> Low -> High -> Low...)
        for i in 1..<smcSwings.count {
            XCTAssertNotEqual(
                smcSwings[i].type,
                smcSwings[i - 1].type,
                "SMC swings must strictly alternate between High and Low without consecutive duplicates"
            )
        }
    }
    
    func testRSIMACalculation() {
        // Construct series of 30 RSI values
        let rsiSeries: [Double?] = (0..<14).map { _ in nil } + (14..<30).map { Double($0 * 2) }
        
        let ema = MomentumEngine.computeEMA(series: rsiSeries, period: 5)
        let wma = MomentumEngine.computeWMA(series: rsiSeries, period: 5)
        
        XCTAssertEqual(ema.count, rsiSeries.count)
        XCTAssertEqual(wma.count, rsiSeries.count)
        
        // Indices before 14 + 4 must be nil (14 warmup + 5 MA period)
        XCTAssertNil(ema[17])
        XCTAssertNotNil(ema[18])
        XCTAssertNotNil(wma[18])
        
        if let emaVal = ema[18], let wmaVal = wma[18] {
            XCTAssertGreaterThan(emaVal, 0)
            XCTAssertLessThanOrEqual(emaVal, 100)
            XCTAssertGreaterThan(wmaVal, 0)
            XCTAssertLessThanOrEqual(wmaVal, 100)
        }
    }
}
