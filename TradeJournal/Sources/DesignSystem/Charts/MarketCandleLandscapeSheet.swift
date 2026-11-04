import SwiftUI

// MARK: - Dedicated Fullscreen Landscape Chart View for Market Candlesticks
// Provides an expansive horizontal institutional inspection canvas for Pre-Trade, Live Coach, and Post-Trade.
// Works seamlessly in both native landscape and forced 90-degree landscape rotation.
public struct MarketCandleLandscapeSheet: View {
    public let bars: [MarketBar]
    public let symbol: String
    @Binding public var selectedTimeframe: String
    public let timeframeOptions: [String]
    public let timeframeTitle: (String) -> String
    public let keyLevels: [KeyLevel]
    public let sessionProfiles: [SessionProfileSnapshot]
    public let developingProfile: DevelopingProfile?
    public let developingProfiles: [DevelopingProfile]
    public let patterns: [DetectedCandlePattern]
    public let onDismiss: () -> Void

    @State private var isForceLandscape90: Bool = true
    @State private var dynamicLevels: [KeyLevel] = []
    @State private var dynamicProfiles: [SessionProfileSnapshot] = []
    @State private var dynamicDeveloping: DevelopingProfile? = nil
    @State private var dynamicDevelopingProfiles: [DevelopingProfile] = []
    @State private var dynamicPatterns: [DetectedCandlePattern] = []

    public init(
        bars: [MarketBar],
        symbol: String,
        selectedTimeframe: Binding<String>,
        timeframeOptions: [String],
        timeframeTitle: @escaping (String) -> String,
        keyLevels: [KeyLevel] = [],
        sessionProfiles: [SessionProfileSnapshot] = [],
        developingProfile: DevelopingProfile? = nil,
        developingProfiles: [DevelopingProfile] = [],
        patterns: [DetectedCandlePattern] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.bars = bars
        self.symbol = symbol
        self._selectedTimeframe = selectedTimeframe
        self.timeframeOptions = timeframeOptions
        self.timeframeTitle = timeframeTitle
        self.keyLevels = keyLevels
        self.sessionProfiles = sessionProfiles
        self.developingProfile = developingProfile
        self.developingProfiles = !developingProfiles.isEmpty ? developingProfiles : (developingProfile.map { [$0] } ?? [])
        self.patterns = patterns
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geo in
            let isNativeLandscape = geo.size.width > geo.size.height
            let rotate = !isNativeLandscape && isForceLandscape90
            let targetWidth = rotate ? geo.size.height : geo.size.width
            let targetHeight = rotate ? geo.size.width : geo.size.height

            ZStack {
                VStack(spacing: 8) {
                    // 1. Top Navigation & Timeframe Selector Bar
                    topNavBar

                    // 2. Wide Edge-to-Edge Candlestick Chart
                    MarketCandleChartView(
                        bars: bars,
                        symbol: symbol,
                        timeframe: timeframeTitle(selectedTimeframe),
                        keyLevels: !keyLevels.isEmpty ? keyLevels : dynamicLevels,
                        sessionProfiles: !sessionProfiles.isEmpty ? sessionProfiles : dynamicProfiles,
                        developingProfile: developingProfile ?? dynamicDeveloping,
                        developingProfiles: !developingProfiles.isEmpty ? developingProfiles : dynamicDevelopingProfiles,
                        patterns: !patterns.isEmpty ? patterns : dynamicPatterns
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(width: targetWidth, height: targetHeight)
                .rotationEffect(rotate ? .degrees(90) : .degrees(0))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(AppColors.background.ignoresSafeArea())
        }
        .statusBarHidden(true)
        .task(id: bars.count) {
            guard !bars.isEmpty else { return }
            if keyLevels.isEmpty {
                let res = await SessionFootprintCoordinator.shared.loadKeyLevels(for: symbol, recentBars: bars)
                self.dynamicLevels = res.levels
                self.dynamicProfiles = res.profiles
                self.dynamicDeveloping = res.developing
                self.dynamicDevelopingProfiles = res.developingProfiles
                self.dynamicPatterns = SessionFootprintCoordinator.shared.scanConfluentPatterns(bars: bars, keyLevels: res.levels)
            }
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ModalDismissButton {
                onDismiss()
            }

            Text(symbol)
                .font(AppTypography.cardHeader)
                .foregroundColor(AppColors.primaryText)

            HStack(spacing: 5) {
                Circle()
                    .fill(AppColors.profit)
                    .frame(width: 5, height: 5)
                Text("\(bars.count) bars")
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            AppSegmentedBar(
                selection: $selectedTimeframe,
                items: timeframeOptions,
                titleFor: timeframeTitle,
                height: 28
            )
        }
    }
}
