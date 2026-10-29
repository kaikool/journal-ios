import Foundation

// MARK: - Institutional Liquidity Domain Models
// Mathematical, immutable, Sendable models representing institutional liquidity pools,
// previous day/week extremes (PDH/PDL, PWH/PWL), session levels, and discrete liquidity events.
// Conforms strictly to the institutional liquidity specification with zero lookahead bias.

// MARK: - 1. Pool Classification & State Machine

public enum LiquidityPoolType: String, Sendable, Codable, Equatable {
    case buySide = "BUY_SIDE"   // Buy-Side Liquidity (BSL) - resting above highs / buy stops
    case sellSide = "SELL_SIDE" // Sell-Side Liquidity (SSL) - resting below lows / sell stops
}

public enum LiquidityOrigin: String, Sendable, Codable, Equatable {
    case swingPivot     = "SWING_PIVOT"       // Confirmed H4 / H1 Swing High/Low
    case equalHighsLows = "EQUAL_HIGHS_LOWS" // Clustered EQH / EQL (double/triple tops & bottoms)
    case pdhPdl         = "PDH_PDL"          // Previous Day High / Low (completed daily boundary)
    case pwhPwl         = "PWH_PWL"          // Previous Week High / Low (completed weekly boundary)
    case sessionLevel   = "SESSION_LEVEL"    // Asia, London, New York session extremes
}

/// Discrete lifecycle state machine for liquidity pools:
/// CANDIDATE -> ACTIVE -> (SWEPT | BROKEN) -> RESOLVED
///                                         -> INVALIDATED
public enum LiquidityPoolState: String, Sendable, Codable, Equatable {
    case candidate   = "CANDIDATE"    // Forming or pending confirmation window
    case active      = "ACTIVE"       // Confirmed and currently resting in the market
    case swept       = "SWEPT"        // Pierced and closed inside (SFP / wick grab)
    case broken      = "BROKEN"       // Broken by candle body close (breakout)
    case resolved    = "RESOLVED"     // Completed lifecycle / consumed
    case invalidated = "INVALIDATED"  // Invalidated by structural shift or corrupted data
}

// MARK: - 2. Event Types & Classification

public enum LiquidityEventType: String, Sendable, Codable, Equatable {
    case approach              = "APPROACH"                 // Price enters proximity warning distance of pool
    case touch                 = "TOUCH"                    // Price touches/crosses the pool boundary
    case sweepCandidate        = "SWEEP_CANDIDATE"          // Price pierces boundary and closes back inside
    case confirmedSweep        = "CONFIRMED_SWEEP"          // Rejection criteria satisfied (wick ratio / displacement)
    case breakout              = "BREAKOUT"                 // Candle body closes beyond boundary
    case reclaim               = "RECLAIM"                  // Price returns and closes back on original side after breakout
    case postEventConfirmation = "POST_EVENT_CONFIRMATION" // Follow-through displacement confirms the reaction
}

public enum LiquiditySweepType: String, Sendable, Codable, Equatable {
    case buySideSwept = "BUY_SIDE_SWEPT"   // High pierced BSL, candle body closed below (Bearish SFP)
    case sellSideSwept = "SELL_SIDE_SWEPT" // Low pierced SSL, candle body closed above (Bullish SFP)
}

public enum SweepQuality: String, Sendable, Codable, Equatable {
    case highConvictionSFP = "HIGH_CONVICTION_SFP" // Deep piercing + large rejection wick (>= 30% of bar range)
    case cleanSweep        = "CLEAN_SWEEP"         // Clear wick pierce with body close back inside (15-30%)
    case shallowPiercing   = "SHALLOW_PIERCING"     // Minor wick pierce (< 15%)
    case strongSFP         = "STRONG_SFP"          // High quality institutional SFP (backward compatibility alias)
}

// MARK: - 3. Causal Swing Pivot

public struct LiquiditySwingPivot: Identifiable, Sendable, Equatable {
    public let id: String
    public let type: LiquidityPoolType
    public let price: Decimal
    public let formationIndex: Int
    public let formationTimestamp: Int64
    public let confirmedAtIndex: Int
    public let confirmedTimestamp: Int64
    public var state: LiquidityPoolState
    public let timeframe: String
    
    public var isMitigated: Bool {
        get { state != .active && state != .candidate }
        set { state = newValue ? .resolved : .active }
    }
    
    public init(
        id: String? = nil,
        type: LiquidityPoolType,
        price: Decimal,
        formationIndex: Int,
        formationTimestamp: Int64,
        confirmedAtIndex: Int,
        confirmedTimestamp: Int64,
        state: LiquidityPoolState = .active,
        isMitigated: Bool = false,
        timeframe: String = "H4"
    ) {
        self.id = id ?? "\(timeframe)_\(type.rawValue)_\(formationIndex)_\(formationTimestamp)"
        self.type = type
        self.price = price
        self.formationIndex = formationIndex
        self.formationTimestamp = formationTimestamp
        self.confirmedAtIndex = confirmedAtIndex
        self.confirmedTimestamp = confirmedTimestamp
        self.state = isMitigated ? .resolved : state
        self.timeframe = timeframe
    }
}

// MARK: - 4. Canonical Liquidity Pool

public struct LiquidityPool: Identifiable, Sendable, Equatable {
    public let id: String
    public let type: LiquidityPoolType
    public let origin: LiquidityOrigin
    public let label: String
    public let price: Decimal
    public let rangeMin: Decimal
    public let rangeMax: Decimal
    public let topPrice: Decimal
    public let bottomPrice: Decimal
    public let touchCount: Int
    public let formationTimestamp: Int64
    public let confirmedTimestamp: Int64
    public let confirmedAtIndex: Int
    public let activatedAtTimestamp: Int64
    public let resolvedAtTimestamp: Int64?
    public let resolutionReason: String?
    public var state: LiquidityPoolState
    public let sourceTimeframe: String
    public let sourcePivots: [LiquiditySwingPivot]
    
    // Backward compatibility helpers
    public var timeframe: String { sourceTimeframe }
    public var isMitigated: Bool {
        get { state != .active && state != .candidate }
        set { state = newValue ? .resolved : .active }
    }
    public var count: Int { touchCount }
    public var extremePrice: Decimal { price }
    
    public init(
        id: String? = nil,
        type: LiquidityPoolType,
        origin: LiquidityOrigin,
        label: String,
        price: Decimal,
        rangeMin: Decimal? = nil,
        rangeMax: Decimal? = nil,
        topPrice: Decimal? = nil,
        bottomPrice: Decimal? = nil,
        touchCount: Int = 1,
        formationTimestamp: Int64 = 0,
        confirmedTimestamp: Int64? = nil,
        confirmedAtIndex: Int = 0,
        activatedAtTimestamp: Int64? = nil,
        resolvedAtTimestamp: Int64? = nil,
        resolutionReason: String? = nil,
        state: LiquidityPoolState = .active,
        isMitigated: Bool = false,
        sourceTimeframe: String = "H4",
        timeframe: String? = nil,
        sourcePivots: [LiquiditySwingPivot] = []
    ) {
        let tf = timeframe ?? sourceTimeframe
        self.id = id ?? "\(tf)_\(type.rawValue)_\(origin.rawValue)_\(formationTimestamp)_\(price)"
        self.type = type
        self.origin = origin
        self.label = label
        self.price = price
        let rMin = rangeMin ?? bottomPrice ?? price
        let rMax = rangeMax ?? topPrice ?? price
        self.rangeMin = min(rMin, rMax)
        self.rangeMax = max(rMin, rMax)
        self.topPrice = max(self.rangeMax, price)
        self.bottomPrice = min(self.rangeMin, price)
        self.touchCount = touchCount
        self.formationTimestamp = formationTimestamp
        self.confirmedTimestamp = confirmedTimestamp ?? formationTimestamp
        self.confirmedAtIndex = confirmedAtIndex
        self.activatedAtTimestamp = activatedAtTimestamp ?? (confirmedTimestamp ?? formationTimestamp)
        self.resolvedAtTimestamp = resolvedAtTimestamp
        self.resolutionReason = resolutionReason
        self.state = isMitigated ? .resolved : state
        self.sourceTimeframe = tf
        self.sourcePivots = sourcePivots
    }
}

// MARK: - 5. Liquidity Event & Sweep

public struct LiquiditySweepEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let poolId: String
    public let barIndex: Int
    public let timestamp: Int64
    public let date: Date
    public let eventType: LiquidityEventType
    public let sweepType: LiquiditySweepType
    public let poolOrigin: LiquidityOrigin
    public let levelName: String
    public let sweptPrice: Decimal
    public let wickExtreme: Decimal
    public let candleClose: Decimal
    public let penetrationAmount: Decimal
    public let penetrationPips: Decimal
    public let rejectionWickRatio: Double
    public let sweepQuality: SweepQuality
    public let barsAgo: Int
    public let timeframe: String
    public let isConfirmedSweep: Bool
    public let hasDisplacement: Bool
    public let displacementRatio: Double
    public let postEventConfirmation: Bool
    
    // Backward compatibility computed property
    public var penetration: Decimal { penetrationAmount }
    
    public init(
        id: String? = nil,
        poolId: String = "",
        barIndex: Int,
        timestamp: Int64,
        eventType: LiquidityEventType = .confirmedSweep,
        sweepType: LiquiditySweepType,
        poolOrigin: LiquidityOrigin = .swingPivot,
        levelName: String,
        sweptPrice: Decimal,
        wickExtreme: Decimal,
        candleClose: Decimal,
        penetrationAmount: Decimal? = nil,
        penetrationPips: Decimal = 0,
        penetration: Decimal? = nil,
        rejectionWickRatio: Double = 0.0,
        sweepQuality: SweepQuality = .cleanSweep,
        barsAgo: Int = 0,
        timeframe: String = "M15",
        isConfirmedSweep: Bool = true,
        hasDisplacement: Bool = false,
        displacementRatio: Double = 0.0,
        postEventConfirmation: Bool = false
    ) {
        let penAmt = penetrationAmount ?? penetration ?? abs(wickExtreme - sweptPrice)
        self.id = id ?? "\(eventType.rawValue)_\(sweepType.rawValue)_\(barIndex)_\(levelName)"
        self.poolId = poolId
        self.barIndex = barIndex
        self.timestamp = timestamp
        self.date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        self.eventType = eventType
        self.sweepType = sweepType
        self.poolOrigin = poolOrigin
        self.levelName = levelName
        self.sweptPrice = sweptPrice
        self.wickExtreme = wickExtreme
        self.candleClose = candleClose
        self.penetrationAmount = penAmt
        self.penetrationPips = penetrationPips != 0 ? penetrationPips : penAmt
        self.rejectionWickRatio = rejectionWickRatio
        self.sweepQuality = sweepQuality
        self.barsAgo = barsAgo
        self.timeframe = timeframe
        self.isConfirmedSweep = isConfirmedSweep
        self.hasDisplacement = hasDisplacement
        self.displacementRatio = displacementRatio
        self.postEventConfirmation = postEventConfirmation
    }
}

// MARK: - 6. Comprehensive Liquidity Analysis Result

public struct LiquidityAnalysisResult: Sendable {
    public let symbol: String
    public let timeframe: String
    public let currentPrice: Decimal
    
    // Macro Institutional Levels
    public let pdh: Decimal?
    public let pdl: Decimal?
    public let pwh: Decimal?
    public let pwl: Decimal?
    
    // Active Resting Liquidity Pools (H4/H1 Primary & Supplementary)
    public let restingBuySidePools: [LiquidityPool]
    public let restingSellSidePools: [LiquidityPool]
    
    // Nearest Targets
    public let nearestBSL: LiquidityPool?
    public let nearestSSL: LiquidityPool?
    public let distanceToBSLPips: Decimal?
    public let distanceToSSLPips: Decimal?
    
    // Institutional Sweeps & Discrete Events
    public let recentEvents: [LiquiditySweepEvent]
    public let recentSweeps: [LiquiditySweepEvent]
    public let latestSweep: LiquiditySweepEvent?
    
    // High Timeframe Active Pools
    public let activeH4Pools: [LiquidityPool]
    public let activeH1Pools: [LiquidityPool]
    
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
        recentEvents: [LiquiditySweepEvent] = [],
        recentSweeps: [LiquiditySweepEvent] = [],
        latestSweep: LiquiditySweepEvent? = nil,
        activeH4Pools: [LiquidityPool] = [],
        activeH1Pools: [LiquidityPool] = []
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
        self.recentEvents = recentEvents
        self.recentSweeps = recentSweeps.isEmpty ? recentEvents.filter { $0.eventType == .confirmedSweep || $0.eventType == .sweepCandidate } : recentSweeps
        self.latestSweep = latestSweep ?? self.recentSweeps.first
        self.activeH4Pools = activeH4Pools
        self.activeH1Pools = activeH1Pools
    }
}

// MARK: - 7. Clean Candlestick Tape Formatter

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
