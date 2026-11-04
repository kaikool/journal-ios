import SwiftUI

/// Professional candlestick chart and execution path view for Trade Replay.
/// Ported 1:1 from `@luxalgo/vela` and `trade-market-data.tsx` / `trade-chart.tsx`.
/// Ensures distinct horizontal coordinates for each bar without timestamp crowding.
public struct CandleChartView: View {
    let visibleBars: [MarketBar]
    let allBars: [MarketBar]
    let totalBarsCount: Int
    let trade: Trade
    let executions: [Execution]
    let throughTimestamp: Int64
    let unrealizedPnl: Decimal
    let timeZone: TimeZone
    let currency: String
    let resolution: MarketResolution
    public var onResolutionChange: ((MarketResolution) -> Void)? = nil
    let showMarketStructure: Bool
    let showRSI: Bool
    let isLandscape: Bool
    public let keyLevels: [KeyLevel]
    public let sessionProfiles: [SessionProfileSnapshot]
    public let developingProfile: DevelopingProfile?
    public let developingProfiles: [DevelopingProfile]
    public let patterns: [DetectedCandlePattern]
    public let onInteractionChanged: ((Bool) -> Void)?
    @State private var activeRSIMAType: MomentumEngine.RSIMAType
    @State private var viewport = ChartViewportState()

    private var defaultVisibleBars: Int {
        min(max(visibleBars.count, 10), isLandscape ? 64 : 42)
    }

    private var activeDevelopingProfiles: [DevelopingProfile] {
        !developingProfiles.isEmpty ? developingProfiles : (developingProfile.map { [$0] } ?? [])
    }

    public init(
        visibleBars: [MarketBar],
        allBars: [MarketBar] = [],
        totalBarsCount: Int,
        trade: Trade,
        executions: [Execution],
        throughTimestamp: Int64,
        unrealizedPnl: Decimal,
        timeZone: TimeZone = .current,
        currency: String = "USD",
        resolution: MarketResolution = .m15,
        showMarketStructure: Bool = true,
        showRSI: Bool = true,
        rsiMAType: MomentumEngine.RSIMAType = .ema,
        isLandscape: Bool = false,
        keyLevels: [KeyLevel] = [],
        sessionProfiles: [SessionProfileSnapshot] = [],
        developingProfile: DevelopingProfile? = nil,
        developingProfiles: [DevelopingProfile] = [],
        patterns: [DetectedCandlePattern] = [],
        onResolutionChange: ((MarketResolution) -> Void)? = nil,
        onInteractionChanged: ((Bool) -> Void)? = nil
    ) {
        self.visibleBars = visibleBars
        self.allBars = allBars.isEmpty ? visibleBars : allBars
        self.totalBarsCount = max(visibleBars.count, totalBarsCount)
        self.trade = trade
        self.executions = executions
        self.throughTimestamp = throughTimestamp
        self.unrealizedPnl = unrealizedPnl
        self.timeZone = timeZone
        self.currency = currency
        self.resolution = resolution
        self.showMarketStructure = showMarketStructure
        self.showRSI = showRSI
        self.isLandscape = isLandscape
        self.keyLevels = keyLevels
        self.sessionProfiles = sessionProfiles
        self.developingProfile = developingProfile
        self.developingProfiles = !developingProfiles.isEmpty ? developingProfiles : (developingProfile.map { [$0] } ?? [])
        self.patterns = patterns
        self.onResolutionChange = onResolutionChange
        self.onInteractionChanged = onInteractionChanged
        self._activeRSIMAType = State(initialValue: rsiMAType)
    }

    public var body: some View {
        VStack(spacing: 4) {
            if !isLandscape {
                hudHeaderView
            }

            VStack(spacing: 0) {
                // 1. Candlestick Canvas drawing
                GeometryReader { geo in
                    let plotW = max(10, geo.size.width - 55)
                    let plotH = max(10, geo.size.height - (showRSI ? 0 : 20))
                    candlestickPlotView(size: geo.size)
                        .onAppear {
                            viewport.currentPlotWidth = plotW
                            viewport.currentPlotHeight = plotH
                            if !viewport.didInitializeViewport && !visibleBars.isEmpty {
                                viewport.didInitializeViewport = true
                                viewport.resetViewport(barsCount: visibleBars.count, plotWidth: plotW, defaultVisibleBars: defaultVisibleBars)
                            }
                        }
                        .onChange(of: visibleBars.count) { _ in
                            if !visibleBars.isEmpty {
                                viewport.resetViewport(barsCount: visibleBars.count, plotWidth: viewport.currentPlotWidth, defaultVisibleBars: defaultVisibleBars)
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: isLandscape ? .infinity : nil)
                .frame(height: isLandscape ? nil : (showRSI ? 220 : 260))
                .clipped()

                // 2. RSI Sub-Window (Underneath)
                if showRSI {
                    Divider()
                        .background(AppColors.border.opacity(0.4))

                    GeometryReader { geo in
                        let m = viewport.computeMetrics(
                            bars: visibleBars,
                            plotWidth: geo.size.width - 55,
                            plotHeight: geo.size.height - 18,
                            defaultVisibleBars: defaultVisibleBars
                        )
                        rsiPlotView(size: geo.size, stepX: m.stepX, panOffset: m.clampedPan)
                    }
                    .frame(height: isLandscape ? 85 : 110)
                    .clipped()
                }
            }
            .contentShape(Rectangle())
            .overlay(
                ChartScrollLockOverlay(
                    rightAxisWidth: 58,
                    bottomAxisHeight: 28,
                    onTouchStateChanged: onInteractionChanged,
                    onCanvasPan: { dx, dy, totalDx, totalDy in
                        viewport.handleCanvasPan(bars: visibleBars, defaultVisibleBars: defaultVisibleBars, dx: dx, dy: dy, totalDx: totalDx, totalDy: totalDy)
                    },
                    onPanEnded: {
                        viewport.hoveredBarIndex = nil
                    },
                    onPriceAxisZoom: { dy in
                        viewport.handlePriceAxisZoom(bars: visibleBars, defaultVisibleBars: defaultVisibleBars, dy: dy)
                    },
                    onTimeAxisZoom: { dx in
                        viewport.handleTimeAxisZoom(barsCount: visibleBars.count, defaultVisibleBars: defaultVisibleBars, dx: dx)
                    },
                    onPinchZoom: { scaleDelta, focalX in
                        viewport.handlePinchZoom(barsCount: visibleBars.count, defaultVisibleBars: defaultVisibleBars, scaleDelta: scaleDelta, focalX: focalX)
                    },
                    onCrosshairChanged: { x in
                        if let locX = x {
                            viewport.updateHoveredBar(at: locX, barsCount: visibleBars.count, defaultVisibleBars: defaultVisibleBars)
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
                            viewport.resetViewport(barsCount: visibleBars.count, plotWidth: viewport.currentPlotWidth, defaultVisibleBars: defaultVisibleBars)
                        }
                    }
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Candlestick chart for \(trade.symbol), \(visibleBars.count) bars visible.")
        }
    }

    // MARK: - 1. HUD Header Bar (Sleek, Minimalist, Pre-Trade Aligned)
    private var hudHeaderView: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(trade.symbol)
                .font(AppTypography.actionButtonCompact)
                .foregroundColor(AppColors.primaryText)

            Spacer()

            if onResolutionChange != nil {
                AppSegmentedBar(
                    selection: Binding(
                        get: { resolution },
                        set: { onResolutionChange?($0) }
                    ),
                    items: [MarketResolution.m15, .h1, .h4],
                    titleFor: { $0.label },
                    height: 28
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 2. Candlestick Main Plot
    private func candlestickPlotView(size: CGSize) -> some View {
        let bottomAxisHeight: CGFloat = showRSI ? 0 : 20
        let m = viewport.computeMetrics(
            bars: visibleBars,
            plotWidth: size.width - 55,
            plotHeight: size.height - bottomAxisHeight,
            defaultVisibleBars: defaultVisibleBars
        )

        return ZStack(alignment: .topLeading) {
            SharedChartCanvas.gridAndPriceAxis(
                width: m.plotWidth,
                height: m.plotHeight,
                minP: m.minP,
                maxP: m.maxP,
                fullWidth: size.width,
                symbol: trade.symbol,
                isManualPriceScale: viewport.isManualPriceScale,
                autoBadgeCenter: CGPoint(x: m.plotWidth + 44, y: m.plotHeight - 10)
            )

            if !showRSI {
                SharedChartCanvas.timeAxis(
                    bars: visibleBars,
                    width: m.plotWidth,
                    height: m.plotHeight,
                    stepX: m.stepX,
                    panOffset: m.clampedPan,
                    yOffset: 10,
                    timeZone: timeZone
                )
            }

            SharedChartCanvas.volumeHistogram(
                bars: visibleBars,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                candleWidth: m.candleWidth,
                panOffset: m.clampedPan
            )

            SharedChartCanvas.candlestickCanvas(
                bars: visibleBars,
                patterns: patterns,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                candleWidth: m.candleWidth,
                minP: m.minP,
                span: m.span,
                clampedPan: m.clampedPan
            )

            SharedChartCanvas.daySeparators(
                bars: visibleBars,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                clampedPan: m.clampedPan
            )

            SharedChartCanvas.footprintOverlay(
                bars: visibleBars,
                symbol: trade.symbol,
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

            tradeOverlay(
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                stepX: m.stepX,
                minP: m.minP,
                span: m.span,
                panOffset: m.clampedPan
            )

            SharedChartCanvas.currentPriceLine(
                bars: visibleBars,
                symbol: trade.symbol,
                hoveredBarIndex: viewport.hoveredBarIndex,
                plotWidth: m.plotWidth,
                plotHeight: m.plotHeight,
                minP: m.minP,
                span: m.span
            )

            if let hIdx = viewport.hoveredBarIndex, hIdx < visibleBars.count {
                SharedChartCanvas.crosshairOverlay(
                    bars: visibleBars,
                    symbol: trade.symbol,
                    hIdx: hIdx,
                    hoveredTouchY: viewport.hoveredTouchY,
                    plotWidth: m.plotWidth,
                    plotHeight: m.plotHeight,
                    stepX: m.stepX,
                    minP: m.minP,
                    span: m.span,
                    clampedPan: m.clampedPan,
                    timeZone: timeZone
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - 3. Unified Trade Overlay (Entry/Exit Lines, Fill Markers, Connecting Line)
    private func findBarIndex(for timestampMs: Int64) -> Int? {
        guard !visibleBars.isEmpty else { return nil }
        let dur = resolution.durationMs
        for i in stride(from: visibleBars.count - 1, through: 0, by: -1) {
            let barStart = visibleBars[i].timestamp
            let barEnd = (i + 1 < visibleBars.count) ? visibleBars[i + 1].timestamp : (barStart + dur)
            if timestampMs >= barStart && timestampMs < barEnd {
                return i
            }
        }
        return nil
    }

    private func tradeOverlay(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, minP: Double, span: Double, panOffset: CGFloat = 0) -> some View {
        let entryD = (trade.avgEntry as NSDecimalNumber).doubleValue
        let yEntry = plotHeight - CGFloat((entryD - minP) / span) * plotHeight
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs = Int64((trade.closedAt ?? Date()).timeIntervalSince1970 * 1000)

        let entryBarIdx = findBarIndex(for: openMs)
        let exitBarIdx = findBarIndex(for: closeMs)

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: yEntry))
                path.addLine(to: CGPoint(x: plotWidth, y: yEntry))
            }
            .stroke(AppColors.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            if let entryIdx = entryBarIdx {
                let entryX = CGFloat(entryIdx) * stepX + (stepX / 2.0) + panOffset

                Text("EN")
                    .font(AppTypography.badgeMarker)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(AppColors.profit)
                    .foregroundColor(.white)
                    .cornerRadius(3)
                    .position(x: min(plotWidth - 20, max(20, entryX)), y: max(8, yEntry - 10))

                Image(systemName: trade.direction == .long ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(AppTypography.badgeMarker)
                    .foregroundColor(AppColors.profit)
                    .position(x: entryX, y: trade.direction == .long ? yEntry + 8 : yEntry - 8)
            }

            if let exitIdx = exitBarIdx, trade.status != .open {
                let exitD = ((trade.avgExit ?? trade.avgEntry) as NSDecimalNumber).doubleValue
                let yExit = plotHeight - CGFloat((exitD - minP) / span) * plotHeight
                let exitX = CGFloat(exitIdx) * stepX + (stepX / 2.0) + panOffset
                let exitColor = AppColors.loss

                Path { path in
                    path.move(to: CGPoint(x: 0, y: yExit))
                    path.addLine(to: CGPoint(x: plotWidth, y: yExit))
                }
                .stroke(exitColor.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if let entryIdx = entryBarIdx {
                    let entryX = CGFloat(entryIdx) * stepX + (stepX / 2.0) + panOffset
                    Path { path in
                        path.move(to: CGPoint(x: entryX, y: yEntry))
                        path.addLine(to: CGPoint(x: exitX, y: yExit))
                    }
                    .stroke(exitColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }

                Text("EX")
                    .font(AppTypography.badgeMarker)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(exitColor)
                    .foregroundColor(.white)
                    .cornerRadius(3)
                    .position(x: min(plotWidth - 20, max(20, exitX)), y: max(8, yExit - 10))

                Image(systemName: trade.direction == .long ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    .font(AppTypography.badgeMarker)
                    .foregroundColor(exitColor)
                    .position(x: exitX, y: trade.direction == .long ? yExit - 8 : yExit + 8)
            } else if let entryIdx = entryBarIdx, let curBar = visibleBars.last {
                let entryX = CGFloat(entryIdx) * stepX + (stepX / 2.0) + panOffset
                let curPrice = (curBar.close as NSDecimalNumber).doubleValue
                let yCur = plotHeight - CGFloat((curPrice - minP) / span) * plotHeight
                let curX = CGFloat(visibleBars.count - 1) * stepX + (stepX / 2.0) + panOffset
                let curPnl = TradeReplayEngine.computeUnrealizedPnl(trade: trade, currentPrice: curBar.close, isLastBar: false)
                let curColor = Formatters.pnlColor(curPnl)

                Path { path in
                    path.move(to: CGPoint(x: entryX, y: yEntry))
                    path.addLine(to: CGPoint(x: curX, y: yCur))
                }
                .stroke(curColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }
    }

    // MARK: - 4. RSI Sub-Window View & Plot
    private var rsiSeries: [Double?] {
        let reference = allBars.isEmpty ? visibleBars : allBars
        return MomentumEngine.computeRSISeries(bars: reference, period: 14)
    }

    private var visibleRsi: [Double?] {
        Array(rsiSeries.prefix(visibleBars.count))
    }

    private var rsiEma9Series: [Double?] {
        MomentumEngine.computeEMA(series: rsiSeries, period: 9)
    }

    private var visibleRsiEma9: [Double?] {
        Array(rsiEma9Series.prefix(visibleBars.count))
    }

    private var rsiWma45Series: [Double?] {
        MomentumEngine.computeWMA(series: rsiSeries, period: 45)
    }

    private var visibleRsiWma45: [Double?] {
        Array(rsiWma45Series.prefix(visibleBars.count))
    }

    private func rsiPlotView(size: CGSize, stepX: CGFloat, panOffset: CGFloat = 0) -> some View {
        let rightAxisWidth: CGFloat = 55
        let bottomAxisHeight: CGFloat = 18
        let plotWidth = max(10, size.width - rightAxisWidth)
        let plotHeight = max(10, size.height - bottomAxisHeight)
        let stX = max(1.0, stepX)

        let y70 = plotHeight * 0.30
        let y50 = plotHeight * 0.50
        let y30 = plotHeight * 0.70
        let bandH = y30 - y70

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.06))
                .frame(width: plotWidth, height: bandH)
                .position(x: plotWidth / 2.0, y: y70 + bandH / 2.0)

            Path { path in
                path.move(to: CGPoint(x: 0, y: y70))
                path.addLine(to: CGPoint(x: plotWidth, y: y70))
            }
            .stroke(AppColors.loss.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            Text("70")
                .font(AppTypography.number(8, weight: .regular))
                .foregroundColor(AppColors.loss.opacity(0.7))
                .frame(width: 50, alignment: .leading)
                .position(x: plotWidth + 28, y: y70)

            Path { path in
                path.move(to: CGPoint(x: 0, y: y50))
                path.addLine(to: CGPoint(x: plotWidth, y: y50))
            }
            .stroke(AppColors.secondaryText.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

            Text("50")
                .font(AppTypography.number(8, weight: .regular))
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
                .frame(width: 50, alignment: .leading)
                .position(x: plotWidth + 28, y: y50)

            Path { path in
                path.move(to: CGPoint(x: 0, y: y30))
                path.addLine(to: CGPoint(x: plotWidth, y: y30))
            }
            .stroke(AppColors.profit.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            Text("30")
                .font(AppTypography.number(8, weight: .regular))
                .foregroundColor(AppColors.profit.opacity(0.7))
                .frame(width: 50, alignment: .leading)
                .position(x: plotWidth + 28, y: y30)

            // 1. RSI Curve (Wilder's RSI 14 - Purple)
            rsiCurvePath(series: visibleRsi, stepX: stX, plotHeight: plotHeight, panOffset: panOffset)
                .stroke(Color(red: 0.65, green: 0.45, blue: 0.95), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .clipped()

            // 2. EMA 9 Curve of RSI 14 (Sky Blue / Cyan)
            rsiCurvePath(series: visibleRsiEma9, stepX: stX, plotHeight: plotHeight, panOffset: panOffset)
                .stroke(Color(red: 0.22, green: 0.74, blue: 0.97), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .clipped()

            // 3. WMA 45 Curve of RSI 14 (Gold / Amber)
            rsiCurvePath(series: visibleRsiWma45, stepX: stX, plotHeight: plotHeight, panOffset: panOffset)
                .stroke(Color(red: 1.0, green: 0.82, blue: 0.2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .clipped()

            // 4. Active / Hovered dot and cursor line
            if let hIdx = viewport.hoveredBarIndex, hIdx < visibleBars.count {
                let hX = CGFloat(hIdx) * stX + (stX / 2.0) + panOffset
                if hX >= 0 && hX <= plotWidth {
                    Rectangle()
                        .fill(AppColors.primaryText.opacity(0.4))
                        .frame(width: 1, height: plotHeight)
                        .position(x: hX, y: plotHeight / 2.0)

                    rsiHoverDot(series: visibleRsi, index: hIdx, x: hX, plotHeight: plotHeight, color: Color(red: 0.65, green: 0.45, blue: 0.95))
                    rsiHoverDot(series: visibleRsiEma9, index: hIdx, x: hX, plotHeight: plotHeight, color: Color(red: 0.22, green: 0.74, blue: 0.97))
                    rsiHoverDot(series: visibleRsiWma45, index: hIdx, x: hX, plotHeight: plotHeight, color: Color(red: 1.0, green: 0.82, blue: 0.2))
                }
            }

            SharedChartCanvas.timeAxis(
                bars: visibleBars,
                width: plotWidth,
                height: plotHeight,
                stepX: stX,
                panOffset: panOffset,
                yOffset: 10,
                timeZone: timeZone
            )
        }
    }

    private func rsiCurvePath(series: [Double?], stepX: CGFloat, plotHeight: CGFloat, panOffset: CGFloat) -> Path {
        Path { path in
            var isFirst = true
            for (i, valOpt) in series.enumerated() {
                guard let val = valOpt else { continue }
                let x = CGFloat(i) * stepX + (stepX / 2.0) + panOffset
                let y = max(2, min(plotHeight - 2, plotHeight - CGFloat(val / 100.0) * plotHeight))
                if isFirst {
                    path.move(to: CGPoint(x: x, y: y))
                    isFirst = false
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    @ViewBuilder
    private func rsiHoverDot(series: [Double?], index: Int, x: CGFloat, plotHeight: CGFloat, color: Color) -> some View {
        if index < series.count, let val = series[index] {
            let y = max(2, min(plotHeight - 2, plotHeight - CGFloat(val / 100.0) * plotHeight))
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .position(x: x, y: y)
        }
    }
}
