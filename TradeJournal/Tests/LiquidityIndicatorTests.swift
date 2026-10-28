import XCTest
@testable import TradeJournal

// MARK: - Institutional Liquidity Indicator Acceptance Tests (LQ-01 to LQ-12)
// Rigorously verifies all mathematical properties, causality guarantees,
// lifecycle transitions, and lookahead-invariance requirements.

final class LiquidityIndicatorTests: XCTestCase {
    
    private func makeBar(
        index: Int,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        baseTimestamp: Int64 = 1719324000000, // 2024-06-25 14:00 UTC
        stepMs: Int64 = 900_000 // 15 minutes
    ) -> MarketBar {
        let ts = baseTimestamp + Int64(index) * stepMs
        return MarketBar(
            timestamp: ts,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: 1000
        )
    }
    
    // MARK: - LQ-01: Map Source (Primary H4/H1 and Macro Levels Only)
    
    func testLQ01_MapSourceOnlyH4H1AndMacro() {
        let h4Bars = [
            makeBar(index: 0, open: 1.0800, high: 1.0820, low: 1.0790, close: 1.0810, stepMs: 14_400_000),
            makeBar(index: 1, open: 1.0810, high: 1.0850, low: 1.0805, close: 1.0840, stepMs: 14_400_000),
            makeBar(index: 2, open: 1.0840, high: 1.0900, low: 1.0830, close: 1.0880, stepMs: 14_400_000), // Swing High at 1.0900
            makeBar(index: 3, open: 1.0880, high: 1.0870, low: 1.0810, close: 1.0820, stepMs: 14_400_000),
            makeBar(index: 4, open: 1.0820, high: 1.0840, low: 1.0780, close: 1.0800, stepMs: 14_400_000)  // Confirmed here
        ]
        
        let map = LiquidityEngine.buildLiquidityMap(
            symbol: "EURUSD",
            barsH4: h4Bars,
            barsH1: [],
            barsD1: []
        )
        
        // Assert: Map contains H4 swing high, and source timeframe is explicitly H4
        let bsl = map.first(where: { $0.type == .buySide })
        XCTAssertNotNil(bsl, "H4 Swing High must be in primary liquidity map")
        XCTAssertEqual(bsl?.sourceTimeframe, "H4")
        XCTAssertEqual(bsl?.price, 1.0900)
    }
    
    // MARK: - LQ-02: Causal Pivot (Zero Lookahead)
    
    func testLQ02_CausalPivotConfirmationNoLookahead() {
        // High at index 2 (1.0900) with window 2 is confirmed strictly at index 4 (i + 2)
        let bars = [
            makeBar(index: 0, open: 1.0800, high: 1.0820, low: 1.0790, close: 1.0810),
            makeBar(index: 1, open: 1.0810, high: 1.0850, low: 1.0805, close: 1.0840),
            makeBar(index: 2, open: 1.0840, high: 1.0900, low: 1.0830, close: 1.0880), // Peak
            makeBar(index: 3, open: 1.0880, high: 1.0870, low: 1.0810, close: 1.0820),
            makeBar(index: 4, open: 1.0820, high: 1.0840, low: 1.0780, close: 1.0800)  // Confirmation bar
        ]
        
        let pivots = LiquidityEngine.identifyPivots(bars: bars, window: 2)
        XCTAssertEqual(pivots.count, 1)
        
        let p = pivots.first!
        XCTAssertEqual(p.formationIndex, 2)
        XCTAssertEqual(p.confirmedAtIndex, 4, "Pivot must be confirmed at index formationIndex + window = 4")
        
        // Simulation at bar 2 or bar 3 must NOT have this pivot active
        let sliceBar3 = Array(bars.prefix(4))
        let pivotsAtBar3 = LiquidityEngine.identifyPivots(bars: sliceBar3, window: 2)
        XCTAssertTrue(pivotsAtBar3.isEmpty, "Pivot cannot be confirmed before bar 4 closes")
    }
    
    // MARK: - LQ-03: Clustered EQH / EQL with Adaptive Tolerance
    
    func testLQ03_EqhEqlAdaptiveClustering() {
        // Two highs close to each other: 1.08500 and 1.08508 (diff 0.8 pips)
        let p1 = LiquiditySwingPivot(
            type: .buySide,
            price: Decimal(string: "1.08500")!,
            formationIndex: 5,
            formationTimestamp: 1000,
            confirmedAtIndex: 7,
            confirmedTimestamp: 1200,
            timeframe: "H1"
        )
        let p2 = LiquiditySwingPivot(
            type: .buySide,
            price: Decimal(string: "1.08508")!,
            formationIndex: 18,
            formationTimestamp: 2000,
            confirmedAtIndex: 20,
            confirmedTimestamp: 2200,
            timeframe: "H1"
        )
        
        let eqPools = LiquidityEngine.detectEqualHighsLows(
            pivots: [p1, p2],
            tickSize: Decimal(string: "0.00001")!,
            atr: Decimal(string: "0.0015")!
        )
        
        XCTAssertEqual(eqPools.count, 1, "Pivots within ATR/tick tolerance must cluster into EQH")
        let eq = eqPools.first!
        XCTAssertEqual(eq.origin, .equalHighsLows)
        XCTAssertEqual(eq.touchCount, 2)
        XCTAssertEqual(eq.topPrice, Decimal(string: "1.08508")!)
        XCTAssertEqual(eq.bottomPrice, Decimal(string: "1.08500")!)
    }
    
    // MARK: - LQ-04: PDH / PDL Dynamic Non-Lookahead Resolution
    
    func testLQ04_PdhPdlNoFutureLookahead() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        
        // Day 1: 2024-06-24
        let day1 = cal.date(from: DateComponents(year: 2024, month: 6, day: 24, hour: 0, minute: 0))!
        let d1Bar1 = MarketBar(timestamp: Int64(day1.timeIntervalSince1970 * 1000), open: 1.0700, high: 1.0750, low: 1.0690, close: 1.0740)
        
        // Day 2: 2024-06-25 (High 1.0850)
        let day2 = cal.date(from: DateComponents(year: 2024, month: 6, day: 25, hour: 0, minute: 0))!
        let d1Bar2 = MarketBar(timestamp: Int64(day2.timeIntervalSince1970 * 1000), open: 1.0740, high: 1.0850, low: 1.0730, close: 1.0820)
        
        // Day 3: 2024-06-26
        let day3 = cal.date(from: DateComponents(year: 2024, month: 6, day: 26, hour: 0, minute: 0))!
        let d1Bar3 = MarketBar(timestamp: Int64(day3.timeIntervalSince1970 * 1000), open: 1.0820, high: 1.0900, low: 1.0810, close: 1.0890)
        
        let allD1 = [d1Bar1, d1Bar2, d1Bar3]
        
        // At 14:00 UTC on Day 2 (2024-06-25):
        // PDH must be Day 1's high (1.0750), NOT Day 2's or Day 3's high!
        let midDay2 = cal.date(from: DateComponents(year: 2024, month: 6, day: 25, hour: 14, minute: 0))!
        let tsMidDay2 = Int64(midDay2.timeIntervalSince1970 * 1000)
        
        let (pdhAtDay2, pdlAtDay2) = LiquidityEngine.resolvePreviousDayLevels(d1Bars: allD1, upToTimestamp: tsMidDay2)
        XCTAssertEqual(pdhAtDay2, 1.0750, "At midday on 2024-06-25, PDH must strictly be Day 1 (1.0750)")
        XCTAssertEqual(pdlAtDay2, 1.0690)
        
        // At 10:00 UTC on Day 3 (2024-06-26):
        // Now Day 2 is completed, so PDH becomes Day 2's high (1.0850)
        let midDay3 = cal.date(from: DateComponents(year: 2024, month: 6, day: 26, hour: 10, minute: 0))!
        let tsMidDay3 = Int64(midDay3.timeIntervalSince1970 * 1000)
        
        let (pdhAtDay3, pdlAtDay3) = LiquidityEngine.resolvePreviousDayLevels(d1Bars: allD1, upToTimestamp: tsMidDay3)
        XCTAssertEqual(pdhAtDay3, 1.0850, "At midday on 2024-06-26, PDH must strictly be Day 2 (1.0850)")
        XCTAssertEqual(pdlAtDay3, 1.0730)
    }
    
    // MARK: - LQ-05: PWH / PWL Weekly Boundary
    
    func testLQ05_PwhPwlWeeklyBoundary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        
        // Week 1: 5 daily bars (High: 1.0800, Low: 1.0600)
        var d1Bars: [MarketBar] = []
        for day in 17...21 { // 2024-06-17 to 2024-06-21 (Monday to Friday)
            let dt = cal.date(from: DateComponents(year: 2024, month: 6, day: day, hour: 0, minute: 0))!
            let ts = Int64(dt.timeIntervalSince1970 * 1000)
            let h: Decimal = day == 19 ? 1.0800 : 1.0720
            let l: Decimal = day == 18 ? 1.0600 : 1.0650
            d1Bars.append(MarketBar(timestamp: ts, open: 1.0680, high: h, low: l, close: 1.0700))
        }
        
        // Wednesday of Week 2: 2024-06-26
        let refDate = cal.date(from: DateComponents(year: 2024, month: 6, day: 26, hour: 12, minute: 0))!
        let refTs = Int64(refDate.timeIntervalSince1970 * 1000)
        
        let (pwh, pwl) = LiquidityEngine.resolvePreviousWeekLevels(d1Bars: d1Bars, upToTimestamp: refTs)
        XCTAssertEqual(pwh, 1.0800, "PWH must match max of completed prior week")
        XCTAssertEqual(pwl, 1.0600, "PWL must match min of completed prior week")
    }
    
    // MARK: - LQ-06 & LQ-07: Sweep vs Breakout Distinction
    
    func testLQ06_SweepVsBreakoutDistinction() {
        let pool = LiquidityPool(
            id: "TEST_BSL",
            type: .buySide,
            origin: .swingPivot,
            label: "Test High",
            price: 1.0850,
            formationTimestamp: 1000,
            confirmedTimestamp: 1000,
            state: .active,
            sourceTimeframe: "H4"
        )
        
        // Bar 0: High = 1.0860 > 1.0850, but Close = 1.0845 < 1.0850 (SWEEP / SFP)
        let bar0 = makeBar(index: 0, open: 1.0840, high: 1.0860, low: 1.0838, close: 1.0845, baseTimestamp: 2000)
        let simSweep = LiquidityEngine.simulate(bars: [bar0], pools: [pool])
        
        XCTAssertEqual(simSweep.sweeps.count, 1, "Piercing with body close inside MUST trigger sweep")
        XCTAssertEqual(simSweep.sweeps.first?.sweepType, .buySideSwept)
        XCTAssertEqual(simSweep.sweeps.first?.eventType, .confirmedSweep)
        
        // Bar 1: Open = 1.0845, High = 1.0870, Close = 1.0865 > 1.0850 (BREAKOUT)
        let bar1 = makeBar(index: 0, open: 1.0845, high: 1.0870, low: 1.0840, close: 1.0865, baseTimestamp: 2000)
        let simBreakout = LiquidityEngine.simulate(bars: [bar1], pools: [pool])
        
        XCTAssertTrue(simBreakout.sweeps.isEmpty, "Candle body close beyond pool MUST NOT be classified as sweep")
        let breakEvent = simBreakout.allEvents.first(where: { $0.eventType == .breakout })
        XCTAssertNotNil(breakEvent, "Breakout event must be recorded")
    }
    
    func testLQ07_BreakoutDoesNotTriggerSweep() {
        let pool = LiquidityPool(
            id: "TEST_SSL",
            type: .sellSide,
            origin: .swingPivot,
            label: "Test Low",
            price: 1.0700,
            formationTimestamp: 1000,
            confirmedTimestamp: 1000,
            state: .active,
            sourceTimeframe: "H4"
        )
        
        // Bar breaks below 1.0700 and closes at 1.0680
        let bar0 = makeBar(index: 0, open: 1.0710, high: 1.0715, low: 1.0675, close: 1.0680, baseTimestamp: 2000)
        let sim = LiquidityEngine.simulate(bars: [bar0], pools: [pool])
        
        XCTAssertTrue(sim.sweeps.isEmpty)
        XCTAssertEqual(sim.allEvents.first?.eventType, .breakout)
    }
    
    // MARK: - LQ-08: MTF Reference at Event Time
    
    func testLQ08_MtfEventDetectionAgainstActivePools() {
        let h4Pool = LiquidityPool(
            id: "H4_BSL_1",
            type: .buySide,
            origin: .swingPivot,
            label: "H4 Major High",
            price: 1.0900,
            formationTimestamp: 1000,
            confirmedTimestamp: 5000,
            state: .active,
            sourceTimeframe: "H4"
        )
        
        // M15 Bar at timestamp 4000 (BEFORE H4 pool confirmation at 5000) pierces 1.0900
        let barPre = makeBar(index: 0, open: 1.0890, high: 1.0910, low: 1.0885, close: 1.0892, baseTimestamp: 4000)
        let simPre = LiquidityEngine.simulate(bars: [barPre], pools: [h4Pool])
        XCTAssertTrue(simPre.sweeps.isEmpty, "Pool confirmed at 5000 cannot be interacted with at timestamp 4000")
        
        // M15 Bar at timestamp 6000 (AFTER H4 pool confirmation) pierces 1.0900 and closes at 1.0895
        let barPost = makeBar(index: 0, open: 1.0890, high: 1.0910, low: 1.0885, close: 1.0895, baseTimestamp: 6000)
        let simPost = LiquidityEngine.simulate(bars: [barPost], pools: [h4Pool])
        XCTAssertEqual(simPost.sweeps.count, 1, "Pool confirmed at 5000 is active and swept at timestamp 6000")
    }
    
    // MARK: - LQ-09: Pool Lifecycle State Transitions
    
    func testLQ09_PoolLifecycleTransitions() {
        var pool = LiquidityPool(
            id: "POOL_1",
            type: .buySide,
            origin: .swingPivot,
            label: "H4 High",
            price: 1.0800,
            formationTimestamp: 1000,
            confirmedTimestamp: 1000,
            state: .active,
            sourceTimeframe: "H4"
        )
        XCTAssertEqual(pool.state, .active)
        XCTAssertFalse(pool.isMitigated)
        
        // Bar 0 pierces and closes below -> pool transitions to .swept
        let bar0 = makeBar(index: 0, open: 1.0790, high: 1.0815, low: 1.0788, close: 1.0795, baseTimestamp: 2000)
        let sim = LiquidityEngine.simulate(bars: [bar0], pools: [pool])
        
        XCTAssertEqual(sim.sweeps.count, 1)
        // Check remaining active resting pools: the swept pool is no longer in restingBuySide!
        XCTAssertTrue(sim.restingBuySide.isEmpty, "Swept pool must be removed from active resting pools")
    }
    
    // MARK: - LQ-10: Minimal UI Pool Merging & Limits
    
    func testLQ10_MinimalUIPoolMergingAndDeduplication() {
        let p1 = LiquidityPool(
            id: "H4_BSL",
            type: .buySide,
            origin: .swingPivot,
            label: "H4 Swing High",
            price: 1.08500,
            formationTimestamp: 1000,
            confirmedTimestamp: 1000,
            state: .active,
            sourceTimeframe: "H4"
        )
        let p2 = LiquidityPool(
            id: "H1_EQH",
            type: .buySide,
            origin: .equalHighsLows,
            label: "H1 Double High (EQH)",
            price: 1.08505, // 0.5 pip difference
            formationTimestamp: 1200,
            confirmedTimestamp: 1200,
            state: .active,
            sourceTimeframe: "H1"
        )
        
        let merged = LiquidityEngine.mergeOverlappingPools(
            pools: [p1, p2],
            tolerance: Decimal(string: "0.00010")!
        )
        
        XCTAssertEqual(merged.count, 1, "Overlapping H4/H1 levels must merge into a single consolidated pool")
        let consolidated = merged.first!
        XCTAssertTrue(consolidated.label.contains("H4 Swing High"))
        XCTAssertTrue(consolidated.label.contains("H1 Double High (EQH)"))
        XCTAssertEqual(consolidated.sourcePivots.count, p1.sourcePivots.count + p2.sourcePivots.count)
    }
    
    // MARK: - LQ-11 & LQ-12: Sequential Replay & Strict Lookahead Invariance
    
    func testLQ11_SequentialReplayConsistency() {
        let bars: [MarketBar] = (0..<20).map { i in
            let p = Decimal(100 + i)
            return makeBar(index: i, open: p, high: p + 1, low: p - 1, close: p + Decimal(0.5))
        }
        
        let out1 = LiquidityEngine.simulate(bars: bars, pools: [])
        let out2 = LiquidityEngine.simulate(bars: bars, pools: [])
        
        XCTAssertEqual(out1.sweeps.count, out2.sweeps.count)
        XCTAssertEqual(out1.allEvents.count, out2.allEvents.count)
    }
    
    /// MANDATORY LOOKAHEAD INVARIANCE TEST:
    /// Calculate analysis up to timestamp t.
    /// Then append candles t+1 ... N.
    /// Assert that the output at timestamp t remains strictly identical!
    func testLQ12_StrictLookaheadInvariance() {
        // Construct 25 M15 bars
        var bars: [MarketBar] = []
        var cur: Decimal = 1.0800
        for i in 0..<25 {
            let high = cur + 0.0010
            let low = cur - 0.0008
            let close = cur + 0.0002
            bars.append(makeBar(index: i, open: cur, high: high, low: low, close: close, baseTimestamp: 1719324000000))
            cur = close
        }
        
        let h4Pool = LiquidityPool(
            id: "H4_BSL_FIXED",
            type: .buySide,
            origin: .swingPivot,
            label: "H4 Fixed High",
            price: 1.0815,
            formationTimestamp: 1719324000000,
            confirmedTimestamp: 1719324000000,
            state: .active,
            sourceTimeframe: "H4"
        )
        
        // Run analysis on slice 0..<15 (up to bar 14)
        let sliceA = Array(bars[0..<15])
        let simA = LiquidityEngine.simulate(bars: sliceA, pools: [h4Pool], symbol: "EURUSD", timeframe: "M15")
        
        // Run analysis on full set 0..<25 (appended bars 15..<25)
        let simFull = LiquidityEngine.simulate(bars: bars, pools: [h4Pool], symbol: "EURUSD", timeframe: "M15")
        
        // Filter events from simFull that occurred on or before bar index 14
        let simFullUpTo14 = simFull.allEvents.filter { $0.barIndex < 15 }
        
        // Assert: Events that happened up to bar 14 must be 100% IDENTICAL
        XCTAssertEqual(
            simA.allEvents.count,
            simFullUpTo14.count,
            "Lookahead Invariance Failure: Events on bars 0..<15 changed after appending future bars 15..<25"
        )
        
        for i in 0..<simA.allEvents.count {
            XCTAssertEqual(simA.allEvents[i].barIndex, simFullUpTo14[i].barIndex)
            XCTAssertEqual(simA.allEvents[i].eventType, simFullUpTo14[i].eventType)
            XCTAssertEqual(simA.allEvents[i].sweptPrice, simFullUpTo14[i].sweptPrice)
            XCTAssertEqual(simA.allEvents[i].wickExtreme, simFullUpTo14[i].wickExtreme)
        }
    }
}
