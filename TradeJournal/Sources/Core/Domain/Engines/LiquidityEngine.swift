import Foundation

// MARK: - Institutional Liquidity Engine
// Detects institutional liquidity sweeps (Turtle Soup / SFP) across unmitigated swing levels,
// clustered Equal Highs/Lows (EQH/EQL), calendar-verified Previous Day High/Low (PDH/PDL),
// Previous Week High/Low (PWH/PWL), and Session extremes.
// Employs strictly chronological simulation (t = 0..<n) with zero lookahead bias.
public enum LiquidityEngine: Sendable {
    
    // MARK: - 1. Causal Pivot Identification (Anti-Lookahead)
    
    /// Identifies causal swing high and swing low pivots without lookahead bias.
    /// A swing high is confirmed at bar `formationIndex + window`.
    public static func identifyPivots(bars: [MarketBar], window: Int = 2) -> [LiquiditySwingPivot] {
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
                    confirmedTimestamp: confirmedTs
                ))
            }
            if isLow {
                pivots.append(LiquiditySwingPivot(
                    type: .sellSide,
                    price: cur.low,
                    formationIndex: i,
                    formationTimestamp: cur.timestamp,
                    confirmedAtIndex: confirmedIdx,
                    confirmedTimestamp: confirmedTs
                ))
            }
        }
        
        return pivots.sorted { $0.formationIndex < $1.formationIndex }
    }
    
    // MARK: - 2. Macro Reference Levels (PDH / PDL & PWH / PWL)
    
    /// Resolves true Previous Day High and Previous Day Low from daily bars using UTC day boundaries.
    public static func resolvePreviousDayLevels(d1Bars: [MarketBar], referenceDate: Date = Date()) -> (pdh: Decimal?, pdl: Decimal?) {
        guard !d1Bars.isEmpty else { return (nil, nil) }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        
        let sortedD1 = d1Bars.sorted { $0.timestamp < $1.timestamp }
        let currentDayStart = calendar.startOfDay(for: referenceDate)
        
        let completedDailyBars = sortedD1.filter { bar in
            let barDay = calendar.startOfDay(for: bar.date)
            return barDay < currentDayStart
        }
        
        if let lastCompleted = completedDailyBars.last {
            return (lastCompleted.high, lastCompleted.low)
        }
        
        if sortedD1.count >= 2 {
            let prev = sortedD1[sortedD1.count - 2]
            return (prev.high, prev.low)
        }
        
        return (nil, nil)
    }
    
    /// Resolves Previous Week High and Low from weekly/daily bars.
    public static func resolvePreviousWeekLevels(d1Bars: [MarketBar], referenceDate: Date = Date()) -> (pwh: Decimal?, pwl: Decimal?) {
        guard d1Bars.count >= 5 else { return (nil, nil) }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return (nil, nil) }
        
        let priorWeekBars = d1Bars.filter { bar in
            bar.date < currentWeek.start
        }
        
        guard let lastPriorBar = priorWeekBars.last,
              let priorWeek = calendar.dateInterval(of: .weekOfYear, for: lastPriorBar.date) else {
            return (nil, nil)
        }
        
        let thatWeekBars = priorWeekBars.filter { bar in
            bar.date >= priorWeek.start && bar.date < priorWeek.end
        }
        
        guard !thatWeekBars.isEmpty else { return (nil, nil) }
        let high = thatWeekBars.map(\.high).max()
        let low = thatWeekBars.map(\.low).min()
        return (high, low)
    }
    
    // MARK: - 3. Clustered Equal Highs (EQH) and Equal Lows (EQL)
    
    public static func detectEqualHighsLows(
        pivots: [LiquiditySwingPivot],
        tolerancePercent: Decimal = 0.0015
    ) -> [LiquidityPool] {
        var pools: [LiquidityPool] = []
        
        // 1. Equal Highs (EQH / Buy-Side Liquidity)
        let highs = pivots.filter { $0.type == .buySide }.sorted { $0.price < $1.price }
        var usedHighIndices = Set<Int>()
        for i in 0..<highs.count {
            if usedHighIndices.contains(highs[i].formationIndex) { continue }
            var cluster: [LiquiditySwingPivot] = [highs[i]]
            let basePrice = highs[i].price
            guard basePrice > 0 else { continue }
            
            for j in (i + 1)..<highs.count {
                if usedHighIndices.contains(highs[j].formationIndex) { continue }
                let diff = abs(highs[j].price - basePrice)
                if (diff / basePrice) <= tolerancePercent {
                    cluster.append(highs[j])
                }
            }
            
            if cluster.count >= 2 {
                for sw in cluster {
                    usedHighIndices.insert(sw.formationIndex)
                }
                let clusterPrices = cluster.map(\.price)
                let extreme = clusterPrices.max() ?? basePrice
                let label = cluster.count == 2 ? "Double High (EQH)" : "Triple High (EQH)"
                pools.append(LiquidityPool(
                    type: .buySide,
                    origin: .equalHighsLows,
                    label: label,
                    price: extreme,
                    rangeMin: clusterPrices.min(),
                    rangeMax: extreme,
                    touchCount: cluster.count,
                    formationTimestamp: cluster.last?.formationTimestamp ?? 0,
                    isMitigated: false
                ))
            }
        }
        
        // 2. Equal Lows (EQL / Sell-Side Liquidity)
        let lows = pivots.filter { $0.type == .sellSide }.sorted { $0.price < $1.price }
        var usedLowIndices = Set<Int>()
        for i in 0..<lows.count {
            if usedLowIndices.contains(lows[i].formationIndex) { continue }
            var cluster: [LiquiditySwingPivot] = [lows[i]]
            let basePrice = lows[i].price
            guard basePrice > 0 else { continue }
            
            for j in (i + 1)..<lows.count {
                if usedLowIndices.contains(lows[j].formationIndex) { continue }
                let diff = abs(lows[j].price - basePrice)
                if (diff / basePrice) <= tolerancePercent {
                    cluster.append(lows[j])
                }
            }
            
            if cluster.count >= 2 {
                for sw in cluster {
                    usedLowIndices.insert(sw.formationIndex)
                }
                let clusterPrices = cluster.map(\.price)
                let extreme = clusterPrices.min() ?? basePrice
                let label = cluster.count == 2 ? "Double Low (EQL)" : "Triple Low (EQL)"
                pools.append(LiquidityPool(
                    type: .sellSide,
                    origin: .equalHighsLows,
                    label: label,
                    price: extreme,
                    rangeMin: extreme,
                    rangeMax: clusterPrices.max(),
                    touchCount: cluster.count,
                    formationTimestamp: cluster.last?.formationTimestamp ?? 0,
                    isMitigated: false
                ))
            }
        }
        
        return pools
    }
    
    // MARK: - 4. Chronological Liquidity Simulation & SFP Detection
    
    public struct SimulationOutput: Sendable {
        public let sweeps: [LiquiditySweepEvent]
        public let restingBuySide: [LiquidityPool]
        public let restingSellSide: [LiquidityPool]
        public let pdhSwept: Bool
        public let pdlSwept: Bool
    }
    
    public static func simulate(
        bars: [MarketBar],
        pivots: [LiquiditySwingPivot],
        d1Bars: [MarketBar] = [],
        sessionBarsCount: Int = 24,
        tolerancePercent: Decimal = 0.0015,
        minRejectionWickRatio: Double = 0.15
    ) -> SimulationOutput {
        let n = bars.count
        guard n >= 2 else {
            return SimulationOutput(sweeps: [], restingBuySide: [], restingSellSide: [], pdhSwept: false, pdlSwept: false)
        }
        
        let startIndex = max(0, n - sessionBarsCount)
        let (pdh, pdl) = resolvePreviousDayLevels(d1Bars: d1Bars, referenceDate: bars.last?.date ?? Date())
        
        var pdhSwept = false
        var pdhBroken = false
        var pdlSwept = false
        var pdlBroken = false
        
        var activePivotsHigh: [LiquiditySwingPivot] = []
        var activePivotsLow: [LiquiditySwingPivot] = []
        var sweeps: [LiquiditySweepEvent] = []
        
        var pivotsByConfirmedIndex: [Int: [LiquiditySwingPivot]] = [:]
        for pv in pivots {
            pivotsByConfirmedIndex[pv.confirmedAtIndex, default: []].append(pv)
        }
        
        for t in 0..<n {
            let bar = bars[t]
            let barsAgo = (n - 1) - t
            let range = max(bar.high - bar.low, Decimal(0.00001))
            
            // Ingest pivots confirmed at bar t
            if let newPvs = pivotsByConfirmedIndex[t] {
                for pv in newPvs {
                    if pv.type == .buySide {
                        activePivotsHigh.append(pv)
                    } else {
                        activePivotsLow.append(pv)
                    }
                }
            }
            
            // PDH SFP evaluation
            if let h = pdh, !pdhBroken, !pdhSwept {
                if bar.close > h {
                    pdhBroken = true
                } else if bar.high > h && bar.close < h {
                    let upperWick = bar.high - max(bar.open, bar.close)
                    let wickRatio = Double(truncating: (upperWick / range) as NSNumber)
                    if wickRatio >= minRejectionWickRatio {
                        pdhSwept = true
                        let quality: SweepQuality = wickRatio >= 0.30 ? .highConvictionSFP : .cleanSweep
                        if t >= startIndex {
                            sweeps.append(LiquiditySweepEvent(
                                barIndex: t,
                                timestamp: bar.timestamp,
                                sweepType: .buySideSwept,
                                poolOrigin: .pdhPdl,
                                levelName: "D1 PDH",
                                sweptPrice: h,
                                wickExtreme: bar.high,
                                candleClose: bar.close,
                                penetrationPips: bar.high - h,
                                rejectionWickRatio: wickRatio,
                                sweepQuality: quality,
                                barsAgo: barsAgo,
                                timeframe: "M15"
                            ))
                        }
                    }
                }
            }
            
            // PDL SFP evaluation
            if let l = pdl, !pdlBroken, !pdlSwept {
                if bar.close < l {
                    pdlBroken = true
                } else if bar.low < l && bar.close > l {
                    let lowerWick = min(bar.open, bar.close) - bar.low
                    let wickRatio = Double(truncating: (lowerWick / range) as NSNumber)
                    if wickRatio >= minRejectionWickRatio {
                        pdlSwept = true
                        let quality: SweepQuality = wickRatio >= 0.30 ? .highConvictionSFP : .cleanSweep
                        if t >= startIndex {
                            sweeps.append(LiquiditySweepEvent(
                                barIndex: t,
                                timestamp: bar.timestamp,
                                sweepType: .sellSideSwept,
                                poolOrigin: .pdhPdl,
                                levelName: "D1 PDL",
                                sweptPrice: l,
                                wickExtreme: bar.low,
                                candleClose: bar.close,
                                penetrationPips: l - bar.low,
                                rejectionWickRatio: wickRatio,
                                sweepQuality: quality,
                                barsAgo: barsAgo,
                                timeframe: "M15"
                            ))
                        }
                    }
                }
            }
            
            // Swing High SFP evaluation
            activePivotsHigh = activePivotsHigh.filter { pv in
                if bar.close > pv.price {
                    return false // Mitigated by body close
                }
                if bar.high > pv.price && bar.close < pv.price {
                    let upperWick = bar.high - max(bar.open, bar.close)
                    let wickRatio = Double(truncating: (upperWick / range) as NSNumber)
                    if wickRatio >= minRejectionWickRatio {
                        let quality: SweepQuality = wickRatio >= 0.30 ? .highConvictionSFP : .cleanSweep
                        if t >= startIndex {
                            sweeps.append(LiquiditySweepEvent(
                                barIndex: t,
                                timestamp: bar.timestamp,
                                sweepType: .buySideSwept,
                                poolOrigin: .swingPivot,
                                levelName: "Swing High #\(pv.formationIndex)",
                                sweptPrice: pv.price,
                                wickExtreme: bar.high,
                                candleClose: bar.close,
                                penetrationPips: bar.high - pv.price,
                                rejectionWickRatio: wickRatio,
                                sweepQuality: quality,
                                barsAgo: barsAgo,
                                timeframe: "M15"
                            ))
                        }
                        return false // Consumed by sweep
                    }
                }
                return true
            }
            
            // Swing Low SFP evaluation
            activePivotsLow = activePivotsLow.filter { pv in
                if bar.close < pv.price {
                    return false // Mitigated by body close
                }
                if bar.low < pv.price && bar.close > pv.price {
                    let lowerWick = min(bar.open, bar.close) - bar.low
                    let wickRatio = Double(truncating: (lowerWick / range) as NSNumber)
                    if wickRatio >= minRejectionWickRatio {
                        let quality: SweepQuality = wickRatio >= 0.30 ? .highConvictionSFP : .cleanSweep
                        if t >= startIndex {
                            sweeps.append(LiquiditySweepEvent(
                                barIndex: t,
                                timestamp: bar.timestamp,
                                sweepType: .sellSideSwept,
                                poolOrigin: .swingPivot,
                                levelName: "Swing Low #\(pv.formationIndex)",
                                sweptPrice: pv.price,
                                wickExtreme: bar.low,
                                candleClose: bar.close,
                                penetrationPips: pv.price - bar.low,
                                rejectionWickRatio: wickRatio,
                                sweepQuality: quality,
                                barsAgo: barsAgo,
                                timeframe: "M15"
                            ))
                        }
                        return false // Consumed by sweep
                    }
                }
                return true
            }
        }
        
        let curPrice = bars.last?.close ?? 0
        
        // Convert remaining unmitigated pivots to resting liquidity pools
        var restingBuySide = activePivotsHigh.filter { $0.price > curPrice }.map { pv in
            LiquidityPool(
                type: .buySide,
                origin: .swingPivot,
                label: "Swing High",
                price: pv.price,
                touchCount: 1,
                formationTimestamp: pv.formationTimestamp,
                isMitigated: false
            )
        }
        if let h = pdh, !pdhBroken, !pdhSwept, h > curPrice {
            restingBuySide.append(LiquidityPool(type: .buySide, origin: .pdhPdl, label: "D1 PDH", price: h))
        }
        
        var restingSellSide = activePivotsLow.filter { $0.price < curPrice }.map { pv in
            LiquidityPool(
                type: .sellSide,
                origin: .swingPivot,
                label: "Swing Low",
                price: pv.price,
                touchCount: 1,
                formationTimestamp: pv.formationTimestamp,
                isMitigated: false
            )
        }
        if let l = pdl, !pdlBroken, !pdlSwept, l < curPrice {
            restingSellSide.append(LiquidityPool(type: .sellSide, origin: .pdhPdl, label: "D1 PDL", price: l))
        }
        
        return SimulationOutput(
            sweeps: sweeps.sorted { $0.barIndex > $1.barIndex },
            restingBuySide: restingBuySide.sorted { $0.price < $1.price },
            restingSellSide: restingSellSide.sorted { $0.price > $1.price },
            pdhSwept: pdhSwept,
            pdlSwept: pdlSwept
        )
    }
    
    // MARK: - 5. Comprehensive Liquidity Analysis
    
    public static func analyzeLiquidity(
        symbol: String,
        barsM15: [MarketBar],
        barsH4: [MarketBar] = [],
        barsD1: [MarketBar] = []
    ) -> LiquidityAnalysisResult {
        let curPrice = barsM15.last?.close ?? barsH4.last?.close ?? barsD1.last?.close ?? 0
        
        let (pdh, pdl) = resolvePreviousDayLevels(d1Bars: barsD1, referenceDate: barsM15.last?.date ?? Date())
        let (pwh, pwl) = resolvePreviousWeekLevels(d1Bars: barsD1, referenceDate: barsM15.last?.date ?? Date())
        
        let pivotsM15 = identifyPivots(bars: barsM15, window: 2)
        let sim = simulate(bars: barsM15, pivots: pivotsM15, d1Bars: barsD1, sessionBarsCount: 32)
        
        // Clustered EQH / EQL
        let eqPools = detectEqualHighsLows(pivots: pivotsM15)
        var allBSL = sim.restingBuySide
        for p in eqPools where p.type == .buySide && p.price > curPrice {
            allBSL.append(p)
        }
        allBSL.sort { $0.price < $1.price }
        
        var allSSL = sim.restingSellSide
        for p in eqPools where p.type == .sellSide && p.price < curPrice {
            allSSL.append(p)
        }
        allSSL.sort { $0.price > $1.price }
        
        let nearestBSL = allBSL.first
        let nearestSSL = allSSL.first
        
        let distBSL = nearestBSL.map { $0.price - curPrice }
        let distSSL = nearestSSL.map { curPrice - $0.price }
        
        return LiquidityAnalysisResult(
            symbol: symbol,
            timeframe: "M15",
            currentPrice: curPrice,
            pdh: pdh,
            pdl: pdl,
            pwh: pwh,
            pwl: pwl,
            restingBuySidePools: allBSL,
            restingSellSidePools: allSSL,
            nearestBSL: nearestBSL,
            nearestSSL: nearestSSL,
            distanceToBSLPips: distBSL,
            distanceToSSLPips: distSSL,
            recentSweeps: sim.sweeps,
            latestSweep: sim.sweeps.first
        )
    }
}
