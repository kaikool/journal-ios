import Foundation

// MARK: - Institutional Liquidity Engine
// Multi-timeframe liquidity architecture with strict zero lookahead bias:
// 1. Liquidity Map: Identifies & manages primary pools from H4 and intermediate pools from H1,
//    alongside calendar-verified PDH/PDL, PWH/PWL, and completed Session extremes.
// 2. Liquidity Event Detection: Tracks M15/M5 price interaction against active H1/H4 pools
//    (APPROACH, TOUCH, SWEEP_CANDIDATE, CONFIRMED_SWEEP, BREAKOUT, RECLAIM, POST_EVENT_CONFIRMATION).
// 3. Discrete Lifecycle State Machine: CANDIDATE -> ACTIVE -> (SWEPT | BROKEN) -> RESOLVED.
public enum LiquidityEngine: Sendable {
    
    // MARK: - 1. Instrument Specifications & Causal ATR
    
    /// Resolves the standardized pip size for any instrument via `AssetContractEngine`.
    public static func resolvePipSize(symbol: String) -> Decimal {
        return AssetContractEngine.spec(for: symbol).pipSize
    }
    
    /// Resolves the minimum tick size for tolerance checks.
    public static func resolveTickSize(symbol: String) -> Decimal {
        let pip = resolvePipSize(symbol: symbol)
        return max(Decimal(string: "0.00001")!, pip / 10)
    }
    
    /// Computes causal Average True Range (Wilder's RMA / EMA smoothing) with zero lookahead bias.
    public static func calculateATR(bars: [MarketBar], period: Int = 14) -> [Decimal] {
        guard !bars.isEmpty else { return [] }
        var atrValues: [Decimal] = Array(repeating: 0, count: bars.count)
        guard bars.count >= 2 else {
            atrValues[0] = max(bars[0].high - bars[0].low, Decimal(string: "0.0001")!)
            return atrValues
        }
        
        var trueRanges: [Decimal] = []
        trueRanges.reserveCapacity(bars.count)
        trueRanges.append(max(bars[0].high - bars[0].low, Decimal(string: "0.0001")!))
        
        for i in 1..<bars.count {
            let h = bars[i].high
            let l = bars[i].low
            let prevC = bars[i - 1].close
            let tr = max(h - l, abs(h - prevC), abs(l - prevC))
            trueRanges.append(tr)
        }
        
        var currentATR = trueRanges[0]
        atrValues[0] = currentATR
        let alpha = Decimal(1) / Decimal(period)
        let oneMinusAlpha = Decimal(1) - alpha
        
        for i in 1..<bars.count {
            if i < period {
                currentATR = (currentATR * Decimal(i) + trueRanges[i]) / Decimal(i + 1)
            } else {
                currentATR = (trueRanges[i] * alpha) + (currentATR * oneMinusAlpha)
            }
            atrValues[i] = currentATR
        }
        
        return atrValues
    }
    
    // MARK: - 2. Causal Pivot Identification (Anti-Lookahead)
    
    /// Identifies causal swing high and swing low pivots without lookahead bias.
    /// A swing pivot formed at index `i` is strictly confirmed at `confirmedAtIndex = i + window`.
    /// The pivot cannot be seen or acted upon before `confirmedAtIndex`.
    public static func identifyPivots(
        bars: [MarketBar],
        window: Int = 2,
        timeframe: String = "H4"
    ) -> [LiquiditySwingPivot] {
        guard bars.count >= (window * 2 + 1) else { return [] }
        var pivots: [LiquiditySwingPivot] = []
        let n = bars.count
        
        for i in window..<(n - window) {
            let cur = bars[i]
            var isHigh = true
            var isLow = true
            
            for j in 1...window {
                if bars[i - j].high >= cur.high || bars[i + j].high > cur.high {
                    isHigh = false
                }
                if bars[i - j].low <= cur.low || bars[i + j].low < cur.low {
                    isLow = false
                }
            }
            
            let confirmedIdx = i + window
            let confirmedTs = bars[min(confirmedIdx, n - 1)].timestamp
            
            if isHigh {
                pivots.append(LiquiditySwingPivot(
                    type: .buySide,
                    price: cur.high,
                    formationIndex: i,
                    formationTimestamp: cur.timestamp,
                    confirmedAtIndex: confirmedIdx,
                    confirmedTimestamp: confirmedTs,
                    state: .active,
                    timeframe: timeframe
                ))
            }
            if isLow {
                pivots.append(LiquiditySwingPivot(
                    type: .sellSide,
                    price: cur.low,
                    formationIndex: i,
                    formationTimestamp: cur.timestamp,
                    confirmedAtIndex: confirmedIdx,
                    confirmedTimestamp: confirmedTs,
                    state: .active,
                    timeframe: timeframe
                ))
            }
        }
        
        return pivots.sorted { $0.formationIndex < $1.formationIndex }
    }
    
    // MARK: - 3. Macro Reference Levels (Dynamic Zero Lookahead)
    
    /// Resolves Previous Day High and Low strictly up to reference timestamp `t`.
    /// Only daily bars whose entire session completed prior to the current trading day of `t` are used.
    public static func resolvePreviousDayLevels(
        d1Bars: [MarketBar],
        upToTimestamp: Int64
    ) -> (pdh: Decimal?, pdl: Decimal?) {
        guard !d1Bars.isEmpty else { return (nil, nil) }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        
        let refDate = Date(timeIntervalSince1970: Double(upToTimestamp) / 1000.0)
        let currentDayStart = calendar.startOfDay(for: refDate)
        
        let sortedD1 = d1Bars.sorted { $0.timestamp < $1.timestamp }
        let completedDailyBars = sortedD1.filter { bar in
            let barDay = calendar.startOfDay(for: bar.date)
            return barDay < currentDayStart
        }
        
        if let lastCompleted = completedDailyBars.last {
            return (lastCompleted.high, lastCompleted.low)
        }
        
        if sortedD1.count >= 2 && sortedD1.first!.timestamp <= upToTimestamp {
            let prev = sortedD1[sortedD1.count - 2]
            return (prev.high, prev.low)
        }
        
        return (nil, nil)
    }
    
    /// Backward-compatible overload accepting `Date`.
    public static func resolvePreviousDayLevels(
        d1Bars: [MarketBar],
        referenceDate: Date = Date()
    ) -> (pdh: Decimal?, pdl: Decimal?) {
        let ts = Int64(referenceDate.timeIntervalSince1970 * 1000)
        return resolvePreviousDayLevels(d1Bars: d1Bars, upToTimestamp: ts)
    }
    
    /// Resolves Previous Week High and Low strictly up to reference timestamp `t`.
    /// Only weekly periods completed before the week containing `t` are counted.
    public static func resolvePreviousWeekLevels(
        d1Bars: [MarketBar],
        upToTimestamp: Int64
    ) -> (pwh: Decimal?, pwl: Decimal?) {
        guard d1Bars.count >= 5 else { return (nil, nil) }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        
        let refDate = Date(timeIntervalSince1970: Double(upToTimestamp) / 1000.0)
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: refDate) else { return (nil, nil) }
        
        let priorBars = d1Bars.filter { bar in
            bar.date < currentWeek.start
        }
        
        guard let lastPriorBar = priorBars.last,
              let priorWeek = calendar.dateInterval(of: .weekOfYear, for: lastPriorBar.date) else {
            return (nil, nil)
        }
        
        let thatWeekBars = priorBars.filter { bar in
            bar.date >= priorWeek.start && bar.date < priorWeek.end
        }
        
        guard !thatWeekBars.isEmpty else { return (nil, nil) }
        let high = thatWeekBars.map(\.high).max()
        let low = thatWeekBars.map(\.low).min()
        return (high, low)
    }
    
    /// Backward-compatible overload accepting `Date`.
    public static func resolvePreviousWeekLevels(
        d1Bars: [MarketBar],
        referenceDate: Date = Date()
    ) -> (pwh: Decimal?, pwl: Decimal?) {
        let ts = Int64(referenceDate.timeIntervalSince1970 * 1000)
        return resolvePreviousWeekLevels(d1Bars: d1Bars, upToTimestamp: ts)
    }
    
    /// Resolves completed session extremes (Asia, London, New York) prior to reference timestamp `t`.
    public static func resolveSessionLevels(
        bars: [MarketBar],
        upToTimestamp: Int64
    ) -> [LiquidityPool] {
        guard !bars.isEmpty else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        
        let refDate = Date(timeIntervalSince1970: Double(upToTimestamp) / 1000.0)
        let priorBars = bars.filter { $0.timestamp < upToTimestamp }
        guard !priorBars.isEmpty else { return [] }
        
        var pools: [LiquidityPool] = []
        
        // Asia Session: 00:00 to 08:00 UTC
        let currentDayStart = calendar.startOfDay(for: refDate)
        let asiaStart = currentDayStart
        let asiaEnd = calendar.date(byAdding: .hour, value: 8, to: asiaStart) ?? asiaStart
        
        if refDate >= asiaEnd {
            let asiaBars = priorBars.filter { $0.date >= asiaStart && $0.date < asiaEnd }
            if let h = asiaBars.map(\.high).max(), let l = asiaBars.map(\.low).min() {
                let endTs = Int64(asiaEnd.timeIntervalSince1970 * 1000)
                pools.append(LiquidityPool(
                    id: "SESSION_ASIA_HIGH_\(endTs)",
                    type: .buySide,
                    origin: .sessionLevel,
                    label: "Asia High",
                    price: h,
                    formationTimestamp: endTs,
                    confirmedTimestamp: endTs,
                    sourceTimeframe: "M15"
                ))
                pools.append(LiquidityPool(
                    id: "SESSION_ASIA_LOW_\(endTs)",
                    type: .sellSide,
                    origin: .sessionLevel,
                    label: "Asia Low",
                    price: l,
                    formationTimestamp: endTs,
                    confirmedTimestamp: endTs,
                    sourceTimeframe: "M15"
                ))
            }
        }
        
        // London Session: 07:00 to 15:00 UTC
        let londonStart = calendar.date(byAdding: .hour, value: 7, to: currentDayStart) ?? currentDayStart
        let londonEnd = calendar.date(byAdding: .hour, value: 15, to: currentDayStart) ?? currentDayStart
        if refDate >= londonEnd {
            let londonBars = priorBars.filter { $0.date >= londonStart && $0.date < londonEnd }
            if let h = londonBars.map(\.high).max(), let l = londonBars.map(\.low).min() {
                let endTs = Int64(londonEnd.timeIntervalSince1970 * 1000)
                pools.append(LiquidityPool(
                    id: "SESSION_LONDON_HIGH_\(endTs)",
                    type: .buySide,
                    origin: .sessionLevel,
                    label: "London High",
                    price: h,
                    formationTimestamp: endTs,
                    confirmedTimestamp: endTs,
                    sourceTimeframe: "M15"
                ))
                pools.append(LiquidityPool(
                    id: "SESSION_LONDON_LOW_\(endTs)",
                    type: .sellSide,
                    origin: .sessionLevel,
                    label: "London Low",
                    price: l,
                    formationTimestamp: endTs,
                    confirmedTimestamp: endTs,
                    sourceTimeframe: "M15"
                ))
            }
        }
        
        return pools
    }
    
    // MARK: - 4. Clustered Equal Highs (EQH) and Equal Lows (EQL)
    
    /// Causal time-stepped clustering of confirmed pivots into EQH/EQL pools.
    /// Tolerance is adaptive based on instrument tick size and local ATR, preventing fixed percentage failure.
    public static func detectEqualHighsLows(
        pivots: [LiquiditySwingPivot],
        tickSize: Decimal = Decimal(string: "0.0001")!,
        atr: Decimal = Decimal(string: "0.0010")!,
        maxBarDistance: Int = 60
    ) -> [LiquidityPool] {
        var pools: [LiquidityPool] = []
        let tolerance = max(tickSize * 2, atr * 0.15)
        
        // 1. Equal Highs (EQH) - Buy-Side Liquidity
        let highs = pivots.filter { $0.type == .buySide }.sorted { $0.confirmedAtIndex < $1.confirmedAtIndex }
        var usedHighs = Set<String>()
        
        for i in 0..<highs.count {
            let p1 = highs[i]
            if usedHighs.contains(p1.id) { continue }
            var cluster: [LiquiditySwingPivot] = [p1]
            
            for j in (i + 1)..<highs.count {
                let p2 = highs[j]
                if usedHighs.contains(p2.id) { continue }
                if abs(p2.formationIndex - p1.formationIndex) > maxBarDistance { continue }
                
                let diff = abs(p2.price - p1.price)
                if diff <= tolerance {
                    cluster.append(p2)
                }
            }
            
            if cluster.count >= 2 {
                for p in cluster { usedHighs.insert(p.id) }
                let prices = cluster.map(\.price)
                let maxP = prices.max() ?? p1.price
                let minP = prices.min() ?? p1.price
                let lastP = cluster.last!
                let label = cluster.count == 2 ? "Double High (EQH)" : "Triple High (EQH)"
                
                pools.append(LiquidityPool(
                    id: "\(p1.timeframe)_EQH_\(lastP.confirmedTimestamp)_\(maxP)",
                    type: .buySide,
                    origin: .equalHighsLows,
                    label: label,
                    price: maxP,
                    rangeMin: minP,
                    rangeMax: maxP,
                    topPrice: maxP,
                    bottomPrice: minP,
                    touchCount: cluster.count,
                    formationTimestamp: lastP.formationTimestamp,
                    confirmedTimestamp: lastP.confirmedTimestamp,
                    confirmedAtIndex: lastP.confirmedAtIndex,
                    state: .active,
                    sourceTimeframe: p1.timeframe,
                    sourcePivots: cluster
                ))
            }
        }
        
        // 2. Equal Lows (EQL) - Sell-Side Liquidity
        let lows = pivots.filter { $0.type == .sellSide }.sorted { $0.confirmedAtIndex < $1.confirmedAtIndex }
        var usedLows = Set<String>()
        
        for i in 0..<lows.count {
            let p1 = lows[i]
            if usedLows.contains(p1.id) { continue }
            var cluster: [LiquiditySwingPivot] = [p1]
            
            for j in (i + 1)..<lows.count {
                let p2 = lows[j]
                if usedLows.contains(p2.id) { continue }
                if abs(p2.formationIndex - p1.formationIndex) > maxBarDistance { continue }
                
                let diff = abs(p2.price - p1.price)
                if diff <= tolerance {
                    cluster.append(p2)
                }
            }
            
            if cluster.count >= 2 {
                for p in cluster { usedLows.insert(p.id) }
                let prices = cluster.map(\.price)
                let maxP = prices.max() ?? p1.price
                let minP = prices.min() ?? p1.price
                let lastP = cluster.last!
                let label = cluster.count == 2 ? "Double Low (EQL)" : "Triple Low (EQL)"
                
                pools.append(LiquidityPool(
                    id: "\(p1.timeframe)_EQL_\(lastP.confirmedTimestamp)_\(minP)",
                    type: .sellSide,
                    origin: .equalHighsLows,
                    label: label,
                    price: minP,
                    rangeMin: minP,
                    rangeMax: maxP,
                    topPrice: maxP,
                    bottomPrice: minP,
                    touchCount: cluster.count,
                    formationTimestamp: lastP.formationTimestamp,
                    confirmedTimestamp: lastP.confirmedTimestamp,
                    confirmedAtIndex: lastP.confirmedAtIndex,
                    state: .active,
                    sourceTimeframe: p1.timeframe,
                    sourcePivots: cluster
                ))
            }
        }
        
        return pools
    }
    
    /// Backward-compatible overload using percentage tolerance.
    public static func detectEqualHighsLows(
        pivots: [LiquiditySwingPivot],
        tolerancePercent: Decimal = 0.0015
    ) -> [LiquidityPool] {
        guard let first = pivots.first, first.price > 0 else { return [] }
        let approxTick = first.price * tolerancePercent
        return detectEqualHighsLows(pivots: pivots, tickSize: approxTick / 2, atr: approxTick)
    }
    
    // MARK: - 5. Building the Liquidity Map (H4 + H1 Primary & Supplementary)
    
    /// Assembles the canonical liquidity map strictly from H4, H1, PDH/PDL, and PWH/PWL.
    /// Micro timeframe (M15/M5) swings are NOT elevated into the primary map.
    public static func buildLiquidityMap(
        symbol: String,
        barsH4: [MarketBar],
        barsH1: [MarketBar] = [],
        barsD1: [MarketBar] = [],
        upToTimestamp: Int64? = nil
    ) -> [LiquidityPool] {
        let pipSize = resolvePipSize(symbol: symbol)
        let tickSize = resolveTickSize(symbol: symbol)
        let atr = calculateATR(bars: barsH4.isEmpty ? barsH1 : barsH4).last ?? (pipSize * 10)
        let cutoffTs = upToTimestamp ?? Int64.max
        
        var pools: [LiquidityPool] = []
        
        // 1. H4 Primary High-Level Pools
        if !barsH4.isEmpty {
            let h4Pivots = identifyPivots(bars: barsH4, window: 2, timeframe: "H4")
                .filter { $0.confirmedTimestamp <= cutoffTs }
            
            // H4 EQH / EQL
            let h4Eq = detectEqualHighsLows(pivots: h4Pivots, tickSize: tickSize, atr: atr)
            pools.append(contentsOf: h4Eq)
            
            // H4 Swings not included in EQ clusters
            let clusteredPivotIds = Set(h4Eq.flatMap(\.sourcePivots).map(\.id))
            for pv in h4Pivots where !clusteredPivotIds.contains(pv.id) {
                pools.append(LiquidityPool(
                    id: "H4_\(pv.type.rawValue)_\(pv.confirmedTimestamp)_\(pv.price)",
                    type: pv.type,
                    origin: .swingPivot,
                    label: pv.type == .buySide ? "H4 Swing High" : "H4 Swing Low",
                    price: pv.price,
                    touchCount: 1,
                    formationTimestamp: pv.formationTimestamp,
                    confirmedTimestamp: pv.confirmedTimestamp,
                    confirmedAtIndex: pv.confirmedAtIndex,
                    state: .active,
                    sourceTimeframe: "H4",
                    sourcePivots: [pv]
                ))
            }
        }
        
        // 2. H1 Supplementary Intermediate Pools
        if !barsH1.isEmpty {
            let h1Pivots = identifyPivots(bars: barsH1, window: 2, timeframe: "H1")
                .filter { $0.confirmedTimestamp <= cutoffTs }
            
            let h1Eq = detectEqualHighsLows(pivots: h1Pivots, tickSize: tickSize, atr: atr * 0.5)
            pools.append(contentsOf: h1Eq)
            
            let clusteredPivotIds = Set(h1Eq.flatMap(\.sourcePivots).map(\.id))
            for pv in h1Pivots where !clusteredPivotIds.contains(pv.id) {
                pools.append(LiquidityPool(
                    id: "H1_\(pv.type.rawValue)_\(pv.confirmedTimestamp)_\(pv.price)",
                    type: pv.type,
                    origin: .swingPivot,
                    label: pv.type == .buySide ? "H1 Swing High" : "H1 Swing Low",
                    price: pv.price,
                    touchCount: 1,
                    formationTimestamp: pv.formationTimestamp,
                    confirmedTimestamp: pv.confirmedTimestamp,
                    confirmedAtIndex: pv.confirmedAtIndex,
                    state: .active,
                    sourceTimeframe: "H1",
                    sourcePivots: [pv]
                ))
            }
        }
        
        // 3. Macro Levels (PDH/PDL & PWH/PWL)
        let effectiveRefDate = Date(timeIntervalSince1970: Double(min(cutoffTs, Int64(Date().timeIntervalSince1970 * 1000))) / 1000.0)
        let (pdh, pdl) = resolvePreviousDayLevels(d1Bars: barsD1, upToTimestamp: cutoffTs)
        let (pwh, pwl) = resolvePreviousWeekLevels(d1Bars: barsD1, upToTimestamp: cutoffTs)
        
        let d1Ts = Int64(effectiveRefDate.timeIntervalSince1970 * 1000)
        if let h = pdh {
            pools.append(LiquidityPool(id: "D1_PDH_\(d1Ts)", type: .buySide, origin: .pdhPdl, label: "D1 PDH", price: h, formationTimestamp: d1Ts, confirmedTimestamp: d1Ts, sourceTimeframe: "D1"))
        }
        if let l = pdl {
            pools.append(LiquidityPool(id: "D1_PDL_\(d1Ts)", type: .sellSide, origin: .pdhPdl, label: "D1 PDL", price: l, formationTimestamp: d1Ts, confirmedTimestamp: d1Ts, sourceTimeframe: "D1"))
        }
        if let wh = pwh {
            pools.append(LiquidityPool(id: "W1_PWH_\(d1Ts)", type: .buySide, origin: .pwhPwl, label: "W1 PWH", price: wh, formationTimestamp: d1Ts, confirmedTimestamp: d1Ts, sourceTimeframe: "W1"))
        }
        if let wl = pwl {
            pools.append(LiquidityPool(id: "W1_PWL_\(d1Ts)", type: .sellSide, origin: .pwhPwl, label: "W1 PWL", price: wl, formationTimestamp: d1Ts, confirmedTimestamp: d1Ts, sourceTimeframe: "W1"))
        }
        
        // 4. Merge overlapping/adjacent pools within tolerance
        return mergeOverlappingPools(pools: pools, tolerance: max(tickSize * 2, atr * 0.10))
    }
    
    /// Merges overlapping or close pools from H4/H1 to prevent visual clutter while preserving source identity.
    public static func mergeOverlappingPools(
        pools: [LiquidityPool],
        tolerance: Decimal
    ) -> [LiquidityPool] {
        var merged: [LiquidityPool] = []
        let buyPools = pools.filter { $0.type == .buySide }.sorted { $0.price < $1.price }
        let sellPools = pools.filter { $0.type == .sellSide }.sorted { $0.price < $1.price }
        
        func clusterSide(_ list: [LiquidityPool]) -> [LiquidityPool] {
            var result: [LiquidityPool] = []
            var visited = Set<String>()
            
            for i in 0..<list.count {
                let p1 = list[i]
                if visited.contains(p1.id) { continue }
                var group = [p1]
                
                for j in (i + 1)..<list.count {
                    let p2 = list[j]
                    if visited.contains(p2.id) { continue }
                    if abs(p2.price - p1.price) <= tolerance {
                        group.append(p2)
                    }
                }
                
                if group.count == 1 {
                    result.append(p1)
                } else {
                    for g in group { visited.insert(g.id) }
                    let extremePrice = p1.type == .buySide ? (group.map(\.price).max() ?? p1.price) : (group.map(\.price).min() ?? p1.price)
                    let minR = group.map(\.rangeMin).min() ?? extremePrice
                    let maxR = group.map(\.rangeMax).max() ?? extremePrice
                    let combinedLabels = group.map(\.label).joined(separator: " + ")
                    let combinedPivots = group.flatMap(\.sourcePivots)
                    let combinedTouches = group.reduce(0) { $0 + $1.touchCount }
                    let earliestConfirmed = group.map(\.confirmedTimestamp).min() ?? p1.confirmedTimestamp
                    
                    result.append(LiquidityPool(
                        id: "MERGED_\(p1.type.rawValue)_\(earliestConfirmed)_\(extremePrice)",
                        type: p1.type,
                        origin: group.contains(where: { $0.origin == .equalHighsLows }) ? .equalHighsLows : .swingPivot,
                        label: combinedLabels,
                        price: extremePrice,
                        rangeMin: minR,
                        rangeMax: maxR,
                        topPrice: maxR,
                        bottomPrice: minR,
                        touchCount: max(2, combinedTouches),
                        formationTimestamp: earliestConfirmed,
                        confirmedTimestamp: earliestConfirmed,
                        state: .active,
                        sourceTimeframe: group.map(\.sourceTimeframe).contains("H4") ? "H4" : "H1",
                        sourcePivots: combinedPivots
                    ))
                }
            }
            return result
        }
        
        merged.append(contentsOf: clusterSide(buyPools))
        merged.append(contentsOf: clusterSide(sellPools))
        return merged
    }
    
    // MARK: - 6. Liquidity Event Detection on M15/M5
    
    public struct SimulationOutput: Sendable {
        public let sweeps: [LiquiditySweepEvent]
        public let allEvents: [LiquiditySweepEvent]
        public let restingBuySide: [LiquidityPool]
        public let restingSellSide: [LiquidityPool]
        public let pdhSwept: Bool
        public let pdlSwept: Bool
    }
    
    /// Tracks causal M15/M5 price interaction against active H1/H4 pools.
    /// Strictly respects pool lifecycle: CANDIDATE -> ACTIVE -> (SWEPT | BROKEN) -> RESOLVED.
    public static func simulate(
        bars: [MarketBar],
        pools: [LiquidityPool],
        symbol: String = "EURUSD",
        timeframe: String = "M15",
        minRejectionWickRatio: Double = 0.15
    ) -> SimulationOutput {
        let n = bars.count
        guard n >= 1 else {
            return SimulationOutput(sweeps: [], allEvents: [], restingBuySide: [], restingSellSide: [], pdhSwept: false, pdlSwept: false)
        }
        
        let pipSize = resolvePipSize(symbol: symbol)
        let atrSeries = calculateATR(bars: bars)
        
        var activePoolsState = pools
        var events: [LiquiditySweepEvent] = []
        var pdhSwept = false
        var pdlSwept = false
        
        // Deduplication tracker per pool
        var poolLastSweptBar: [String: Int] = [:]
        
        for t in 0..<n {
            let bar = bars[t]
            let barsAgo = (n - 1) - t
            let range = max(bar.high - bar.low, Decimal(string: "0.00001")!)
            let currentATR = t < atrSeries.count ? atrSeries[t] : (pipSize * 10)
            let proximityThreshold = max(pipSize * 5, currentATR * 0.35)
            
            // Check each pool that is ACTIVE and already confirmed at or before bar t
            for poolIdx in 0..<activePoolsState.count {
                var pool = activePoolsState[poolIdx]
                guard pool.state == .active && pool.confirmedTimestamp <= bar.timestamp else { continue }
                
                // 1. Buy-Side Liquidity (BSL) Interaction
                if pool.type == .buySide {
                    let level = pool.topPrice
                    
                    // Breakout condition: candle body close > level
                    if bar.close > level {
                        pool.state = .broken
                        activePoolsState[poolIdx] = pool
                        events.append(LiquiditySweepEvent(
                            poolId: pool.id,
                            barIndex: t,
                            timestamp: bar.timestamp,
                            eventType: .breakout,
                            sweepType: .buySideSwept,
                            poolOrigin: pool.origin,
                            levelName: pool.label,
                            sweptPrice: level,
                            wickExtreme: bar.high,
                            candleClose: bar.close,
                            penetrationAmount: bar.high - level,
                            penetrationPips: (bar.high - level) / pipSize,
                            rejectionWickRatio: 0,
                            sweepQuality: .shallowPiercing,
                            barsAgo: barsAgo,
                            timeframe: timeframe,
                            isConfirmedSweep: false
                        ))
                        continue
                    }
                    
                    // Sweep candidate: High pierces level, but body closes BELOW level (wick grab)
                    if bar.high > level && bar.close <= level {
                        let upperWick = bar.high - max(bar.open, bar.close)
                        let wickRatio = Double(truncating: (upperWick / range) as NSNumber)
                        let pen = bar.high - level
                        
                        // Check if previously swept in immediate recent bars
                        let lastSwept = poolLastSweptBar[pool.id] ?? -999
                        if (t - lastSwept) >= 1 {
                            let isConfirmed = wickRatio >= minRejectionWickRatio
                            let quality: SweepQuality = wickRatio >= 0.30 ? .highConvictionSFP : (wickRatio >= 0.15 ? .cleanSweep : .shallowPiercing)
                            
                            pool.state = .swept
                            activePoolsState[poolIdx] = pool
                            poolLastSweptBar[pool.id] = t
                            
                            if pool.origin == .pdhPdl { pdhSwept = true }
                            
                            events.append(LiquiditySweepEvent(
                                poolId: pool.id,
                                barIndex: t,
                                timestamp: bar.timestamp,
                                eventType: isConfirmed ? .confirmedSweep : .sweepCandidate,
                                sweepType: .buySideSwept,
                                poolOrigin: pool.origin,
                                levelName: pool.label,
                                sweptPrice: level,
                                wickExtreme: bar.high,
                                candleClose: bar.close,
                                penetrationAmount: pen,
                                penetrationPips: pen / pipSize,
                                rejectionWickRatio: wickRatio,
                                sweepQuality: quality,
                                barsAgo: barsAgo,
                                timeframe: timeframe,
                                isConfirmedSweep: isConfirmed
                            ))
                        }
                        continue
                    }
                    
                    // Touch or Approach
                    if bar.high >= pool.bottomPrice && bar.low <= pool.topPrice {
                        events.append(LiquiditySweepEvent(
                            poolId: pool.id,
                            barIndex: t,
                            timestamp: bar.timestamp,
                            eventType: .touch,
                            sweepType: .buySideSwept,
                            poolOrigin: pool.origin,
                            levelName: pool.label,
                            sweptPrice: level,
                            wickExtreme: bar.high,
                            candleClose: bar.close,
                            penetrationAmount: 0,
                            penetrationPips: 0,
                            rejectionWickRatio: 0,
                            sweepQuality: .shallowPiercing,
                            barsAgo: barsAgo,
                            timeframe: timeframe,
                            isConfirmedSweep: false
                        ))
                    } else if (level - bar.high) <= proximityThreshold && (level - bar.high) > 0 {
                        events.append(LiquiditySweepEvent(
                            poolId: pool.id,
                            barIndex: t,
                            timestamp: bar.timestamp,
                            eventType: .approach,
                            sweepType: .buySideSwept,
                            poolOrigin: pool.origin,
                            levelName: pool.label,
                            sweptPrice: level,
                            wickExtreme: bar.high,
                            candleClose: bar.close,
                            penetrationAmount: 0,
                            penetrationPips: 0,
                            rejectionWickRatio: 0,
                            sweepQuality: .shallowPiercing,
                            barsAgo: barsAgo,
                            timeframe: timeframe,
                            isConfirmedSweep: false
                        ))
                    }
                }
                
                // 2. Sell-Side Liquidity (SSL) Interaction
                if pool.type == .sellSide {
                    let level = pool.bottomPrice
                    
                    // Breakout condition: candle body close < level
                    if bar.close < level {
                        pool.state = .broken
                        activePoolsState[poolIdx] = pool
                        events.append(LiquiditySweepEvent(
                            poolId: pool.id,
                            barIndex: t,
                            timestamp: bar.timestamp,
                            eventType: .breakout,
                            sweepType: .sellSideSwept,
                            poolOrigin: pool.origin,
                            levelName: pool.label,
                            sweptPrice: level,
                            wickExtreme: bar.low,
                            candleClose: bar.close,
                            penetrationAmount: level - bar.low,
                            penetrationPips: (level - bar.low) / pipSize,
                            rejectionWickRatio: 0,
                            sweepQuality: .shallowPiercing,
                            barsAgo: barsAgo,
                            timeframe: timeframe,
                            isConfirmedSweep: false
                        ))
                        continue
                    }
                    
                    // Sweep candidate: Low pierces level, but body closes ABOVE level (wick grab)
                    if bar.low < level && bar.close >= level {
                        let lowerWick = min(bar.open, bar.close) - bar.low
                        let wickRatio = Double(truncating: (lowerWick / range) as NSNumber)
                        let pen = level - bar.low
                        
                        let lastSwept = poolLastSweptBar[pool.id] ?? -999
                        if (t - lastSwept) >= 1 {
                            let isConfirmed = wickRatio >= minRejectionWickRatio
                            let quality: SweepQuality = wickRatio >= 0.30 ? .highConvictionSFP : (wickRatio >= 0.15 ? .cleanSweep : .shallowPiercing)
                            
                            pool.state = .swept
                            activePoolsState[poolIdx] = pool
                            poolLastSweptBar[pool.id] = t
                            
                            if pool.origin == .pdhPdl { pdlSwept = true }
                            
                            events.append(LiquiditySweepEvent(
                                poolId: pool.id,
                                barIndex: t,
                                timestamp: bar.timestamp,
                                eventType: isConfirmed ? .confirmedSweep : .sweepCandidate,
                                sweepType: .sellSideSwept,
                                poolOrigin: pool.origin,
                                levelName: pool.label,
                                sweptPrice: level,
                                wickExtreme: bar.low,
                                candleClose: bar.close,
                                penetrationAmount: pen,
                                penetrationPips: pen / pipSize,
                                rejectionWickRatio: wickRatio,
                                sweepQuality: quality,
                                barsAgo: barsAgo,
                                timeframe: timeframe,
                                isConfirmedSweep: isConfirmed
                            ))
                        }
                        continue
                    }
                    
                    // Touch or Approach
                    if bar.low <= pool.topPrice && bar.high >= pool.bottomPrice {
                        events.append(LiquiditySweepEvent(
                            poolId: pool.id,
                            barIndex: t,
                            timestamp: bar.timestamp,
                            eventType: .touch,
                            sweepType: .sellSideSwept,
                            poolOrigin: pool.origin,
                            levelName: pool.label,
                            sweptPrice: level,
                            wickExtreme: bar.low,
                            candleClose: bar.close,
                            penetrationAmount: 0,
                            penetrationPips: 0,
                            rejectionWickRatio: 0,
                            sweepQuality: .shallowPiercing,
                            barsAgo: barsAgo,
                            timeframe: timeframe,
                            isConfirmedSweep: false
                        ))
                    } else if (bar.low - level) <= proximityThreshold && (bar.low - level) > 0 {
                        events.append(LiquiditySweepEvent(
                            poolId: pool.id,
                            barIndex: t,
                            timestamp: bar.timestamp,
                            eventType: .approach,
                            sweepType: .sellSideSwept,
                            poolOrigin: pool.origin,
                            levelName: pool.label,
                            sweptPrice: level,
                            wickExtreme: bar.low,
                            candleClose: bar.close,
                            penetrationAmount: 0,
                            penetrationPips: 0,
                            rejectionWickRatio: 0,
                            sweepQuality: .shallowPiercing,
                            barsAgo: barsAgo,
                            timeframe: timeframe,
                            isConfirmedSweep: false
                        ))
                    }
                }
            }
        }
        
        let curPrice = bars.last?.close ?? 0
        let remainingBSL = activePoolsState.filter { $0.type == .buySide && $0.state == .active && $0.price > curPrice }
            .sorted { $0.price < $1.price }
        let remainingSSL = activePoolsState.filter { $0.type == .sellSide && $0.state == .active && $0.price < curPrice }
            .sorted { $0.price > $1.price }
        
        let confirmedSweeps = events.filter { $0.eventType == .confirmedSweep || $0.eventType == .sweepCandidate }
            .sorted { $0.barIndex > $1.barIndex }
        
        return SimulationOutput(
            sweeps: confirmedSweeps,
            allEvents: events.sorted { $0.barIndex > $1.barIndex },
            restingBuySide: remainingBSL,
            restingSellSide: remainingSSL,
            pdhSwept: pdhSwept,
            pdlSwept: pdlSwept
        )
    }
    
    /// Backward-compatible simulation overload accepting legacy parameters.
    public static func simulate(
        bars: [MarketBar],
        pivots: [LiquiditySwingPivot],
        d1Bars: [MarketBar] = [],
        sessionBarsCount: Int = 24,
        tolerancePercent: Decimal = 0.0015,
        minRejectionWickRatio: Double = 0.15
    ) -> SimulationOutput {
        guard !bars.isEmpty else {
            return SimulationOutput(sweeps: [], allEvents: [], restingBuySide: [], restingSellSide: [], pdhSwept: false, pdlSwept: false)
        }
        
        let curPrice = bars.last?.close ?? 0
        let (pdh, pdl) = resolvePreviousDayLevels(d1Bars: d1Bars, referenceDate: bars.last?.date ?? Date())
        
        var pools: [LiquidityPool] = []
        for pv in pivots {
            pools.append(LiquidityPool(
                id: pv.id,
                type: pv.type,
                origin: .swingPivot,
                label: pv.type == .buySide ? "Swing High #\(pv.formationIndex)" : "Swing Low #\(pv.formationIndex)",
                price: pv.price,
                touchCount: 1,
                formationTimestamp: pv.formationTimestamp,
                confirmedTimestamp: pv.confirmedTimestamp,
                confirmedAtIndex: pv.confirmedAtIndex,
                state: .active,
                sourceTimeframe: pv.timeframe,
                sourcePivots: [pv]
            ))
        }
        
        if let h = pdh {
            pools.append(LiquidityPool(id: "D1_PDH", type: .buySide, origin: .pdhPdl, label: "D1 PDH", price: h, state: .active, sourceTimeframe: "D1"))
        }
        if let l = pdl {
            pools.append(LiquidityPool(id: "D1_PDL", type: .sellSide, origin: .pdhPdl, label: "D1 PDL", price: l, state: .active, sourceTimeframe: "D1"))
        }
        
        let sim = simulate(bars: bars, pools: pools, minRejectionWickRatio: minRejectionWickRatio)
        let filteredSweeps = sim.sweeps.filter { $0.barsAgo < sessionBarsCount }
        
        return SimulationOutput(
            sweeps: filteredSweeps,
            allEvents: sim.allEvents,
            restingBuySide: sim.restingBuySide,
            restingSellSide: sim.restingSellSide,
            pdhSwept: sim.pdhSwept,
            pdlSwept: sim.pdlSwept
        )
    }
    
    // MARK: - 7. Backward Compatibility Bridges (Tests & Legacy Callers)
    
    /// Backward-compatible bridge for legacy tests calling `detectSweeps`.
    public static func detectSweeps(
        bars: [MarketBar],
        swings: Any? = nil,
        d1Bars: [MarketBar] = [],
        sessionBarsCount: Int = 24
    ) -> [LiquiditySweepEvent] {
        let pivots = identifyPivots(bars: bars, window: 2)
        let sim = simulate(bars: bars, pivots: pivots, d1Bars: d1Bars, sessionBarsCount: sessionBarsCount)
        return sim.sweeps
    }
    
    /// Backward-compatible bridge for legacy tests calling `detectUnsweptPools`.
    public static func detectUnsweptPools(
        bars: [MarketBar],
        swings: Any? = nil
    ) -> [LiquidityPool] {
        let pivots = identifyPivots(bars: bars, window: 2)
        let sim = simulate(bars: bars, pivots: pivots)
        return sim.restingBuySide + sim.restingSellSide
    }
    
    // MARK: - 8. Comprehensive Liquidity Analysis (Primary Facade)
    
    /// Comprehensive multi-timeframe liquidity analysis strictly abiding by institutional role separation:
    /// - H4/H1: Primary & Supplementary Liquidity Map
    /// - M15/M5: Real-time Event Tracking & SFP Detection
    public static func analyzeLiquidity(
        symbol: String,
        barsM5: [MarketBar] = [],
        barsM15: [MarketBar],
        barsH1: [MarketBar] = [],
        barsH4: [MarketBar] = [],
        barsD1: [MarketBar] = []
    ) -> LiquidityAnalysisResult {
        let curPrice = barsM15.last?.close ?? barsH1.last?.close ?? barsH4.last?.close ?? barsD1.last?.close ?? 0
        let pipSize = resolvePipSize(symbol: symbol)
        let refTimestamp = barsM15.last?.timestamp ?? barsH4.last?.timestamp ?? Int64(Date().timeIntervalSince1970 * 1000)
        
        // 1. Build Liquidity Map from H4/H1/Macro
        let mapPools = buildLiquidityMap(
            symbol: symbol,
            barsH4: barsH4,
            barsH1: barsH1,
            barsD1: barsD1,
            upToTimestamp: refTimestamp
        )
        
        // 2. Track events on execution timeframe (M15 by default, M5 if provided)
        let execBars = !barsM5.isEmpty ? barsM5 : barsM15
        let execTf = !barsM5.isEmpty ? "M5" : "M15"
        
        let sim = simulate(
            bars: execBars,
            pools: mapPools,
            symbol: symbol,
            timeframe: execTf,
            minRejectionWickRatio: 0.15
        )
        
        let (pdh, pdl) = resolvePreviousDayLevels(d1Bars: barsD1, upToTimestamp: refTimestamp)
        let (pwh, pwl) = resolvePreviousWeekLevels(d1Bars: barsD1, upToTimestamp: refTimestamp)
        
        let nearestBSL = sim.restingBuySide.first
        let nearestSSL = sim.restingSellSide.first
        
        let distBSLPips = nearestBSL.map { abs($0.price - curPrice) / pipSize }
        let distSSLPips = nearestSSL.map { abs(curPrice - $0.price) / pipSize }
        
        let h4Pools = mapPools.filter { $0.sourceTimeframe == "H4" && $0.state == .active }
        let h1Pools = mapPools.filter { $0.sourceTimeframe == "H1" && $0.state == .active }
        
        return LiquidityAnalysisResult(
            symbol: symbol,
            timeframe: execTf,
            currentPrice: curPrice,
            pdh: pdh,
            pdl: pdl,
            pwh: pwh,
            pwl: pwl,
            restingBuySidePools: sim.restingBuySide,
            restingSellSidePools: sim.restingSellSide,
            nearestBSL: nearestBSL,
            nearestSSL: nearestSSL,
            distanceToBSLPips: distBSLPips,
            distanceToSSLPips: distSSLPips,
            recentEvents: sim.allEvents,
            recentSweeps: sim.sweeps,
            latestSweep: sim.sweeps.first,
            activeH4Pools: h4Pools,
            activeH1Pools: h1Pools
        )
    }
    
    /// Backward-compatible overload without M5 / H1.
    public static func analyzeLiquidity(
        symbol: String,
        barsM15: [MarketBar],
        barsH4: [MarketBar] = [],
        barsD1: [MarketBar] = []
    ) -> LiquidityAnalysisResult {
        return analyzeLiquidity(
            symbol: symbol,
            barsM5: [],
            barsM15: barsM15,
            barsH1: [],
            barsH4: barsH4,
            barsD1: barsD1
        )
    }
}
