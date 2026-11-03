import SwiftUI

// MARK: - Pre-Trade Quantitative Context Card (EMA 21/50 Multi-Timeframe Trend & Key Levels)
// Provides clean, robust EMA 21 & 50 multi-timeframe trend evaluation alongside
// daily PDH/PDL, ADR 14, H4 Swing High/Low, and Wilder RSI-14 momentum.
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
    
    private var emaAnalysis: MultiTimeframeEMAAnalysis {
        MovingAverageEngine.analyzeMultiTimeframe(
            barsD1: d1Bars,
            barsH4: h4Bars,
            barsH1: h1Bars,
            barsM15: m15Bars,
            symbol: symbol
        )
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
    
    private var h4Swing: (high: Decimal?, low: Decimal?) {
        guard !h4Bars.isEmpty else { return (nil, nil) }
        let h = h4Bars.suffix(24).map(\.high).max()
        let l = h4Bars.suffix(24).map(\.low).min()
        return (h, l)
    }
    
    private var momentumSnapshot: (rsi: Double, signal: Double, isBullish: Bool)? {
        let targetBars = !h1Bars.isEmpty ? h1Bars : m15Bars
        guard targetBars.count >= 14 else { return nil }
        let window = MomentumEngine.computeWindow(bars: targetBars, windowSize: 1)
        guard let pt = window.points.last else { return nil }
        let r = NSDecimalNumber(decimal: pt.rsi14).doubleValue
        let s = NSDecimalNumber(decimal: pt.ema9).doubleValue
        return (r, s, r >= s)
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(AppTypography.cardHeaderUppercase)
                            .foregroundColor(AppColors.brand)
                        
                        Text("TREND & STRUCTURAL CONTEXT")
                            .font(AppTypography.cardHeaderUppercase)
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                    }
                    
                    Spacer()
                    
                    if let cur = livePrice {
                        Text("Live: \(Formatters.price(cur, symbol: symbol))")
                            .font(AppTypography.statValue)
                            .foregroundColor(AppColors.brand)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Section 1: Multi-Timeframe EMA 21 & 50
                VStack(alignment: .leading, spacing: 6) {
                    Text("DYNAMIC TREND (EMA 21 / 50)")
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.3)
                    
                    HStack(spacing: 6) {
                        if let d = emaAnalysis.d1 {
                            timeframeEMAPill(tf: "D1", snap: d)
                        }
                        if let h = emaAnalysis.h4 {
                            timeframeEMAPill(tf: "H4", snap: h)
                        }
                        if let h1 = emaAnalysis.h1 {
                            timeframeEMAPill(tf: "H1", snap: h1)
                        }
                        if let m = emaAnalysis.m15 {
                            timeframeEMAPill(tf: "M15", snap: m)
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.3))
                
                // Section 2: Key Price Levels (PDH / PDL, ADR 14, H4 Swing High / Low)
                VStack(alignment: .leading, spacing: 6) {
                    Text("KEY STRUCTURAL LEVELS")
                        .font(AppTypography.cardHeaderUppercase)
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
                                Text("14-Day ADR")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.price(adr, symbol: symbol))
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        // H4 Swing High & Low
                        if let sh = h4Swing.high, let sl = h4Swing.low {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("H4 High / Low")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(Formatters.price(sh, symbol: symbol)) / \(Formatters.price(sl, symbol: symbol))")
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.brand)
                            }
                        }
                    }
                }
                
                // Section 3: Momentum & RSI 14
                if let mom = momentumSnapshot {
                    Divider().background(AppColors.border.opacity(0.3))
                    
                    HStack(spacing: 8) {
                        Text("RSI(14): \(String(format: "%.1f", mom.rsi))")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Signal: \(String(format: "%.1f", mom.signal))")
                            .font(AppTypography.captionMicro)
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
    
    @ViewBuilder
    private func timeframeEMAPill(tf: String, snap: TimeframeEMASnapshot) -> some View {
        let isBull = snap.trend == .bullish || snap.trend == .strongBullish
        let isBear = snap.trend == .bearish || snap.trend == .strongBearish
        let color = isBull ? AppColors.profit : (isBear ? AppColors.loss : AppColors.warning)
        
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(tf)
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.primaryText)
                
                Text(isBull ? "▲" : (isBear ? "▼" : "⇄"))
                    .font(AppTypography.captionMicro)
                    .foregroundColor(color)
            }
            
            if let e21 = snap.ema21 {
                Text("21: \(Formatters.price(e21, symbol: symbol))")
                    .font(AppTypography.number(9.5, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSubCardStyle(cornerRadius: 6, padding: 6)
    }
}
