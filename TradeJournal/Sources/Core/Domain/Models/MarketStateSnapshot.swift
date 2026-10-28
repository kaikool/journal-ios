import Foundation

// MARK: - Market State Snapshot (Pure Objective Measurement Form)
/// Encapsulates multi-timeframe factual market readings (H4 vs M15) for AI Coach consumption.
/// Zero hardcoded opinions or predictions; only quantifiable levels, indicators, and calendar timing.
public struct MarketStateSnapshot: Equatable, Sendable {
    public let symbol: String
    public let currentPrice: Decimal
    
    // Higher Timeframe (H4) Structure & Key Barriers
    public let h4OrderFlow: String // e.g. "BULLISH", "BEARISH", "RANGING"
    public let h4SwingHigh: Decimal?
    public let h4SwingLow: Decimal?
    public let h4BrokenLevel: Decimal?
    
    // Execution Timeframe (M15) Structure & Key Levels
    public let m15OrderFlow: String
    public let m15MssState: String? // e.g. "CHoCH Bullish", "BOS Bearish"
    public let m15TriggerLevel: Decimal?
    public let m15NearestSweep: String? // e.g. "Sweep High 2748.50"
    public let m15NearestUnsweptPool: Decimal?
    
    // Technical Momentum Indicators (M15)
    public let rsi14: Double?
    public let ema9: Double?
    public let wma45: Double?
    public let emaVsWmaGap: Double?
    
    // Macro Catalyst / News Proximity
    public let nearestHighImpactNewsTitle: String?
    public let newsCountdownMinutes: Int? // e.g. +45 (in 45 mins), -15 (15 mins ago)
    public let timestamp: Date
    
    public init(
        symbol: String,
        currentPrice: Decimal,
        h4OrderFlow: String,
        h4SwingHigh: Decimal? = nil,
        h4SwingLow: Decimal? = nil,
        h4BrokenLevel: Decimal? = nil,
        m15OrderFlow: String,
        m15MssState: String? = nil,
        m15TriggerLevel: Decimal? = nil,
        m15NearestSweep: String? = nil,
        m15NearestUnsweptPool: Decimal? = nil,
        rsi14: Double? = nil,
        ema9: Double? = nil,
        wma45: Double? = nil,
        emaVsWmaGap: Double? = nil,
        nearestHighImpactNewsTitle: String? = nil,
        newsCountdownMinutes: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.symbol = symbol.uppercased()
        self.currentPrice = currentPrice
        self.h4OrderFlow = h4OrderFlow
        self.h4SwingHigh = h4SwingHigh
        self.h4SwingLow = h4SwingLow
        self.h4BrokenLevel = h4BrokenLevel
        self.m15OrderFlow = m15OrderFlow
        self.m15MssState = m15MssState
        self.m15TriggerLevel = m15TriggerLevel
        self.m15NearestSweep = m15NearestSweep
        self.m15NearestUnsweptPool = m15NearestUnsweptPool
        self.rsi14 = rsi14
        self.ema9 = ema9
        self.wma45 = wma45
        self.emaVsWmaGap = emaVsWmaGap
        self.nearestHighImpactNewsTitle = nearestHighImpactNewsTitle
        self.newsCountdownMinutes = newsCountdownMinutes
        self.timestamp = timestamp
    }
}
