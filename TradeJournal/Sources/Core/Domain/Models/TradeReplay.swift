import Foundation

public enum MarketResolution: String, CaseIterable, Identifiable, Sendable {
    case m1 = "1m"
    case m5 = "5m"
    case m15 = "15m"
    case h1 = "1h"
    case d1 = "1d"
    
    public var id: String { rawValue }
    
    public var durationMs: Int64 {
        switch self {
        case .m1: return 60_000
        case .m5: return 300_000
        case .m15: return 900_000
        case .h1: return 3_600_000
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
    
    public init(
        mae: Decimal? = nil,
        mfe: Decimal? = nil,
        sampledBars: Int = 0,
        excludedBars: Int = 0,
        warnings: [String] = [],
        priceBasisMismatch: Bool = false
    ) {
        self.mae = mae
        self.mfe = mfe
        self.sampledBars = sampledBars
        self.excludedBars = excludedBars
        self.warnings = warnings
        self.priceBasisMismatch = priceBasisMismatch
    }
}

public struct ReplayFrame: Sendable {
    public let visibleBars: [MarketBar]
    public let throughTimestamp: Int64
    public let activeFills: [Execution]
    public let unrealizedPnl: Decimal
    public let currentBar: MarketBar?
    
    public init(
        visibleBars: [MarketBar],
        throughTimestamp: Int64,
        activeFills: [Execution],
        unrealizedPnl: Decimal,
        currentBar: MarketBar? = nil
    ) {
        self.visibleBars = visibleBars
        self.throughTimestamp = throughTimestamp
        self.activeFills = activeFills
        self.unrealizedPnl = unrealizedPnl
        self.currentBar = currentBar ?? visibleBars.last
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
                currentBar: nil
            )
        }
        
        let through = lastBar.timestamp + resolution.durationMs
        let currentFills = fills.filter { Int64($0.executedAt.timeIntervalSince1970 * 1000) <= through }
        
        // Calculate unrealized P&L at current bar close
        var unrealized: Decimal = 0
        if trade.status != .open && clampedIndex >= bars.count {
            unrealized = trade.netPnl
        } else {
            if trade.direction == .long {
                unrealized = (lastBar.close - trade.avgEntry) * trade.quantity
            } else {
                unrealized = (trade.avgEntry - lastBar.close) * trade.quantity
            }
        }
        
        return ReplayFrame(
            visibleBars: visible,
            throughTimestamp: through,
            activeFills: currentFills,
            unrealizedPnl: unrealized,
            currentBar: lastBar
        )
    }
    
    /// Computes MAE (Maximum Adverse Excursion) and MFE (Maximum Favorable Excursion)
    /// Ported 1:1 from `excursions.ts` in source-repo
    public static func estimateExcursions(
        trade: Trade,
        fills: [Execution],
        bars: [MarketBar],
        resolution: MarketResolution = .m15
    ) -> ExcursionEstimate {
        guard !bars.isEmpty else {
            return ExcursionEstimate(warnings: ["No candle data available to calculate MAE/MFE."])
        }
        
        let qty = trade.quantity
        guard qty > 0, trade.avgEntry > 0 else {
            return ExcursionEstimate(warnings: ["Missing valid quantity or entry price."])
        }
        
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs = Int64((trade.closedAt ?? Date()).timeIntervalSince1970 * 1000)
        let step = resolution.durationMs
        
        // Filter candles within trade holding window
        let tradeBars = bars.filter { $0.timestamp + step >= openMs && $0.timestamp <= closeMs }
        guard !tradeBars.isEmpty else {
            return ExcursionEstimate(warnings: ["Candle range does not cover trade holding duration."])
        }
        
        var minAdverse: Decimal = 0
        var maxFavorable: Decimal = 0
        
        for bar in tradeBars {
            if trade.direction == .long {
                let adverse = (bar.low - trade.avgEntry) * qty
                let favorable = (bar.high - trade.avgEntry) * qty
                if adverse < minAdverse { minAdverse = adverse }
                if favorable > maxFavorable { maxFavorable = favorable }
            } else {
                let adverse = (trade.avgEntry - bar.high) * qty
                let favorable = (trade.avgEntry - bar.low) * qty
                if adverse < minAdverse { minAdverse = adverse }
                if favorable > maxFavorable { maxFavorable = favorable }
            }
        }
        
        return ExcursionEstimate(
            mae: minAdverse,
            mfe: maxFavorable,
            sampledBars: tradeBars.count,
            excludedBars: max(0, bars.count - tradeBars.count),
            warnings: [
                "MAE/MFE estimates based on completed candle High/Low during trade holding period.",
                "Excludes commissions, fees, and overnight swap."
            ]
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
            if let c = trade.closedAt {
                return max(openMs + resolution.durationMs * 3, Int64(c.timeIntervalSince1970 * 1000))
            } else if let dur = trade.durationMs, dur > 0 {
                return openMs + dur
            } else {
                return openMs + resolution.durationMs * 12
            }
        }()
        
        let step = resolution.durationMs
        let preBars = 4
        let postBars = 2
        let startTimestamp = openMs - Int64(preBars) * step
        let endTimestamp = closeMs + Int64(postBars) * step
        
        let totalSteps = max(8, min(120, Int((endTimestamp - startTimestamp) / step)))
        var bars: [MarketBar] = []
        
        let entryPrice = (trade.avgEntry as NSDecimalNumber).doubleValue
        let exitPrice = trade.avgExit != nil ? (trade.avgExit! as NSDecimalNumber).doubleValue : (entryPrice + (trade.netPnl > 0 ? 0.005 : -0.005) * entryPrice)
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
}
