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
    public let onInteractionChanged: ((Bool) -> Void)?

    @State private var keyLevels: [KeyLevel] = []
    @State private var sessionProfiles: [SessionProfileSnapshot] = []
    @State private var developingProfile: DevelopingProfile? = nil
    @State private var developingProfiles: [DevelopingProfile] = []
    @State private var patterns: [DetectedCandlePattern] = []

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
        onAttachPhoto: @escaping () -> Void,
        onInteractionChanged: ((Bool) -> Void)? = nil
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
        self.onInteractionChanged = onInteractionChanged
    }

    private var activeTimeframeTitle: String {
        MarketResolution.label(for: selectedTimeframe)
    }

    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                // Header with Timeframe Tabs
                HStack {
                    Text("CHART STRUCTURE")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)

                    Spacer()

                    // Timeframe Picker Tabs (M15, H1, H4, D1)
                    AppSegmentedBar(
                        selection: $selectedTimeframe,
                        items: ["15m", "1h", "4h", "1d"],
                        titleFor: { MarketResolution.label(for: $0) },
                        height: 28
                    )
                }

                // Chart View Container
                if !activeBars.isEmpty {
                    VStack(spacing: 4) {
                        MarketCandleChartView(
                            bars: activeBars,
                            symbol: symbol,
                            timeframe: activeTimeframeTitle,
                            keyLevels: keyLevels,
                            sessionProfiles: sessionProfiles,
                            developingProfile: developingProfile,
                            developingProfiles: developingProfiles,
                            patterns: patterns,
                            onInteractionChanged: onInteractionChanged
                        )
                        .frame(height: 260)

                        chartFooterActions
                    }
                    .task(id: activeBars.count) {
                        guard !activeBars.isEmpty else { return }
                        let res = await SessionFootprintCoordinator.shared.loadKeyLevels(for: symbol, recentBars: activeBars)
                        self.keyLevels = res.levels
                        self.sessionProfiles = res.profiles
                        self.developingProfile = res.developing
                        self.developingProfiles = res.developingProfiles
                        self.patterns = SessionFootprintCoordinator.shared.scanConfluentPatterns(bars: activeBars, keyLevels: res.levels)
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
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            HStack(spacing: 8) {
                // Attach custom chart image icon button
                ModalCircleButton(icon: "photo.badge.plus", label: "Attach chart image", action: onAttachPhoto)

                // Enlarge full-screen lightbox icon button
                ModalCircleButton(icon: "arrow.up.left.and.arrow.down.right", color: AppColors.brand, label: "Enlarge chart", action: onEnlarge)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var emptyLoadingView: some View {
        LoadingView("Fetching \(symbol) \(activeTimeframeTitle) candles...", size: 36)
            .padding(.vertical, 24)
    }
}
