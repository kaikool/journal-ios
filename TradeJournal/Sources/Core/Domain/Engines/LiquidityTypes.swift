import Foundation

// MARK: - Institutional Liquidity Domain Models
// Mathematical, immutable, Sendable models representing institutional liquidity pools,
// previous day/week extremes (PDH/PDL, PWH/PWL), session levels, and Swing Failure Patterns (SFP).

public enum LiquidityPoolType: String, Sendable, Codable, Equatable {
    case buySide = "BUY_SIDE"   // Buy-Side Liquidity (BSL) - resting above highs / buy stops
    case sellSide = "SELL_SIDE" // Sell-Side Liquidity (SSL) - resting below lows / sell stops
}

public enum LiquidityOrigin: String, Sendable, Codable, Equatable {
    case pdhPdl = "PDH_PDL"               // Previous Day High / Low
    case pwhPwl = "PWH_PWL"               // Previous Week High / Low
    case equalHighsLows = "EQUAL_HIGHS_LOWS" // EQH / EQL clusters (double / triple tops/bottoms)
    case sessionLevel = "SESSION_LEVEL"   // Asia, London, New York session extremes
    case swingPivot = "SWING_PIVOT"       // Major unmitigated swing high / low
}

public enum LiquiditySweepType: String, Sendable, Codable, Equatable {
    case buySideSwept = "BUY_SIDE_SWEPT"   // High pierced BSL, candle body closed below (Bearish SFP / Turtle Soup Sell)
    case sellSideSwept = "SELL_SIDE_SWEPT" // Low pierced SSL, candle body closed above (Bullish SFP / Turtle Soup Buy)
}

public enum SweepQuality: String, Sendable, Codable, Equatable {
    case highConvictionSFP = "HIGH_CONVICTION_SFP" // Deep piercing + large rejection wick (>= 30% of bar range)
    case cleanSweep = "CLEAN_SWEEP"               // Clear wick pierce with body close back inside (15-30%)
    case shallowPiercing = "SHALLOW_PIERCING"     // Minor wick pierce
}

public struct LiquiditySwingPivot: Identifiable, Sendable, Equatable {
    public var id: String { "\(type.rawValue)_\(formationIndex)_\(formationTimestamp)" }
    public let type: LiquidityPoolType
    public let price: Decimal
    public let formationIndex: Int
    public let formationTimestamp: Int64
    public let confirmedAtIndex: Int
    public let confirmedTimestamp: Int64
    public var isMitigated: Bool
    
    public init(
        type: LiquidityPoolType,
        price: Decimal,
        formationIndex: Int,
        formationTimestamp: Int64,
        confirmedAtIndex: Int,
        confirmedTimestamp: Int64,
        isMitigated: Bool = false
    ) {
        self.type = type
        self.price = price
        self.formationIndex = formationIndex
        self.formationTimestamp = formationTimestamp
        self.confirmedAtIndex = confirmedAtIndex
        self.confirmedTimestamp = confirmedTimestamp
        self.isMitigated = isMitigated
    }
}

public struct LiquidityPool: Identifiable, Sendable, Equatable {
    public var id: String { "\(type.rawValue)_\(origin.rawValue)_\(label)_\(price)" }
    public let type: LiquidityPoolType
    public let origin: LiquidityOrigin
    public let label: String
    public let price: Decimal
    public let rangeMin: Decimal
    public let rangeMax: Decimal
    public let touchCount: Int
    public let formationTimestamp: Int64
    public var isMitigated: Bool
    public let timeframe: String
    
    public init(
        type: LiquidityPoolType,
        origin: LiquidityOrigin,
        label: String,
        price: Decimal,
        rangeMin: Decimal? = nil,
        rangeMax: Decimal? = nil,
        touchCount: Int = 1,
        formationTimestamp: Int64 = 0,
        isMitigated: Bool = false,
        timeframe: String = "H4"
    ) {
        self.type = type
        self.origin = origin
        self.label = label
        self.price = price
        self.rangeMin = rangeMin ?? price
        self.rangeMax = rangeMax ?? price
        self.touchCount = touchCount
        self.formationTimestamp = formationTimestamp
        self.isMitigated = isMitigated
        self.timeframe = timeframe
    }
}

public struct LiquiditySweepEvent: Identifiable, Sendable, Equatable {
    public var id: String { "\(sweepType.rawValue)_\(barIndex)_\(levelName)" }
    public let barIndex: Int
    public let timestamp: Int64
    public let date: Date
    public let sweepType: LiquiditySweepType
    public let poolOrigin: LiquidityOrigin
    public let levelName: String
    public let sweptPrice: Decimal
    public let wickExtreme: Decimal
    public let candleClose: Decimal
    public let penetrationPips: Decimal
    public let rejectionWickRatio: Double
    public let sweepQuality: SweepQuality
    public let barsAgo: Int
    public let timeframe: String
    public let isConfirmedSweep: Bool
    
    public init(
        barIndex: Int,
        timestamp: Int64,
        sweepType: LiquiditySweepType,
        poolOrigin: LiquidityOrigin = .swingPivot,
        levelName: String,
        sweptPrice: Decimal,
        wickExtreme: Decimal,
        candleClose: Decimal,
        penetrationPips: Decimal = 0,
        rejectionWickRatio: Double = 0.0,
        sweepQuality: SweepQuality = .cleanSweep,
        barsAgo: Int = 0,
        timeframe: String = "M15",
        isConfirmedSweep: Bool = true
    ) {
        self.barIndex = barIndex
        self.timestamp = timestamp
        self.date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        self.sweepType = sweepType
        self.poolOrigin = poolOrigin
        self.levelName = levelName
        self.sweptPrice = sweptPrice
        self.wickExtreme = wickExtreme
        self.candleClose = candleClose
        self.penetrationPips = penetrationPips
        self.rejectionWickRatio = rejectionWickRatio
        self.sweepQuality = sweepQuality
        self.barsAgo = barsAgo
        self.timeframe = timeframe
        self.isConfirmedSweep = isConfirmedSweep
    }
}

// MARK: - Comprehensive Liquidity State Analysis Result

public struct LiquidityAnalysisResult: Sendable {
    public let symbol: String
    public let timeframe: String
    public let currentPrice: Decimal
    
    // Macro Institutional Levels
    public let pdh: Decimal?
    public let pdl: Decimal?
    public let pwh: Decimal?
    public let pwl: Decimal?
    
    // Active Resting Liquidity Pools
    public let restingBuySidePools: [LiquidityPool]
    public let restingSellSidePools: [LiquidityPool]
    
    // Nearest Targets
    public let nearestBSL: LiquidityPool?
    public let nearestSSL: LiquidityPool?
    public let distanceToBSLPips: Decimal?
    public let distanceToSSLPips: Decimal?
    
    // Institutional Sweeps & SFP
    public let recentSweeps: [LiquiditySweepEvent]
    public let latestSweep: LiquiditySweepEvent?
    
    public init(
        symbol: String,
        timeframe: String,
        currentPrice: Decimal,
        pdh: Decimal? = nil,
        pdl: Decimal? = nil,
        pwh: Decimal? = nil,
        pwl: Decimal? = nil,
        restingBuySidePools: [LiquidityPool] = [],
        restingSellSidePools: [LiquidityPool] = [],
        nearestBSL: LiquidityPool? = nil,
        nearestSSL: LiquidityPool? = nil,
        distanceToBSLPips: Decimal? = nil,
        distanceToSSLPips: Decimal? = nil,
        recentSweeps: [LiquiditySweepEvent] = [],
        latestSweep: LiquiditySweepEvent? = nil
    ) {
        self.symbol = symbol
        self.timeframe = timeframe
        self.currentPrice = currentPrice
        self.pdh = pdh
        self.pdl = pdl
        self.pwh = pwh
        self.pwl = pwl
        self.restingBuySidePools = restingBuySidePools
        self.restingSellSidePools = restingSellSidePools
        self.nearestBSL = nearestBSL
        self.nearestSSL = nearestSSL
        self.distanceToBSLPips = distanceToBSLPips
        self.distanceToSSLPips = distanceToSSLPips
        self.recentSweeps = recentSweeps
        self.latestSweep = latestSweep
    }
}

// MARK: - Clean Candlestick Tape Formatter

public enum CandleTapeFormatter: Sendable {
    
    public static func formatCandlesTable(
        bars: [MarketBar],
        count: Int = 16,
        sweeps: [LiquiditySweepEvent] = [],
        symbol: String? = nil,
        displayTimeZone: TimeZone = .current
    ) -> String {
        guard !bars.isEmpty else { return "No candle data available." }
        let slice = bars.suffix(max(1, count))
        let total = bars.count
        
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = displayTimeZone
        
        var lines: [String] = [
            "| # | Time | Open | High | Low | Close | Range | Direction | Liquidity Note |",
            "|---|------|------|------|-----|-------|-------|-----------|----------------|"
        ]
        
        for (offset, bar) in slice.enumerated() {
            let actualIndex = total - slice.count + offset
            let timeStr = f.string(from: bar.date)
            let o = formatPrice(bar.open, symbol: symbol)
            let h = formatPrice(bar.high, symbol: symbol)
            let l = formatPrice(bar.low, symbol: symbol)
            let c = formatPrice(bar.close, symbol: symbol)
            let range = formatPrice(abs(bar.high - bar.low), symbol: symbol)
            
            let dir: String = {
                if bar.close > bar.open { return "BULLISH ▲" }
                if bar.close < bar.open { return "BEARISH ▼" }
                return "DOJI ▬"
            }()
            
            // Check for liquidity sweeps on this bar
            let sweepOnBar = sweeps.first { $0.barIndex == actualIndex }
            let note: String = {
                if let sw = sweepOnBar {
                    let sfpLabel = sw.sweepType == .buySideSwept ? "BEARISH SFP (BSL Swept)" : "BULLISH SFP (SSL Swept)"
                    return "\(sfpLabel) [\(sw.levelName)]"
                }
                return "Normal"
            }()
            
            lines.append("| \(offset + 1) | \(timeStr) | \(o) | \(h) | \(l) | \(c) | \(range) | \(dir) | \(note) |")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func formatPrice(_ p: Decimal, symbol: String?) -> String {
        if let sym = symbol, !sym.isEmpty {
            return Formatters.price(p, symbol: sym)
        }
        let d = (p as NSDecimalNumber).doubleValue
        if d >= 500 { return String(format: "%.2f", d) }
        if d >= 10 { return String(format: "%.3f", d) }
        return String(format: "%.5f", d)
    }
}
