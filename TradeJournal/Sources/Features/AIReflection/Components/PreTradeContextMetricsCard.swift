import SwiftUI

// MARK: - Pre-Trade Quantitative Context Card (EMA 21/50 Trend & Institutional Liquidity)
// Replaces complex lagging market structure machines with clean, robust EMA 21 & 50 multi-timeframe
// trend evaluation alongside calendar-verified D1 PDH/PDL and institutional liquidity sweeps.
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
    
    private var liquidityResult: LiquidityAnalysisResult {
        LiquidityEngine.analyzeLiquidity(
            symbol: symbol,
            barsM15: m15Bars,
            barsH4: h4Bars,
            barsD1: d1Bars
        )
    }
    
    private var livePrice: Decimal? {
        m15Bars.last?.close ?? h4Bars.last?.close ?? d1Bars.last?.close
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                        
                        Text("TREND & LIQUIDITY CONTEXT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                    }
                    
                    Spacer()
                    
                    if let cur = livePrice {
                        Text("Live: \(Formatters.price(cur, symbol: symbol))")
                            .font(AppTypography.number(11, weight: .bold))
                            .foregroundColor(AppColors.brand)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Section 1: Multi-Timeframe EMA 21 & 50
                VStack(alignment: .leading, spacing: 6) {
                    Text("DYNAMIC TREND (EMA 21 / 50)")
                        .font(.system(size: 9.5, weight: .semibold))
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
                
                // Section 2: Institutional Liquidity Reference Levels
                VStack(alignment: .leading, spacing: 6) {
                    Text("INSTITUTIONAL LIQUIDITY LEVELS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.3)
                    
                    HStack(spacing: 12) {
                        // D1 PDH / PDL
                        if let h = liquidityResult.pdh, let l = liquidityResult.pdl {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("D1 PDH / PDL")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(Formatters.price(h, symbol: symbol)) / \(Formatters.price(l, symbol: symbol))")
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                        
                        Spacer()
                        
                        // Nearest BSL / SSL Targets
                        if let bsl = liquidityResult.nearestBSL {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nearest BSL")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.price(bsl.price, symbol: symbol))
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.loss)
                            }
                        }
                        
                        if let ssl = liquidityResult.nearestSSL {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nearest SSL")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.price(ssl.price, symbol: symbol))
                                    .font(AppTypography.number(11, weight: .semibold))
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                    }
                }
                
                // Section 3: Recent SFP Sweeps (if any)
                if let sweep = liquidityResult.latestSweep {
                    HStack(spacing: 6) {
                        let isBuySweep = sweep.sweepType == .buySideSwept
                        Image(systemName: isBuySweep ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                            .foregroundColor(isBuySweep ? AppColors.loss : AppColors.profit)
                            .font(.system(size: 12))
                        
                        Text("\(sweep.levelName) Swept (\(sweep.sweepType == .buySideSwept ? "Bearish SFP" : "Bullish SFP"))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isBuySweep ? AppColors.loss : AppColors.profit)
                        
                        Spacer()
                        
                        Text("\(sweep.barsAgo) bars ago")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background((sweep.sweepType == .buySideSwept ? AppColors.loss : AppColors.profit).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                
                Text(isBull ? "▲" : (isBear ? "▼" : "⇄"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
            }
            
            if let e21 = snap.ema21 {
                Text("21: \(Formatters.price(e21, symbol: symbol))")
                    .font(AppTypography.number(9.5, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
