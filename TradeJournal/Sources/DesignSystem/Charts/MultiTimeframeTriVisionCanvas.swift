import SwiftUI

// MARK: - Multi-Timeframe Tri-Panel Vision Canvas
// Stacks D1 (Macro), H4 (Structure), and M15 (Execution) into a single unified visual asset
// for AI Vision inspection and full-screen multi-timeframe review.
public struct MultiTimeframeTriVisionCanvas: View {
    public let symbol: String
    public let d1Bars: [MarketBar]
    public let h4Bars: [MarketBar]
    public let h1Bars: [MarketBar]
    public let m15Bars: [MarketBar]
    
    public init(
        symbol: String,
        d1Bars: [MarketBar],
        h4Bars: [MarketBar],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar]
    ) {
        self.symbol = symbol
        self.d1Bars = d1Bars
        self.h4Bars = h4Bars
        self.h1Bars = h1Bars
        self.m15Bars = m15Bars
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Master Header HUD
            HStack {
                Text("\(symbol) MULTI-TIMEFRAME STRUCTURE")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                
                Spacer()
                
                Text(h1Bars.isEmpty ? "D1 • H4 • M15" : "D1 • H4 • H1 • M15")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.brand.opacity(0.12))
                    .foregroundColor(AppColors.brand)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // Panel 1: D1 Daily Macro Regime
            VStack(alignment: .leading, spacing: 3) {
                panelBadge(title: "1. D1 DAILY MACRO REGIME & KEY HIGHS/LOWS", color: AppColors.brand)
                if !d1Bars.isEmpty {
                    MarketCandleChartView(
                        bars: Array(d1Bars.suffix(30)),
                        symbol: symbol,
                        timeframe: "D1"
                    )
                    .frame(height: 150)
                    .background(AppColors.secondaryBackground.opacity(0.35))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 10)
            
            // Panel 2: H4 4-Hour Swing Structure & Liquidity Bounds
            VStack(alignment: .leading, spacing: 3) {
                panelBadge(title: "2. H4 4-HOUR SWING STRUCTURE & ORDER BLOCKS", color: AppColors.profit)
                if !h4Bars.isEmpty {
                    MarketCandleChartView(
                        bars: Array(h4Bars.suffix(36)),
                        symbol: symbol,
                        timeframe: "H4"
                    )
                    .frame(height: 150)
                    .background(AppColors.secondaryBackground.opacity(0.35))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 10)
            
            // Panel 2b: H1 Intermediate Hourly Structure (if available)
            if !h1Bars.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    panelBadge(title: "3. H1 HOURLY SWING & DYNAMIC TREND", color: Color(red: 0.0, green: 0.85, blue: 1.0))
                    MarketCandleChartView(
                        bars: Array(h1Bars.suffix(40)),
                        symbol: symbol,
                        timeframe: "H1"
                    )
                    .frame(height: 150)
                    .background(AppColors.secondaryBackground.opacity(0.35))
                    .cornerRadius(6)
                }
                .padding(.horizontal, 10)
            }
            
            // Panel 3: M15 15-Minute Execution & Micro Structure
            VStack(alignment: .leading, spacing: 3) {
                panelBadge(title: "\(h1Bars.isEmpty ? "3" : "4"). M15 15-MINUTE EXECUTION & LIQUIDITY SWEEPS", color: .orange)
                if !m15Bars.isEmpty {
                    MarketCandleChartView(
                        bars: Array(m15Bars.suffix(48)),
                        symbol: symbol,
                        timeframe: "M15"
                    )
                    .frame(height: 150)
                    .background(AppColors.secondaryBackground.opacity(0.35))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 440)
        .background(AppColors.cardBackground)
    }
    
    private func panelBadge(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(AppTypography.badgeMicro)
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.3)
        }
        .padding(.horizontal, 2)
    }
}
