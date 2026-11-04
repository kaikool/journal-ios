import SwiftUI

// MARK: - Pre-Trade Quantitative Context Card (Key Price Levels & 3-Line RSI Momentum)
// Displays authoritative, measurable market facts:
// Daily PDH/PDL, ADR 14, H4 High/Low, and Wilder RSI-14 momentum system.
public struct PreTradeContextMetricsCard: View {
    public let d1Bars: [MarketBar]
    public let h4Bars: [MarketBar]
    public let h1Bars: [MarketBar]
    public let m15Bars: [MarketBar]
    public let symbol: String
    
    public init(
        d1Bars: [MarketBar],
        h4Bars: [MarketBar],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar],
        symbol: String = ""
    ) {
        self.d1Bars = d1Bars
        self.h4Bars = h4Bars
        self.h1Bars = h1Bars
        self.m15Bars = m15Bars
        self.symbol = symbol
    }
    
    private var livePrice: Decimal? {
        m15Bars.last?.close ?? h1Bars.last?.close ?? h4Bars.last?.close ?? d1Bars.last?.close
    }
    
    private var d1KeyLevels: (pdh: Decimal?, pdl: Decimal?, adr: Decimal?) {
        guard d1Bars.count >= 2 else { return (nil, nil, nil) }
        let prev = d1Bars[d1Bars.count - 2]
        let lookback = min(14, d1Bars.count - 1)
        let ranges = d1Bars.suffix(lookback).map { $0.high - $0.low }
        let avgRange = ranges.reduce(Decimal.zero, +) / Decimal(lookback)
        return (prev.high, prev.low, avgRange)
    }
    
    private var h4Range: (high: Decimal?, low: Decimal?) {
        guard !h4Bars.isEmpty else { return (nil, nil) }
        let h = h4Bars.suffix(24).map(\.high).max()
        let l = h4Bars.suffix(24).map(\.low).min()
        return (h, l)
    }
    
    private var momentumSnapshot: (rsi: Double, signal: Double, wma: Double, isBullish: Bool)? {
        let targetBars = !h1Bars.isEmpty ? h1Bars : m15Bars
        guard targetBars.count >= 14 else { return nil }
        let window = MomentumEngine.computeWindow(bars: targetBars, windowSize: 1)
        guard let pt = window.points.last else { return nil }
        let r = NSDecimalNumber(decimal: pt.rsi14).doubleValue
        let s = NSDecimalNumber(decimal: pt.ema9).doubleValue
        let w = NSDecimalNumber(decimal: pt.wma45).doubleValue
        return (r, s, w, r >= s)
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center) {
                    Text("KEY PRICE LEVELS & MOMENTUM")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    if let cur = livePrice {
                        Text("Live: \(Formatters.price(cur, symbol: symbol))")
                            .font(AppTypography.statValue)
                            .foregroundColor(AppColors.brand)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Section 1: Key Price Levels (PDH / PDL, ADR 14, H4 High / Low)
                VStack(alignment: .leading, spacing: 6) {
                    Text("KEY STRUCTURAL LEVELS")
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.3)
                    
                    HStack(spacing: 12) {
                        // D1 PDH / PDL
                        if let h = d1KeyLevels.pdh, let l = d1KeyLevels.pdl {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("D1 PDH / PDL")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(Formatters.price(h, symbol: symbol)) / \(Formatters.price(l, symbol: symbol))")
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                        
                        // ADR 14
                        if let adr = d1KeyLevels.adr {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ADR 14D")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.price(adr, symbol: symbol))
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                        
                        Spacer()
                        
                        // H4 Range
                        if let h4H = h4Range.high, let h4L = h4Range.low {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("H4 24-BAR RANGE")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("H: \(Formatters.price(h4H, symbol: symbol)) | L: \(Formatters.price(h4L, symbol: symbol))")
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.brand)
                            }
                        }
                    }
                }
                
                // Section 2: 3-Line RSI Momentum System
                if let mom = momentumSnapshot {
                    Divider().background(AppColors.border.opacity(0.3))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("3-LINE RSI MOMENTUM")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.3)
                        
                        HStack(spacing: 12) {
                            Text("RSI(14): \(String(format: "%.1f", mom.rsi))")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            Text("EMA(9): \(String(format: "%.1f", mom.signal))")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Text("WMA(45): \(String(format: "%.1f", mom.wma))")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Spacer()
                            
                            Text(mom.isBullish ? "Bullish Momentum" : "Bearish Momentum")
                                .font(AppTypography.captionMicro)
                                .foregroundColor(mom.isBullish ? AppColors.profit : AppColors.loss)
                        }
                    }
                }
            }
        }
    }
}
