import Foundation

// MARK: - Moving Average Engine (EMA 21 & EMA 50 Multi-Timeframe Trend Engine)
// Lightweight, robust, mathematically sound exponential moving average trend engine.
// Replaces complex lagging structure machines with institutional 21 & 50 EMA dynamic trend evaluation.

public enum TrendBias: String, Sendable, Codable, Equatable {
    case strongBullish = "STRONG_BULLISH"
    case bullish       = "BULLISH"
    case neutral       = "NEUTRAL"
    case pullback      = "PULLBACK"
    case bearish       = "BEARISH"
    case strongBearish = "STRONG_BEARISH"
    
    public var label: String {
        switch self {
        case .strongBullish: return "Strong Bullish ▲▲"
        case .bullish:       return "Bullish ▲"
        case .neutral:       return "Neutral ▬"
        case .pullback:      return "Pullback / Consolidating ⇄"
        case .bearish:       return "Bearish ▼"
        case .strongBearish: return "Strong Bearish ▼▼"
        }
    }
}

public struct TimeframeEMASnapshot: Sendable, Equatable {
    public let timeframe: String
    public let currentPrice: Decimal
    public let ema21: Decimal?
    public let ema50: Decimal?
    public let trend: TrendBias
    public let spread: Decimal?
    public let distanceToEMA21: Decimal?
    public let summary: String
    
    public init(
        timeframe: String,
        currentPrice: Decimal,
        ema21: Decimal?,
        ema50: Decimal?,
        trend: TrendBias,
        spread: Decimal? = nil,
        distanceToEMA21: Decimal? = nil,
        summary: String
    ) {
        self.timeframe = timeframe
        self.currentPrice = currentPrice
        self.ema21 = ema21
        self.ema50 = ema50
        self.trend = trend
        self.spread = spread
        self.distanceToEMA21 = distanceToEMA21
        self.summary = summary
    }
}

public struct MultiTimeframeEMAAnalysis: Sendable {
    public let symbol: String
    public let currentPrice: Decimal
    public let d1: TimeframeEMASnapshot?
    public let h4: TimeframeEMASnapshot?
    public let h1: TimeframeEMASnapshot?
    public let m15: TimeframeEMASnapshot?
    public let alignmentSummary: String
    
    public init(
        symbol: String,
        currentPrice: Decimal,
        d1: TimeframeEMASnapshot?,
        h4: TimeframeEMASnapshot?,
        h1: TimeframeEMASnapshot? = nil,
        m15: TimeframeEMASnapshot?,
        alignmentSummary: String
    ) {
        self.symbol = symbol
        self.currentPrice = currentPrice
        self.d1 = d1
        self.h4 = h4
        self.h1 = h1
        self.m15 = m15
        self.alignmentSummary = alignmentSummary
    }
}

public enum MovingAverageEngine: Sendable {
    
    // MARK: - Single Series EMA Calculation (Zero Lookahead Bias)
    
    /// Pure causal Exponential Moving Average calculation with strictly zero lookahead bias.
    /// Multiplier: alpha = 2 / (period + 1)
    /// Recursion: EMA[0] = Close[0]
    ///            EMA[i] = Close[i] * alpha + EMA[i-1] * (1 - alpha)
    /// Every point i depends solely on past data [0...i] and is strictly invariant to future bars.
    public static func calculateEMA(period: Int, bars: [MarketBar]) -> [Decimal] {
        guard period > 0, let firstBar = bars.first else { return [] }
        var result: [Decimal] = []
        result.reserveCapacity(bars.count)
        
        let alpha = Decimal(2) / Decimal(period + 1)
        let oneMinusAlpha = Decimal(1) - alpha
        
        var currentEMA: Decimal = firstBar.close
        result.append(currentEMA)
        
        for i in 1..<bars.count {
            currentEMA = (bars[i].close * alpha) + (currentEMA * oneMinusAlpha)
            result.append(currentEMA)
        }
        
        return result
    }
    
    /// Pure causal EMA calculation for raw Decimal price series.
    public static func calculateEMA(period: Int, closes: [Decimal]) -> [Decimal] {
        guard period > 0, let firstClose = closes.first else { return [] }
        var result: [Decimal] = []
        result.reserveCapacity(closes.count)
        
        let alpha = Decimal(2) / Decimal(period + 1)
        let oneMinusAlpha = Decimal(1) - alpha
        
        var currentEMA: Decimal = firstClose
        result.append(currentEMA)
        
        for i in 1..<closes.count {
            currentEMA = (closes[i] * alpha) + (currentEMA * oneMinusAlpha)
            result.append(currentEMA)
        }
        
        return result
    }
    
    // MARK: - Timeframe Snapshot Analysis
    
    public static func analyzeTimeframe(bars: [MarketBar], timeframe: String, symbol: String? = nil) -> TimeframeEMASnapshot? {
        guard let lastBar = bars.last else { return nil }
        let curPrice = lastBar.close
        
        let ema21Series = calculateEMA(period: 21, bars: bars)
        let ema50Series = calculateEMA(period: 50, bars: bars)
        
        let val21 = ema21Series.last
        let val50 = ema50Series.last
        
        let trend: TrendBias
        let spread: Decimal?
        let dist21: Decimal?
        
        if let e21 = val21, let e50 = val50 {
            spread = e21 - e50
            dist21 = curPrice - e21
            
            if e21 > e50 {
                if curPrice >= e21 {
                    trend = .strongBullish
                } else if curPrice >= e50 {
                    trend = .pullback
                } else {
                    trend = .bullish
                }
            } else if e21 < e50 {
                if curPrice <= e21 {
                    trend = .strongBearish
                } else if curPrice <= e50 {
                    trend = .pullback
                } else {
                    trend = .bearish
                }
            } else {
                trend = .neutral
            }
        } else if let e21 = val21 {
            spread = nil
            dist21 = curPrice - e21
            trend = curPrice >= e21 ? .bullish : .bearish
        } else {
            spread = nil
            dist21 = nil
            trend = .neutral
        }
        
        let summary: String = {
            guard let e21 = val21, let e50 = val50 else {
                return "\(timeframe): Insufficient data for EMA"
            }
            let pStr21 = formatPrice(e21, symbol: symbol)
            let pStr50 = formatPrice(e50, symbol: symbol)
            return "\(timeframe): \(trend.label) (EMA 21: \(pStr21), EMA 50: \(pStr50))"
        }()
        
        return TimeframeEMASnapshot(
            timeframe: timeframe,
            currentPrice: curPrice,
            ema21: val21,
            ema50: val50,
            trend: trend,
            spread: spread,
            distanceToEMA21: dist21,
            summary: summary
        )
    }
    
    // MARK: - Multi-Timeframe Alignment (D1, H4, H1, M15)
    
    public static func analyzeMultiTimeframe(
        barsD1: [MarketBar],
        barsH4: [MarketBar],
        barsH1: [MarketBar] = [],
        barsM15: [MarketBar],
        symbol: String
    ) -> MultiTimeframeEMAAnalysis {
        let curPrice = barsM15.last?.close ?? barsH1.last?.close ?? barsH4.last?.close ?? barsD1.last?.close ?? 0
        
        let snapD1 = analyzeTimeframe(bars: barsD1, timeframe: "D1", symbol: symbol)
        let snapH4 = analyzeTimeframe(bars: barsH4, timeframe: "H4", symbol: symbol)
        let snapH1 = !barsH1.isEmpty ? analyzeTimeframe(bars: barsH1, timeframe: "H1", symbol: symbol) : nil
        let snapM15 = analyzeTimeframe(bars: barsM15, timeframe: "M15", symbol: symbol)
        
        var parts: [String] = []
        if let d = snapD1 { parts.append(d.summary) }
        if let h = snapH4 { parts.append(h.summary) }
        if let h1 = snapH1 { parts.append(h1.summary) }
        if let m = snapM15 { parts.append(m.summary) }
        
        let alignment = parts.isEmpty ? "No multi-timeframe EMA data." : parts.joined(separator: " | ")
        
        return MultiTimeframeEMAAnalysis(
            symbol: symbol,
            currentPrice: curPrice,
            d1: snapD1,
            h4: snapH4,
            h1: snapH1,
            m15: snapM15,
            alignmentSummary: alignment
        )
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
