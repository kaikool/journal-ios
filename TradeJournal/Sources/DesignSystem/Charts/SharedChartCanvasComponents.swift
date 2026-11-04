import SwiftUI

// MARK: - Unified TradingView Viewport State & Math Engine
public struct ChartViewportMetrics {
    public let plotWidth: CGFloat
    public let plotHeight: CGFloat
    public let stepX: CGFloat
    public let candleWidth: CGFloat
    public let clampedPan: CGFloat
    public let minP: Double
    public let maxP: Double
    public let span: Double
}

@MainActor
public struct ChartViewportState {
    public var hoveredBarIndex: Int? = nil
    public var hoveredTouchY: CGFloat? = nil
    public var zoomScale: CGFloat = 1.0
    public var panOffset: CGFloat = 0.0
    public var isManualPriceScale: Bool = false
    public var manualCenterPrice: Double = 0.0
    public var manualPriceSpan: Double = 0.0
    public var currentPlotWidth: CGFloat = 320
    public var currentPlotHeight: CGFloat = 220
    public var didInitializeViewport: Bool = false

    public init() {}

    public func computeMetrics(
        bars: [MarketBar],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        defaultVisibleBars: Int
    ) -> ChartViewportMetrics {
        let pw = max(10, plotWidth)
        let ph = max(10, plotHeight)
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
        let stepX = pw / CGFloat(max(1.0, slotCount))
        let candleWidth = max(2.0, min(22.0, stepX * 0.72))

        let maxRightSpace = max(stepX * 6.0, pw * 0.45)
        let totalContentWidth = CGFloat(bars.count) * stepX + maxRightSpace
        let minPan = min(0, pw - totalContentWidth)
        let maxPan = stepX * 2.0
        let clampedPan = min(maxPan, max(minPan, panOffset))

        let autoBounds = Self.computeAutoPriceBounds(bars: bars, stepX: stepX, clampedPan: clampedPan, plotWidth: pw)
        let minP: Double
        let maxP: Double
        if isManualPriceScale && manualPriceSpan > 0 {
            minP = manualCenterPrice - (manualPriceSpan / 2.0)
            maxP = manualCenterPrice + (manualPriceSpan / 2.0)
        } else {
            minP = autoBounds.minP
            maxP = autoBounds.maxP
        }
        let span = max(0.00001, maxP - minP)

        return ChartViewportMetrics(
            plotWidth: pw,
            plotHeight: ph,
            stepX: stepX,
            candleWidth: candleWidth,
            clampedPan: clampedPan,
            minP: minP,
            maxP: maxP,
            span: span
        )
    }

    public static func computeAutoPriceBounds(
        bars: [MarketBar],
        stepX: CGFloat,
        clampedPan: CGFloat,
        plotWidth: CGFloat
    ) -> (minP: Double, maxP: Double) {
        guard !bars.isEmpty, stepX > 0 else { return (1.0, 2.0) }
        let leftX = -clampedPan
        let rightX = leftX + plotWidth
        let startIdx = max(0, min(bars.count - 1, Int(floor(leftX / stepX))))
        let endIdx = max(startIdx, min(bars.count - 1, Int(ceil(rightX / stepX))))

        let slice = bars[startIdx...endIdx]
        let lows = slice.map { ($0.low as NSDecimalNumber).doubleValue }
        let highs = slice.map { ($0.high as NSDecimalNumber).doubleValue }
        let minVal = lows.min() ?? 1.0
        let maxVal = highs.max() ?? 2.0
        let rawSpan = max(0.0001, maxVal - minVal)
        let pad = rawSpan * 0.08
        return (minP: minVal - pad, maxP: maxVal + pad)
    }

    public mutating func resetViewport(barsCount: Int, plotWidth: CGFloat, defaultVisibleBars: Int) {
        let pw = max(10, plotWidth)
        zoomScale = 1.0
        isManualPriceScale = false
        manualCenterPrice = 0
        manualPriceSpan = 0
        hoveredBarIndex = nil
        hoveredTouchY = nil
        let stepX = pw / CGFloat(max(1, defaultVisibleBars))
        let defaultRightMargin = stepX * 5.0
        let totalW = CGFloat(barsCount) * stepX + defaultRightMargin
        panOffset = min(0, pw - totalW)
    }

    public mutating func resetPriceScaleToAuto() {
        isManualPriceScale = false
        manualCenterPrice = 0
        manualPriceSpan = 0
    }

    public mutating func ensureManualPriceScaleInitialized(bars: [MarketBar], stepX: CGFloat, plotWidth: CGFloat) {
        guard !isManualPriceScale || manualPriceSpan <= 0 else { return }
        let maxRightSpace = max(stepX * 6.0, plotWidth * 0.45)
        let totalContentWidth = CGFloat(bars.count) * stepX + maxRightSpace
        let minPan = min(0, plotWidth - totalContentWidth)
        let maxPan = stepX * 2.0
        let clampedPan = min(maxPan, max(minPan, panOffset))
        let auto = Self.computeAutoPriceBounds(bars: bars, stepX: stepX, clampedPan: clampedPan, plotWidth: plotWidth)
        manualCenterPrice = (auto.minP + auto.maxP) / 2.0
        manualPriceSpan = max(0.00001, auto.maxP - auto.minP)
        isManualPriceScale = true
    }

    public mutating func handleCanvasPan(
        bars: [MarketBar],
        defaultVisibleBars: Int,
        dx: CGFloat,
        dy: CGFloat,
        totalDx: CGFloat,
        totalDy: CGFloat
    ) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let plotH = max(10, currentPlotHeight)
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
        let stepX = plotW / CGFloat(max(1.0, slotCount))

        let maxRightSpace = max(stepX * 6.0, plotW * 0.45)
        let totalW = CGFloat(bars.count) * stepX + maxRightSpace
        let minOffset = min(0, plotW - totalW)
        let maxOffset = stepX * 2.0
        panOffset = min(maxOffset, max(minOffset, panOffset + dx))

        if !isManualPriceScale && abs(totalDy) > 10 && abs(totalDy) > abs(totalDx) * 1.1 {
            ensureManualPriceScaleInitialized(bars: bars, stepX: stepX, plotWidth: plotW)
        }
        if isManualPriceScale && manualPriceSpan > 0 {
            let priceShift = (Double(dy) / Double(plotH)) * manualPriceSpan
            manualCenterPrice += priceShift
        }
    }

    public mutating func handlePriceAxisZoom(bars: [MarketBar], defaultVisibleBars: Int, dy: CGFloat) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let plotH = max(10, currentPlotHeight)
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
        let stepX = plotW / CGFloat(max(1.0, slotCount))

        ensureManualPriceScaleInitialized(bars: bars, stepX: stepX, plotWidth: plotW)
        let scaleChange = max(0.85, min(1.18, 1.0 + Double(dy / max(80, plotH)) * 1.8))
        manualPriceSpan = max(0.00001, manualPriceSpan * scaleChange)
    }

    public mutating func handleTimeAxisZoom(barsCount: Int, defaultVisibleBars: Int, dx: CGFloat) {
        guard barsCount > 0 else { return }
        let plotW = max(10, currentPlotWidth)
        let scaleDelta = max(0.85, min(1.18, 1.0 + (dx / max(90, plotW)) * 1.8))
        let oldSlotCount = max(6.0, Double(defaultVisibleBars) / Double(zoomScale))
        let oldStepX = plotW / CGFloat(max(1.0, oldSlotCount))
        let anchorX = max(plotW * 0.5, min(plotW, plotW - oldStepX * 5.0))
        applyHorizontalZoom(barsCount: barsCount, defaultVisibleBars: defaultVisibleBars, scaleDelta: scaleDelta, anchorX: anchorX)
    }

    public mutating func handlePinchZoom(barsCount: Int, defaultVisibleBars: Int, scaleDelta: CGFloat, focalX: CGFloat) {
        guard barsCount > 0 else { return }
        let plotW = max(10, currentPlotWidth)
        let anchorX = max(0, min(plotW, focalX))
        applyHorizontalZoom(barsCount: barsCount, defaultVisibleBars: defaultVisibleBars, scaleDelta: scaleDelta, anchorX: anchorX)
    }

    public mutating func applyHorizontalZoom(barsCount: Int, defaultVisibleBars: Int, scaleDelta: CGFloat, anchorX: CGFloat) {
        let plotW = max(10, currentPlotWidth)
        let oldZoom = zoomScale
        let newZoom = max(0.25, min(6.0, oldZoom * scaleDelta))
        guard abs(newZoom - oldZoom) > 0.0001 else { return }

        let oldSlotCount = max(6.0, Double(defaultVisibleBars) / Double(oldZoom))
        let oldStepX = plotW / CGFloat(max(1.0, oldSlotCount))
        let barPosAtAnchor = (anchorX - panOffset) / oldStepX

        zoomScale = newZoom

        let newSlotCount = max(6.0, Double(defaultVisibleBars) / Double(newZoom))
        let newStepX = plotW / CGFloat(max(1.0, newSlotCount))
        let maxRightSpace = max(newStepX * 6.0, plotW * 0.45)
        let newTotalW = CGFloat(barsCount) * newStepX + maxRightSpace
        let newMinOffset = min(0, plotW - newTotalW)
        let newMaxOffset = newStepX * 2.0

        let rawNewPan = anchorX - (barPosAtAnchor * newStepX)
        panOffset = min(newMaxOffset, max(newMinOffset, rawNewPan))
    }

    public mutating func updateHoveredBar(
        at x: CGFloat,
        barsCount: Int,
        defaultVisibleBars: Int,
        stepX: CGFloat? = nil
    ) {
        guard barsCount > 0, currentPlotWidth > 0 else { return }
        let stX: CGFloat = {
            if let s = stepX, s > 0 { return s }
            let effectiveZoom = max(0.25, min(6.0, zoomScale))
            let slotCount = max(6.0, Double(defaultVisibleBars) / Double(effectiveZoom))
            return currentPlotWidth / CGFloat(max(1.0, slotCount))
        }()
        let adjustedX = x - panOffset
        let index = max(0, min(barsCount - 1, Int(adjustedX / stX)))
        if hoveredBarIndex != index {
            hoveredBarIndex = index
            NativeHaptics.selection()
        }
    }
}

// MARK: - Unified Candlestick, Footprint, Grid & Crosshair Rendering Engine
@MainActor
public enum SharedChartCanvas {

    // MARK: 1. Candlesticks (GPU-accelerated Canvas)
    public static func candlestickCanvas(
        bars: [MarketBar],
        patterns: [DetectedCandlePattern],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        candleWidth: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat
    ) -> some View {
        Canvas { context, _ in
            for (i, bar) in bars.enumerated() {
                let xCenter = CGFloat(i) * stepX + (stepX / 2.0) + clampedPan
                guard xCenter >= -candleWidth && xCenter <= (plotWidth + candleWidth) else { continue }

                let matchedPattern = patterns.first(where: {
                    $0.barTimestamp == bar.timestamp && $0.type != .insideBar && $0.type != .doji
                })
                let isPattern = matchedPattern != nil
                let candleColor: Color
                if let pat = matchedPattern {
                    candleColor = pat.type.isBullish ? AppColors.patternBullish : AppColors.patternBearish
                } else {
                    candleColor = bar.isUp ? AppColors.candleUp : AppColors.candleDown
                }

                let highD = (bar.high as NSDecimalNumber).doubleValue
                let lowD = (bar.low as NSDecimalNumber).doubleValue
                let openD = (bar.open as NSDecimalNumber).doubleValue
                let closeD = (bar.close as NSDecimalNumber).doubleValue

                let yHigh = plotHeight - CGFloat((highD - minP) / span) * plotHeight
                let yLow = plotHeight - CGFloat((lowD - minP) / span) * plotHeight
                let yOpen = plotHeight - CGFloat((openD - minP) / span) * plotHeight
                let yClose = plotHeight - CGFloat((closeD - minP) / span) * plotHeight

                var wickPath = Path()
                wickPath.move(to: CGPoint(x: xCenter, y: yHigh))
                wickPath.addLine(to: CGPoint(x: xCenter, y: yLow))
                context.stroke(wickPath, with: .color(candleColor), lineWidth: isPattern ? 1.5 : 1.0)

                let bodyTop = min(yOpen, yClose)
                let bodyHeight = max(1.5, abs(yOpen - yClose))
                let bodyRect = CGRect(
                    x: xCenter - (candleWidth / 2.0),
                    y: bodyTop,
                    width: candleWidth,
                    height: bodyHeight
                )
                context.fill(Path(bodyRect), with: .color(candleColor))
                if isPattern {
                    context.stroke(Path(bodyRect), with: .color(candleColor.opacity(0.9)), lineWidth: 1.0)
                }
            }
        }
        .frame(width: plotWidth, height: plotHeight)
    }

    // MARK: 2. TradingView Day / Session Vertical Dividers
    @ViewBuilder
    public static func daySeparators(
        bars: [MarketBar],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        clampedPan: CGFloat
    ) -> some View {
        let cal: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = SessionFootprintEngine.sessionTimeZone
            return c
        }()

        if bars.count >= 2 {
            ForEach(1..<bars.count, id: \.self) { i in
                let curr = bars[i]
                let prev = bars[i - 1]
                if !cal.isDate(curr.date, inSameDayAs: prev.date) {
                    let x = CGFloat(i) * stepX + clampedPan
                    if x >= 0 && x <= plotWidth {
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: plotHeight))
                        }
                        .stroke(AppColors.secondaryText.opacity(0.12), style: StrokeStyle(lineWidth: 1.0, dash: [2, 4]))
                    }
                }
            }
        }
    }

    // MARK: 3. Price Grid & Right Price Axis + "A" Auto-Scale Badge
    public static func gridAndPriceAxis(
        width: CGFloat,
        height: CGFloat,
        minP: Double,
        maxP: Double,
        fullWidth: CGFloat,
        symbol: String,
        isManualPriceScale: Bool,
        autoBadgeCenter: CGPoint
    ) -> some View {
        let levels = 4
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height + 20))
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: fullWidth, y: height))
            }
            .stroke(AppColors.border.opacity(0.32), lineWidth: 0.8)

            ForEach(0...levels, id: \.self) { i in
                let ratio = Double(i) / Double(levels)
                let price = minP + ratio * (maxP - minP)
                let y = height - CGFloat(ratio) * height
                let clampedY = max(8, min(height - 8, y))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(AppColors.border.opacity(0.18), style: StrokeStyle(lineWidth: 0.8, dash: [2, 4]))

                Text(Formatters.price(Decimal(price), symbol: symbol))
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .frame(width: 50, alignment: .leading)
                    .position(x: width + 28, y: clampedY)
            }

            Text("A")
                .font(AppTypography.badgeMarkerSmall)
                .foregroundColor(isManualPriceScale ? AppColors.secondaryText.opacity(0.65) : .white)
                .frame(width: 16, height: 14)
                .background(isManualPriceScale ? AppColors.cardBackground : AppColors.accent.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isManualPriceScale ? AppColors.border.opacity(0.6) : Color.clear, lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .position(autoBadgeCenter)
        }
    }

    // MARK: 4. Time Axis
    public static func timeAxis(
        bars: [MarketBar],
        width: CGFloat,
        height: CGFloat,
        stepX: CGFloat,
        panOffset: CGFloat,
        yOffset: CGFloat = 9,
        timeZone: TimeZone = .current,
        timeframe: String? = nil
    ) -> some View {
        let count = bars.count
        let markInterval = max(1, count / 4)

        return ForEach(0..<count, id: \.self) { i in
            if i % markInterval == 0 || i == count - 1 {
                let x = CGFloat(i) * stepX + (stepX / 2.0) + panOffset
                if x >= 0 && x <= width {
                    let timeStr = formatBarTime(bars[i].timestamp, bars: bars, timeZone: timeZone, timeframe: timeframe)
                    Text(timeStr)
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                        .position(x: x, y: height + yOffset)
                }
            }
        }
    }

    // MARK: 5. Volume Histogram
    public static func volumeHistogram(
        bars: [MarketBar],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        candleWidth: CGFloat,
        panOffset: CGFloat
    ) -> some View {
        let maxVol = bars.map { ($0.volume as NSDecimalNumber).doubleValue }.max() ?? 1.0
        let safeMaxVol = max(1.0, maxVol)
        let volAreaHeight = plotHeight * 0.16

        return ForEach(0..<bars.count, id: \.self) { i in
            let bar = bars[i]
            let vol = (bar.volume as NSDecimalNumber).doubleValue
            let height = CGFloat(vol / safeMaxVol) * volAreaHeight
            let xCenter = CGFloat(i) * stepX + (stepX / 2.0) + panOffset

            if xCenter >= -candleWidth && xCenter <= (plotWidth + candleWidth) {
                let color = (bar.isUp ? AppColors.candleUp : AppColors.candleDown).opacity(0.22)
                Rectangle()
                    .fill(color)
                    .frame(width: max(1.5, candleWidth * 0.75), height: max(1, height))
                    .position(x: xCenter, y: plotHeight - height / 2.0)
            }
        }
    }

    // MARK: 6. Live Current Price Line & Badge
    @ViewBuilder
    public static func currentPriceLine(
        bars: [MarketBar],
        symbol: String,
        hoveredBarIndex: Int?,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        minP: Double,
        span: Double
    ) -> some View {
        if let lastBar = bars.last {
            let lastPriceD = (lastBar.close as NSDecimalNumber).doubleValue
            let y = plotHeight - CGFloat((lastPriceD - minP) / span) * plotHeight
            let col = lastBar.isUp ? AppColors.candleUp : AppColors.candleDown

            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: plotWidth, y: y))
            }
            .stroke(col.opacity(0.75), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))

            if hoveredBarIndex == nil {
                Text(Formatters.price(lastBar.close, symbol: symbol))
                    .font(AppTypography.captionMicro)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(col)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .position(x: plotWidth + 28, y: max(8, min(plotHeight - 8, y)))
            }
        }
    }

    // MARK: 7. Dual-Axis Crosshair Overlay (Vertical + Horizontal + Badges)
    @ViewBuilder
    public static func crosshairOverlay(
        bars: [MarketBar],
        symbol: String,
        hIdx: Int,
        hoveredTouchY: CGFloat?,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat,
        timeZone: TimeZone = .current,
        timeframe: String? = nil
    ) -> some View {
        if hIdx < bars.count {
            let hBar = bars[hIdx]
            let hX = CGFloat(hIdx) * stepX + (stepX / 2.0) + clampedPan
            let closeD = (hBar.close as NSDecimalNumber).doubleValue
            let yClose = plotHeight - CGFloat((closeD - minP) / span) * plotHeight
            let yCross = hoveredTouchY ?? max(0, min(plotHeight, yClose))
            let crossPrice = minP + Double((plotHeight - yCross) / max(1, plotHeight)) * span

            Path { path in
                path.move(to: CGPoint(x: hX, y: 0))
                path.addLine(to: CGPoint(x: hX, y: plotHeight))
            }
            .stroke(AppColors.secondaryText.opacity(0.45), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))

            Path { path in
                path.move(to: CGPoint(x: 0, y: yCross))
                path.addLine(to: CGPoint(x: plotWidth, y: yCross))
            }
            .stroke(AppColors.secondaryText.opacity(0.45), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))

            Circle()
                .fill(hBar.isUp ? AppColors.candleUp : AppColors.candleDown)
                .frame(width: 5, height: 5)
                .position(x: hX, y: max(2, min(plotHeight - 2, yClose)))

            Text(Formatters.price(Decimal(crossPrice), symbol: symbol))
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(AppColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(AppColors.secondaryText.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .position(x: plotWidth + 28, y: max(8, min(plotHeight - 8, yCross)))

            Text(formatBarTime(hBar.timestamp, bars: bars, timeZone: timeZone, timeframe: timeframe))
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(AppColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(AppColors.secondaryText.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .position(x: max(32, min(plotWidth - 32, hX)), y: plotHeight + 10)
        }
    }

    // MARK: 8. Footprint Key Levels Overlay (TradingView Footprint Alignment)
    @ViewBuilder
    public static func footprintOverlay(
        bars: [MarketBar],
        symbol: String,
        keyLevels: [KeyLevel],
        sessionProfiles: [SessionProfileSnapshot],
        developingProfiles: [DevelopingProfile],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat
    ) -> some View {
        let filteredProfiles = filteredTradingViewProfiles(sessionProfiles)
        ZStack(alignment: .topLeading) {
            ForEach(filteredProfiles, id: \.snap.id) { item in
                sessionProfileSegment(
                    bars: bars,
                    symbol: symbol,
                    snap: item.snap,
                    tag: item.tag,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight,
                    stepX: stepX,
                    minP: minP,
                    span: span,
                    panOffset: panOffset
                )
            }

            ForEach(developingProfiles, id: \.sessionType) { dev in
                developingProfileSegment(
                    bars: bars,
                    symbol: symbol,
                    dev: dev,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight,
                    stepX: stepX,
                    minP: minP,
                    span: span,
                    panOffset: panOffset
                )
            }

            intradayKeyLevels(
                bars: bars,
                keyLevels: keyLevels,
                plotWidth: plotWidth,
                plotHeight: plotHeight,
                stepX: stepX,
                minP: minP,
                span: span,
                panOffset: panOffset
            )
        }
    }

    private static func filteredTradingViewProfiles(
        _ sessionProfiles: [SessionProfileSnapshot]
    ) -> [(snap: SessionProfileSnapshot, tag: String)] {
        let daily = sessionProfiles.filter { $0.sessionType == .daily }.sorted { $0.startTime > $1.startTime }
        let weekly = sessionProfiles.filter { $0.sessionType == .weekly }.sorted { $0.startTime > $1.startTime }
        let tokyo = sessionProfiles.filter { $0.sessionType == .tokyo }.sorted { $0.startTime > $1.startTime }
        let london = sessionProfiles.filter { $0.sessionType == .london }.sorted { $0.startTime > $1.startTime }
        let ny = sessionProfiles.filter { $0.sessionType == .newYork }.sorted { $0.startTime > $1.startTime }

        var list: [(SessionProfileSnapshot, String)] = []
        for (idx, snap) in daily.prefix(3).enumerated() {
            list.append((snap, idx == 0 ? "[D]" : "[D-\(idx)]"))
        }
        for (idx, snap) in weekly.prefix(2).enumerated() {
            list.append((snap, idx == 0 ? "[W]" : "[W-\(idx)]"))
        }
        if let t = tokyo.first { list.append((t, "[TY]")) }
        if let l = london.first { list.append((l, "[LD]")) }
        if let n = ny.first { list.append((n, "[NY]")) }
        return list
    }

    @ViewBuilder
    private static func sessionProfileSegment(
        bars: [MarketBar],
        symbol: String,
        snap: SessionProfileSnapshot,
        tag: String,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat
    ) -> some View {
        let pocD = (snap.pocPrice as NSDecimalNumber).doubleValue
        if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
            let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
            let col = sessionColor(for: snap.sessionType)

            let startIdx = bars.firstIndex(where: { $0.date >= snap.startTime })
            let endIdx = bars.lastIndex(where: { $0.date <= snap.endTime })

            if let sI = startIdx ?? (bars.first.map { snap.endTime >= $0.date ? 0 : nil } ?? nil) {
                let eI = endIdx ?? min(bars.count - 1, sI)
                let x1 = CGFloat(sI) * stepX + (stepX / 2.0) + panOffset
                let x2 = CGFloat(eI) * stepX + (stepX / 2.0) + panOffset
                let segXEnd = max(x1 + stepX, x2)
                let isD1orW1 = snap.sessionType == .daily || snap.sessionType == .weekly
                let lineWidth: CGFloat = isD1orW1 ? 2.0 : 1.2

                let sessionBars = bars.filter { $0.date >= snap.startTime && $0.date <= snap.endTime }
                if sessionBars.count >= 2 {
                    let steps = SessionFootprintEngine.computeStaircaseSteps(bars: sessionBars, symbol: symbol)
                    let staircase = buildStaircasePath(
                        bars: bars,
                        steps: steps,
                        stepX: stepX,
                        panOffset: panOffset,
                        minP: minP,
                        span: span,
                        plotHeight: plotHeight
                    )
                    staircase.stroke(col, lineWidth: lineWidth)
                } else if segXEnd >= 0 && x1 <= plotWidth {
                    Path { path in
                        path.move(to: CGPoint(x: max(0, x1), y: y))
                        path.addLine(to: CGPoint(x: min(plotWidth, segXEnd), y: y))
                    }
                    .stroke(col, lineWidth: lineWidth)
                }

                if snap.isNaked {
                    let rayEndIdx = findRayEndIndex(after: eI, for: snap.pocPrice, in: bars)
                    let rayXEnd = CGFloat(rayEndIdx) * stepX + (stepX / 2.0) + panOffset

                    if rayXEnd > segXEnd && segXEnd <= plotWidth {
                        Path { path in
                            path.move(to: CGPoint(x: max(0, segXEnd), y: y))
                            path.addLine(to: CGPoint(x: min(plotWidth, rayXEnd), y: y))
                        }
                        .stroke(col.opacity(0.65), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))

                        if rayXEnd >= (plotWidth - 20) {
                            Text(tag)
                                .font(AppTypography.captionMicro)
                                .foregroundColor(col)
                                .position(x: plotWidth - 14, y: max(6, min(plotHeight - 6, y - 6)))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private static func developingProfileSegment(
        bars: [MarketBar],
        symbol: String,
        dev: DevelopingProfile,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat
    ) -> some View {
        if let curPoc = dev.currentPoc {
            let pocD = (curPoc as NSDecimalNumber).doubleValue
            if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
                let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
                let col = sessionColor(for: dev.sessionType)

                let sIdx = bars.firstIndex(where: { $0.date >= dev.startTime }) ?? max(0, bars.count - 12)
                let x1 = CGFloat(sIdx) * stepX + (stepX / 2.0) + panOffset
                let x2 = CGFloat(max(0, bars.count - 1)) * stepX + (stepX / 2.0) + panOffset
                let isD1orW1 = dev.sessionType == .daily || dev.sessionType == .weekly
                let lineWidth: CGFloat = isD1orW1 ? 2.0 : 1.4

                if x2 >= 0 && x1 <= plotWidth {
                    let devBars = bars.filter { $0.date >= dev.startTime }
                    if devBars.count >= 2 {
                        let steps = SessionFootprintEngine.computeStaircaseSteps(bars: devBars, symbol: symbol)
                        let staircase = buildStaircasePath(
                            bars: bars,
                            steps: steps,
                            stepX: stepX,
                            panOffset: panOffset,
                            minP: minP,
                            span: span,
                            plotHeight: plotHeight
                        )
                        staircase.stroke(col, lineWidth: lineWidth)
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: max(0, x1), y: y))
                            path.addLine(to: CGPoint(x: min(plotWidth, x2), y: y))
                        }
                        .stroke(col, lineWidth: lineWidth)
                    }

                    if x2 < plotWidth {
                        Path { path in
                            path.move(to: CGPoint(x: x2, y: y))
                            path.addLine(to: CGPoint(x: plotWidth, y: y))
                        }
                        .stroke(col.opacity(0.65), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))
                    }

                    let devTag = dev.sessionType == .daily ? "[D]" : (dev.sessionType == .weekly ? "[W]" : (dev.sessionType == .tokyo ? "[TKY]" : (dev.sessionType == .london ? "[LD]" : "[NY]")))
                    Text(devTag)
                        .font(AppTypography.captionMicro)
                        .foregroundColor(col)
                        .position(x: plotWidth - 14, y: max(6, min(plotHeight - 6, y - 6)))
                }
            }
        }
    }

    @ViewBuilder
    private static func intradayKeyLevels(
        bars: [MarketBar],
        keyLevels: [KeyLevel],
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat
    ) -> some View {
        let intradayLevels = keyLevels.filter { $0.type == .pdh || $0.type == .pdl || $0.type == .pdc }
        if !intradayLevels.isEmpty && !bars.isEmpty {
            let todayStartIdx = findTodayStartIndex(in: bars)
            let x1 = CGFloat(todayStartIdx) * stepX + (stepX / 2.0) + panOffset
            let x2 = CGFloat(bars.count - 1) * stepX + (stepX / 2.0) + panOffset

            ForEach(intradayLevels) { lvl in
                let priceD = (lvl.price as NSDecimalNumber).doubleValue
                if priceD >= minP && priceD <= (minP + span) {
                    let y = plotHeight - CGFloat((priceD - minP) / span) * plotHeight

                    Path { path in
                        path.move(to: CGPoint(x: max(0, x1), y: y))
                        path.addLine(to: CGPoint(x: min(plotWidth, x2), y: y))
                    }
                    .stroke(AppColors.secondaryText.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                }
            }
        }
    }

    private static func buildStaircasePath(
        bars: [MarketBar],
        steps: [(timestamp: Int64, pocPrice: Decimal)],
        stepX: CGFloat,
        panOffset: CGFloat,
        minP: Double,
        span: Double,
        plotHeight: CGFloat
    ) -> Path {
        var path = Path()
        guard !steps.isEmpty else { return path }

        var barIndexMap: [Int64: Int] = [:]
        for (i, b) in bars.enumerated() {
            barIndexMap[b.timestamp] = i
        }

        var lastY: CGFloat? = nil
        var lastRightX: CGFloat? = nil

        for step in steps {
            guard let bIdx = barIndexMap[step.timestamp] else { continue }
            let xCenter = CGFloat(bIdx) * stepX + (stepX / 2.0) + panOffset
            let xLeft = xCenter - (stepX / 2.0)
            let xRight = xCenter + (stepX / 2.0)

            let stepPocD = (step.pocPrice as NSDecimalNumber).doubleValue
            let yStep = plotHeight - CGFloat((stepPocD - minP) / span) * plotHeight

            if let prevY = lastY, let prevRight = lastRightX {
                if abs(xLeft - prevRight) > 2.0 {
                    path.move(to: CGPoint(x: xLeft, y: yStep))
                    path.addLine(to: CGPoint(x: xRight, y: yStep))
                } else {
                    if abs(yStep - prevY) > 0.5 {
                        path.addLine(to: CGPoint(x: prevRight, y: yStep))
                    }
                    path.addLine(to: CGPoint(x: xRight, y: yStep))
                }
            } else {
                path.move(to: CGPoint(x: xLeft, y: yStep))
                path.addLine(to: CGPoint(x: xRight, y: yStep))
            }

            lastY = yStep
            lastRightX = xRight
        }

        return path
    }

    private static func findRayEndIndex(after endIndex: Int, for pocPrice: Decimal, in bars: [MarketBar]) -> Int {
        guard endIndex + 1 < bars.count else { return max(0, bars.count - 1) }
        for k in (endIndex + 1)..<bars.count {
            let b = bars[k]
            if b.low <= pocPrice && b.high >= pocPrice {
                return k
            }
        }
        return max(0, bars.count - 1)
    }

    private static func findTodayStartIndex(in bars: [MarketBar]) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        return bars.firstIndex(where: { cal.isDateInToday($0.date) }) ?? max(0, bars.count - 24)
    }

    public static func sessionColor(for type: FootprintSessionType) -> Color {
        switch type {
        case .tokyo: return AppColors.sessionTokyo
        case .london: return AppColors.sessionLondon
        case .newYork: return AppColors.sessionNewYork
        case .daily: return AppColors.sessionDaily
        case .weekly: return AppColors.sessionWeekly
        case .monthly: return AppColors.sessionMonthly
        }
    }

    // MARK: 9. Cached Bar Time Formatting
    public static func formatBarTime(
        _ timestamp: Int64,
        bars: [MarketBar],
        timeZone: TimeZone = .current,
        timeframe: String? = nil
    ) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        if let tf = timeframe, (tf == "1d" || tf == "D" || tf == "D1") {
            let f = SharedChartDateFormatters.dayFormatter
            if f.timeZone != timeZone { f.timeZone = timeZone }
            return f.string(from: date)
        }
        let spanMs = (bars.last?.timestamp ?? timestamp) - (bars.first?.timestamp ?? timestamp)
        let f: DateFormatter
        if spanMs > 86_400_000 * 2 {
            f = SharedChartDateFormatters.dayFormatter
        } else if spanMs > 86_400_000 {
            f = SharedChartDateFormatters.dayTimeFormatter
        } else {
            f = SharedChartDateFormatters.timeFormatter
        }
        if f.timeZone != timeZone {
            f.timeZone = timeZone
        }
        return f.string(from: date)
    }
}

private enum SharedChartDateFormatters {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()
    static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
