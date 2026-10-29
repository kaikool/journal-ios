import SwiftUI
import UIKit

// MARK: - Pre-Trade Multi-Timeframe Chart Vision Card
// Renders timeframe tabs (M15 / H4 / D1 / Tri-Vision), candlestick flow, and full-screen lightbox trigger
public struct PreTradeChartCard: View {
    public let symbol: String
    @Binding public var selectedTimeframe: String
    public let activeBars: [MarketBar]
    public let d1Bars: [MarketBar]
    public let h4Bars: [MarketBar]
    public let h1Bars: [MarketBar]
    public let m15Bars: [MarketBar]
    public let activeProvider: String
    public let onEnlarge: () -> Void
    public let onAttachPhoto: () -> Void
    
    public init(
        symbol: String,
        selectedTimeframe: Binding<String>,
        activeBars: [MarketBar],
        d1Bars: [MarketBar] = [],
        h4Bars: [MarketBar] = [],
        h1Bars: [MarketBar] = [],
        m15Bars: [MarketBar] = [],
        activeProvider: String,
        onEnlarge: @escaping () -> Void,
        onAttachPhoto: @escaping () -> Void
    ) {
        self.symbol = symbol
        self._selectedTimeframe = selectedTimeframe
        self.activeBars = activeBars
        self.d1Bars = d1Bars
        self.h4Bars = h4Bars
        self.h1Bars = h1Bars
        self.m15Bars = m15Bars
        self.activeProvider = activeProvider
        self.onEnlarge = onEnlarge
        self.onAttachPhoto = onAttachPhoto
    }
    
    private var activeTimeframeTitle: String {
        switch selectedTimeframe {
        case "1d": return "D1"
        case "4h": return "H4"
        case "1h": return "H1"
        default: return "M15"
        }
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                // Header with Timeframe Tabs
                HStack {
                    Text("CHART STRUCTURE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    // Timeframe Picker Tabs (M15, H1, H4, D1)
                    HStack(spacing: 2) {
                        timeframeTab(title: "M15", id: "15m")
                        timeframeTab(title: "H1", id: "1h")
                        timeframeTab(title: "H4", id: "4h")
                        timeframeTab(title: "D1", id: "1d")
                    }
                    .padding(2)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(6)
                }
                
                // Chart View Container
                if !activeBars.isEmpty {
                    VStack(spacing: 4) {
                        MarketCandleChartView(
                            bars: activeBars,
                            symbol: symbol,
                            timeframe: activeTimeframeTitle
                        )
                        .frame(height: 210)
                        .background(AppColors.secondaryBackground.opacity(0.35))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onEnlarge)
                        
                        chartFooterActions
                    }
                } else {
                    emptyLoadingView
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private var chartFooterActions: some View {
        HStack(alignment: .center) {
            HStack(spacing: 5) {
                Circle()
                    .fill(AppColors.profit)
                    .frame(width: 5, height: 5)
                Text("\(activeBars.count) bars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Attach custom chart image icon button
                Button(action: onAttachPhoto) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(AppColors.secondaryBackground.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Attach chart image")
                
                // Enlarge full-screen lightbox icon button
                Button(action: onEnlarge) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.brand)
                        .frame(width: 28, height: 28)
                        .background(AppColors.brand.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Enlarge chart")
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
    
    private var emptyLoadingView: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Fetching \(symbol) \(activeTimeframeTitle) candles...")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.vertical, 32)
            Spacer()
        }
    }
    
    private func timeframeTab(title: String, id: String) -> some View {
        let isSel = selectedTimeframe == id
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTimeframe = id
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSel ? .bold : .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(isSel ? AppColors.brand : Color.clear)
                .foregroundColor(isSel ? .white : AppColors.secondaryText)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
