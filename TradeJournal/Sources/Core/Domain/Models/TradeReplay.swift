import Foundation

public enum MarketResolution: String, CaseIterable, Identifiable, Sendable {
    case m1 = "1m"
    case m5 = "5m"
    case m15 = "15m"
    case h1 = "1h"
    case h4 = "4h"
    case d1 = "1d"
    
    public var id: String { rawValue }
    
    public var durationMs: Int64 {
        switch self {
        case .m1: return 60_000
        case .m5: return 300_000
        case .m15: return 900_000
        case .h1: return 3_600_000
        case .h4: return 14_400_000
        case .d1: return 86_400_000
        }
    }
}

public struct MarketBar: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64 { timestamp }
    public let timestamp: Int64 // ms epoch (UTC bar-open timestamp)
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal
    public let volume: Decimal
    
    public var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }
    
    public var isUp: Bool {
        close >= open
    }
    
    public init(timestamp: Int64, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volume: Decimal) {
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

public struct ExcursionEstimate: Codable, Sendable, Equatable {
    public let mae: Decimal?
    public let mfe: Decimal?
    public let sampledBars: Int
    public let excludedBars: Int
    public let warnings: [String]
    public let priceBasisMismatch: Bool
    public let maePrice: Decimal?
    public let mfePrice: Decimal?
    public let maePoints: Decimal?
    public let mfePoints: Decimal?
    
    public init(
        mae: Decimal? = nil,
        mfe: Decimal? = nil,
        sampledBars: Int = 0,
        excludedBars: Int = 0,
        warnings: [String] = [],
        priceBasisMismatch: Bool = false,
        maePrice: Decimal? = nil,
        mfePrice: Decimal? = nil,
        maePoints: Decimal? = nil,
        mfePoints: Decimal? = nil
    ) {
        self.mae = mae
        self.mfe = mfe
        self.sampledBars = sampledBars
        self.excludedBars = excludedBars
        self.warnings = warnings
        self.priceBasisMismatch = priceBasisMismatch
        self.maePrice = maePrice
        self.mfePrice = mfePrice
        self.maePoints = maePoints
        self.mfePoints = mfePoints
    }
}

public struct ReplayFrame: Sendable {
    public let visibleBars: [MarketBar]
    public let throughTimestamp: Int64
    public let activeFills: [Execution]
    public let unrealizedPnl: Decimal
    public let currentBar: MarketBar?
    public let hasEntered: Bool
    public let hasExited: Bool
    
    public init(
        visibleBars: [MarketBar],
        throughTimestamp: Int64,
        activeFills: [Execution],
        unrealizedPnl: Decimal,
        currentBar: MarketBar? = nil,
        hasEntered: Bool = false,
        hasExited: Bool = false
    ) {
        self.visibleBars = visibleBars
        self.throughTimestamp = throughTimestamp
        self.activeFills = activeFills
        self.unrealizedPnl = unrealizedPnl
        self.currentBar = currentBar ?? visibleBars.last
        self.hasEntered = hasEntered
        self.hasExited = hasExited
    }
}

public enum TradeReplayEngine {
    
    public static func frame(
        bars: [MarketBar],
        fills: [Execution],
        trade: Trade,
        barIndex: Int,
        resolution: MarketResolution = .m15
    ) -> ReplayFrame {
        let clampedIndex = max(0, min(bars.count, barIndex))
        let visible = Array(bars.prefix(clampedIndex))
        
        guard let lastBar = visible.last else {
            return ReplayFrame(
                visibleBars: [],
                throughTimestamp: 0,
                activeFills: [],
                unrealizedPnl: 0,
                currentBar: nil,
                hasEntered: false,
                hasExited: false
            )
        }
        
        let through = lastBar.timestamp + resolution.durationMs
        let currentFills = fills.filter { Int64($0.executedAt.timeIntervalSince1970 * 1000) <= through }
        
        let entryTimeMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let exitTimeMs: Int64? = trade.closedAt.map { Int64($0.timeIntervalSince1970 * 1000) }
        
        let hasEntered = through >= entryTimeMs
        let hasExited = exitTimeMs != nil && through >= exitTimeMs!
        let isLast = clampedIndex >= bars.count
        
        // Accurate entry gating: unrealized PnL is 0 until position is actually entered
        let unrealized: Decimal = {
            if !hasEntered {
                return 0
            }
            if hasExited || (isLast && trade.status != .open) {
                return trade.netPnl
            }
            return computeUnrealizedPnl(
                trade: trade,
                currentPrice: lastBar.close,
                isLastBar: isLast
            )
        }()
        
        return ReplayFrame(
            visibleBars: visible,
            throughTimestamp: through,
            activeFills: currentFills,
            unrealizedPnl: unrealized,
            currentBar: lastBar,
            hasEntered: hasEntered,
            hasExited: hasExited
        )
    }
    
    /// Accurately computes mark-to-market Unrealized P&L at any candlestick bar close
    public static func computeUnrealizedPnl(
        trade: Trade,
        currentPrice: Decimal,
        isLastBar: Bool
    ) -> Decimal {
        if trade.status != .open && isLastBar {
            return trade.netPnl
        }
        
        let priceDelta: Decimal = (trade.direction == .long)
            ? (currentPrice - trade.avgEntry)
            : (trade.avgEntry - currentPrice)
        
        // Method 1: If closed trade has an exit price, compute empirical dollar value per price unit
        if let exit = trade.avgExit {
            let totalExitDelta = (trade.direction == .long) ? (exit - trade.avgEntry) : (trade.avgEntry - exit)
            if abs(totalExitDelta) > 0.00001 && abs(trade.grossPnl) > 0 {
                let dollarPerPoint = trade.grossPnl / totalExitDelta
                let grossAtBar = priceDelta * dollarPerPoint
                let feeShare = isLastBar ? trade.fees : (trade.fees * 0.5)
                return grossAtBar - feeShare
            }
        }
        
        // Method 2: Contract multiplier fallback with accurate commodity, index, and forex specifications
        let multiplier: Decimal = {
            if let cm = trade.contractMultiplier, cm > 0 {
                return cm
            }
            return AssetContractEngine.contractMultiplier(for: trade.symbol)
        }()
        
        let grossAtBar = priceDelta * trade.quantity * multiplier
        let feeShare = isLastBar ? trade.fees : (trade.fees * 0.5)
        return grossAtBar - feeShare
    }
    
    /// Computes MAE (Maximum Adverse Excursion) and MFE (Maximum Favorable Excursion)
    /// Accurately accounts for asset multipliers, empirical dollar-per-point, and true holding period extremes.
    public static func estimateExcursions(
        trade: Trade,
        fills: [Execution],
        bars: [MarketBar],
        resolution: MarketResolution = .m15
    ) -> ExcursionEstimate {
        guard trade.avgEntry > 0 else {
            return ExcursionEstimate(warnings: ["Missing valid entry price."])
        }
        
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs = Int64((trade.closedAt ?? Date()).timeIntervalSince1970 * 1000)
        let step = resolution.durationMs
        
        // Filter candles that overlap with trade holding window [openMs, closeMs]
        // A candle [t, t + step] overlaps if t <= closeMs and t + step >= openMs
        let tradeBars = bars.filter { bar in
            bar.timestamp <= closeMs && (bar.timestamp + step) >= openMs
        }
        
        var candidateLows: [Decimal] = [trade.avgEntry]
        var candidateHighs: [Decimal] = [trade.avgEntry]
        
        if let exit = trade.avgExit, exit > 0 {
            candidateLows.append(exit)
            candidateHighs.append(exit)
        }
        
        for fill in fills {
            if fill.price > 0 {
                candidateLows.append(fill.price)
                candidateHighs.append(fill.price)
            }
        }
        
        for bar in tradeBars {
            if bar.low > 0 { candidateLows.append(bar.low) }
            if bar.high > 0 { candidateHighs.append(bar.high) }
        }
        
        let minPrice = candidateLows.min() ?? trade.avgEntry
        let maxPrice = candidateHighs.max() ?? trade.avgEntry
        
        let isLong = trade.direction == .long
        let maePrice = isLong ? minPrice : maxPrice
        let mfePrice = isLong ? maxPrice : minPrice
        
        let maePoints = isLong ? (minPrice - trade.avgEntry) : (trade.avgEntry - maxPrice)
        let mfePoints = isLong ? (maxPrice - trade.avgEntry) : (trade.avgEntry - minPrice)
        
        // Mark-to-market dollar conversion using asset contract specifications & empirical dollarPerPoint
        var maeDollar = computeUnrealizedPnl(trade: trade, currentPrice: maePrice, isLastBar: false)
        var mfeDollar = computeUnrealizedPnl(trade: trade, currentPrice: mfePrice, isLastBar: false)
        
        // MAE is maximum adverse excursion (drawdown), so it must be <= 0
        if maeDollar > 0 { maeDollar = 0 }
        // If the closed trade finished with a net loss, MAE must be at least as severe as net loss
        if trade.status != .open && trade.netPnl < 0 {
            maeDollar = min(maeDollar, trade.netPnl)
        }
        
        // MFE is maximum favorable excursion (runup), so it must be >= 0
        if mfeDollar < 0 { mfeDollar = 0 }
        // If the closed trade finished with a net profit, MFE must be at least as high as net profit
        if trade.status != .open && trade.netPnl > 0 {
            mfeDollar = max(mfeDollar, trade.netPnl)
        }
        
        return ExcursionEstimate(
            mae: maeDollar,
            mfe: mfeDollar,
            sampledBars: tradeBars.count,
            excludedBars: max(0, bars.count - tradeBars.count),
            warnings: [
                "MAE/MFE estimates based on candles & fills during trade holding period.",
                "Computed using contract multiplier & broker trade delta."
            ],
            priceBasisMismatch: false,
            maePrice: maePrice,
            mfePrice: mfePrice,
            maePoints: min(0, maePoints),
            mfePoints: max(0, mfePoints)
        )
    }
    
    /// Generates distinct, time-stepped candlesticks representing trade progress when external candle feeds are offline
    public static func generateBarsFromTrade(
        trade: Trade,
        fills: [Execution],
        resolution: MarketResolution = .m15
    ) -> [MarketBar] {
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs: Int64 = {
            if trade.status == .open {
                // For open trades, extend candles to current time
                return Int64(Date().timeIntervalSince1970 * 1000)
            }
            if let c = trade.closedAt {
                return Int64(c.timeIntervalSince1970 * 1000)
            } else if let dur = trade.durationMs, dur > 0 {
                return openMs + dur
            } else {
                return openMs + resolution.durationMs * 4
            }
        }()
        
        let step = resolution.durationMs
        let preBars = 80
        let postBars = trade.status == .open ? 0 : 15
        let startTimestamp = openMs - Int64(preBars) * step
        let endTimestamp = max(startTimestamp + Int64(preBars + postBars + 1) * step, closeMs + Int64(postBars) * step)
        
        let exactSteps = Int((endTimestamp - startTimestamp) / step) + 1
        let totalSteps = max(80, min(300, exactSteps))
        var bars: [MarketBar] = []
        
        let entryPrice = (trade.avgEntry as NSDecimalNumber).doubleValue
        let exitPrice: Double
        let isShort = trade.direction == .short
        if trade.status == .open {
            // For open trades, estimate current price from unrealized PnL and trade direction
            let mult = (trade.netPnl > 0) ? (isShort ? -0.003 : 0.003) : (isShort ? 0.003 : -0.003)
            exitPrice = entryPrice + mult * entryPrice
        } else {
            let mult = (trade.netPnl > 0) ? (isShort ? -0.005 : 0.005) : (isShort ? 0.005 : -0.005)
            exitPrice = trade.avgExit.map { ($0 as NSDecimalNumber).doubleValue } ?? (entryPrice + mult * entryPrice)
        }
        let priceSpan = exitPrice - entryPrice
        
        for i in 0..<totalSteps {
            let t = startTimestamp + Int64(i) * step
            let progress = min(1.0, max(0.0, Double(t - openMs) / Double(max(1, closeMs - openMs))))
            
            let basePrice = entryPrice + progress * priceSpan
            let variance = abs(entryPrice) * 0.0015 * sin(Double(i) * 0.8)
            let currentClose = basePrice + variance
            let previousClose = i > 0 ? (bars[i - 1].close as NSDecimalNumber).doubleValue : (basePrice - variance)
            
            let high = max(previousClose, currentClose) + abs(entryPrice) * 0.0012
            let low = min(previousClose, currentClose) - abs(entryPrice) * 0.0012
            let vol = (trade.quantity as NSDecimalNumber).doubleValue * (0.8 + 0.4 * abs(sin(Double(i))))
            
            bars.append(MarketBar(
                timestamp: t,
                open: Decimal(previousClose),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(currentClose),
                volume: Decimal(vol)
            ))
        }
        
        return bars
    }
    
    /// Resamples lower-timeframe candles into higher-timeframe candles using standard OHLCV bucket aggregation.
    /// For example, 12 x 5m candles → 1 x 1h candle. Timestamps are aligned to resolution boundaries.
    public static func resampleBars(_ bars: [MarketBar], to resolution: MarketResolution) -> [MarketBar] {
        guard !bars.isEmpty else { return [] }
        let step = resolution.durationMs
        
        // Group bars into buckets by flooring timestamp to resolution boundary
        var buckets: [Int64: [MarketBar]] = [:]
        var bucketOrder: [Int64] = []
        
        for bar in bars {
            let bucketTs = bar.timestamp - (bar.timestamp % step)
            if buckets[bucketTs] == nil {
                bucketOrder.append(bucketTs)
            }
            buckets[bucketTs, default: []].append(bar)
        }
        
        return bucketOrder.compactMap { ts -> MarketBar? in
            guard let group = buckets[ts], let first = group.first else { return nil }
            let open = first.open
            let close = group.last!.close
            var high = first.high
            var low = first.low
            var volume: Decimal = 0
            for bar in group {
                if bar.high > high { high = bar.high }
                if bar.low < low { low = bar.low }
                volume += bar.volume
            }
            return MarketBar(
                timestamp: ts,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        }
    }
    
    // MARK: - Broker Timezone & Price Alignment Engine
    
    /// Checks if a candlestick covers a target execution price within its [low, high] bounds
    /// Accommodates a small spread/slippage buffer (10% of bar range or 0.05% relative price)
    public static func barContainsPrice(_ bar: MarketBar, price: Decimal) -> Bool {
        guard price > 0, bar.low > 0, bar.high >= bar.low else { return false }
        let p = (price as NSDecimalNumber).doubleValue
        let l = (bar.low as NSDecimalNumber).doubleValue
        let h = (bar.high as NSDecimalNumber).doubleValue
        let spreadTol = max(abs(p) * 0.0005, (h - l) * 0.10)
        return p >= (l - spreadTol) && p <= (h + spreadTol)
    }
    
    /// Resolves the broker server timezone offset (e.g. UTC, Cyprus EET/EEST UTC+2/+3, Vietnam ICT UTC+7)
    /// by testing candidate offsets to find the exact candlestick window where trade.avgEntry falls within [low, high].
    public static func resolveTimeAlignmentOffset(
        bars: [MarketBar],
        trade: Trade,
        resolution: MarketResolution = .m5
    ) -> Int64 {
        guard !bars.isEmpty, trade.avgEntry > 0 else { return 0 }
        
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs: Int64? = trade.closedAt.map { Int64($0.timeIntervalSince1970 * 1000) }
        let step = resolution.durationMs
        
        func findBar(at targetMs: Int64) -> MarketBar? {
            bars.first { targetMs >= $0.timestamp && targetMs < ($0.timestamp + step) }
        }
        
        func evaluateOffset(_ offsetMs: Int64) -> (score: Int, dist: Int64)? {
            let targetOpen = openMs + offsetMs
            guard let entryBar = findBar(at: targetOpen) ?? bars.min(by: { abs($0.timestamp - targetOpen) < abs($1.timestamp - targetOpen) }),
                  abs(entryBar.timestamp - targetOpen) <= step * 2 else {
                return nil
            }
            
            let entryMatch = barContainsPrice(entryBar, price: trade.avgEntry)
            if !entryMatch { return nil }
            
            var score = 10
            if let cMs = closeMs, let exit = trade.avgExit, exit > 0 {
                let targetClose = cMs + offsetMs
                if let exitBar = findBar(at: targetClose) ?? bars.min(by: { abs($0.timestamp - targetClose) < abs($1.timestamp - targetClose) }),
                   abs(exitBar.timestamp - targetClose) <= step * 2 {
                    if barContainsPrice(exitBar, price: exit) {
                        score += 20
                    }
                }
            }
            return (score, abs(offsetMs))
        }
        
        // Candidate broker server offsets in hours:
        // 0h: UTC (standard)
        // -3h: Cyprus EEST summer (The5ers, FTMO, IC Markets)
        // -2h: Cyprus EET winter
        // -7h: Vietnam ICT (UTC+7)
        // +2h, +3h, -1h, +1h, -4h, +4h, -5h, +5h
        let candidateHours: [Double] = [0, -3, -2, -7, 2, 3, -1, 1, -4, 4, -5, 5, -8, 8]
        var bestOffset: Int64 = 0
        var highestScore = -1
        var smallestDist = Int64.max
        
        for h in candidateHours {
            let offsetMs = Int64(h * 3_600_000)
            if let result = evaluateOffset(offsetMs) {
                if result.score > highestScore || (result.score == highestScore && result.dist < smallestDist) {
                    highestScore = result.score
                    smallestDist = result.dist
                    bestOffset = offsetMs
                }
            }
        }
        
        if highestScore > 0 {
            return bestOffset
        }
        
        // Fallback: Scan all bars that contain trade.avgEntry and find the one closest to trade.openedAt
        let matchingBars = bars.filter { barContainsPrice($0, price: trade.avgEntry) }
        if let closestBar = matchingBars.min(by: { abs($0.timestamp - openMs) < abs($1.timestamp - openMs) }) {
            let derivedOffset = closestBar.timestamp - openMs
            let cleanOffset = (derivedOffset / step) * step
            return cleanOffset
        }
        
        return 0
    }
    
    /// Shifts bar timestamps to match broker execution time, and trims bars to replay padding
    /// (e.g. 80 bars before entry for full SMC structure & liquidity context, 15 bars after exit).
    public static func alignAndTrimBars(
        bars: [MarketBar],
        trade: Trade,
        resolution: MarketResolution = .m5,
        preBarsCount: Int = 80,
        postBarsCount: Int = 15
    ) -> [MarketBar] {
        guard !bars.isEmpty else { return [] }
        
        let offsetMs = resolveTimeAlignmentOffset(bars: bars, trade: trade, resolution: resolution)
        
        // Shift bar timestamps by -offsetMs so the candle matching the trade aligns with trade.openedAt
        let alignedBars: [MarketBar] = (offsetMs == 0) ? bars : bars.map {
            MarketBar(
                timestamp: $0.timestamp - offsetMs,
                open: $0.open,
                high: $0.high,
                low: $0.low,
                close: $0.close,
                volume: $0.volume
            )
        }
        
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs: Int64 = {
            if trade.status == .open {
                return Int64(Date().timeIntervalSince1970 * 1000)
            }
            return Int64((trade.closedAt ?? trade.openedAt).timeIntervalSince1970 * 1000)
        }()
        
        let step = resolution.durationMs
        let minTime = openMs - Int64(preBarsCount) * step
        let maxTime: Int64 = {
            if trade.status == .open {
                return Int64(Date().timeIntervalSince1970 * 1000)
            } else {
                return closeMs + Int64(postBarsCount) * step
            }
        }()
        
        let trimmed = alignedBars.filter { $0.timestamp >= minTime && $0.timestamp <= maxTime }
        if !trimmed.isEmpty {
            return trimmed
        }
        return alignedBars
    }
}
