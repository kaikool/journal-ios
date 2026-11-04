import SwiftUI

// MARK: - Pure Market Candlestick Chart (Multi-Timeframe Structure View)
// Displays clean institutional candlestick price action with Footprint Key Levels (POC / VAH / VAL / Naked POC)
// and detected Price Action Candlestick Patterns without clutter.
public struct MarketCandleChartView: View {
    public let bars: [MarketBar]
    public let symbol: String
    public let timeframe: String
    public let showStructure: Bool
    public let keyLevels: [KeyLevel]
    public let sessionProfiles: [SessionProfileSnapshot]
    public let developingProfile: DevelopingProfile?
    public let developingProfiles: [DevelopingProfile]
    public let patterns: [DetectedCandlePattern]
    public let onInteractionChanged: ((Bool) -> Void)?

    @State private var viewport = ChartViewportState()

    private var defaultVisibleBars: Int {
        min(max(bars.count, 10), 42)
    }

    private var activeDevelopingProfiles: [DevelopingProfile] {
        !developingProfiles.isEmpty ? developingProfiles : (developingProfile.map { [$0] } ?? [])
    }

    public init(
        bars: [MarketBar],
        symbol: String,
        timeframe: String = "M15",
        showStructure: Bool = true,
        showEMA: Bool = false,
        keyLevels: [KeyLevel] = [],
        sessionProfiles: [SessionProfileSnapshot] = [],
        developingProfile: DevelopingProfile? = nil,
        developingProfiles: [DevelopingProfile] = [],
        patterns: [DetectedCandlePattern] = [],
        onInteractionChanged: ((Bool) -> Void)? = nil
    ) {
        self.bars = bars
        self.symbol = symbol
        self.timeframe = timeframe
        self.showStructure = showStructure
        self.keyLevels = keyLevels
        self.sessionProfiles = sessionProfiles
        self.developingProfile = developingProfile
        self.developingProfiles = !developingProfiles.isEmpty ? developingProfiles : (developingProfile.map { [$0] } ?? [])
        self.patterns = patterns
        self.onInteractionChanged = onInteractionChanged
    }

    public var body: some View {
        VStack(spacing: 4) {
            hudHeaderView

            GeometryReader { geo in
                let pw = max(10, geo.size.width - 55)
                let ph = max(10, geo.size.height - 20)
                candlestickPlotView(size: geo.size)
                    .onAppear {
                        viewport.currentPlotWidth = pw
                        viewport.currentPlotHeight = ph
                        if !viewport.didInitializeViewport && !bars.isEmpty {
                            viewport.didInitializeViewport = true
                            viewport.resetViewport(barsCount: bars.count, plotWidth: pw, defaultVisibleBars: defaultVisibleBars)
                        }
                    }
                    .onChange(of: bars.count) { _ in
                        if !bars.isEmpty {
                            viewport.resetViewport(barsCount: bars.count, plotWidth: viewport.currentPlotWidth, defaultVisibleBars: defaultVisibleBars)
                        }
                    }
            }
            .contentShape(Rectangle())
            .clipped()
            .overlay(
                ChartScrollLockOverlay(
                    rightAxisWidth: 58,
                    bottomAxisHeight: 28,
                    onTouchStateChanged: onInteractionChanged,
                    onCanvasPan: { dx, dy, totalDx, totalDy in
                        viewport.handleCanvasPan(bars: bars, defaultVisibleBars: defaultVisibleBars, dx: dx, dy: dy, totalDx: totalDx, totalDy: totalDy)
                    },
                    onPanEnded: {
                        viewport.hoveredBarIndex = nil
                    },
                    onPriceAxisZoom: { dy in
                        viewport.handlePriceAxisZoom(bars: bars, defaultVisibleBars: defaultVisibleBars, dy: dy)
                    },
                    onTimeAxisZoom: { dx in
                        viewport.handleTimeAxisZoom(barsCount: bars.count, defaultVisibleBars: defaultVisibleBars, dx: dx)
                    },
                    onPinchZoom: { scaleDelta, focalX in
                        viewport.handlePinchZoom(barsCount: bars.count, defaultVisibleBars: defaultVisibleBars, scaleDelta: scaleDelta, focalX: focalX)
                    },
                    onCrosshairChanged: { x in
                        if let locX = x {
                            viewport.updateHoveredBar(at: locX, barsCount: bars.count, defaultVisibleBars: defaultVisibleBars)
                        } else {
                            viewport.hoveredBarIndex = nil
                            viewport.hoveredTouchY = nil
                        }
                    },
                    onCrosshairPointChanged: { pt in
                        if let pt = pt {
                            viewport.hoveredTouchY = max(0, min(viewport.currentPlotHeight, pt.y))
                        } else {
                            viewport.hoveredTouchY = nil
                        }
                    },
                    onPriceAxisDoubleTap: {
                        withAnimation(AppAnimations.springStandard) {
                            viewport.resetPriceScaleToAuto()
                        }
                    },
                    onDoubleTapReset: {
                        withAnimation(AppAnimations.springStandard) {
                            viewport.resetViewport(barsCount: bars.count, plotWidth: viewport.currentPlotWidth, defaultVisibleBars: defaultVisibleBars)
                        }
                    }
                )
            )
        }
    }

    // MARK: - 1. HUD Header Bar
    private var hudHeaderView: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 5) {
                Text(symbol)
                    .font(AppTypography.actionButtonCompact)
                    .foregroundColor(AppColors.primaryText)
                AppBadge(timeframe, style: .neutral)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 2. Candlestick Canvas Plot
    private func candlestickPlotView(size: CGSize) -> some View {
        let m = viewport.computeMetrics(
            bars: bars,
            plotWidth: size.width - 55,
            plotHeight: size.height - 20,
            defaultVisibleBars: defaultVisibleBars
        )

        return ZStack(alignment: .topLeading) {
            SharedChartCanvas.daySeparators(
                bars: bars,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                clampedPan: m.clampedPan
            )

            SharedChartCanvas.gridAndPriceAxis(
                width: m.plotWidth,
                height: m.plotHeight,
                minP: m.minP,
                maxP: m.maxP,
                fullWidth: m.plotWidth + 55,
                symbol: symbol,
                isManualPriceScale: viewport.isManualPriceScale,
                autoBadgeCenter: CGPoint(x: m.plotWidth + 28, y: m.plotHeight + 10)
            )

            SharedChartCanvas.volumeHistogram(
                bars: bars,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                candleWidth: m.candleWidth,
                panOffset: m.clampedPan
            )

            SharedChartCanvas.footprintOverlay(
                bars: bars,
                symbol: symbol,
                keyLevels: keyLevels,
                sessionProfiles: sessionProfiles,
                developingProfiles: activeDevelopingProfiles,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                minP: m.minP,
                span: m.span,
                panOffset: m.clampedPan
            )

            SharedChartCanvas.candlestickCanvas(
                bars: bars,
                patterns: patterns,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                candleWidth: m.candleWidth,
                minP: m.minP,
                span: m.span,
                clampedPan: m.clampedPan
            )

            SharedChartCanvas.timeAxis(
                bars: bars,
                width: m.plotWidth,
                height: m.plotHeight,
                stepX: m.stepX,
                panOffset: m.clampedPan,
                yOffset: 9,
                timeframe: timeframe
            )

            SharedChartCanvas.currentPriceLine(
                bars: bars,
                symbol: symbol,
                hoveredBarIndex: viewport.hoveredBarIndex,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                minP: m.minP,
                span: m.span
            )

            if let hIdx = viewport.hoveredBarIndex, hIdx < bars.count {
                SharedChartCanvas.crosshairOverlay(
                    bars: bars,
                    symbol: symbol,
                    hIdx: hIdx,
                    hoveredTouchY: viewport.hoveredTouchY,
                    plotWidth: m.plotWidth,
                    plotHeight: m.plotHeight,
                    stepX: m.stepX,
                    minP: m.minP,
                    span: m.span,
                    clampedPan: m.clampedPan,
                    timeframe: timeframe
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
