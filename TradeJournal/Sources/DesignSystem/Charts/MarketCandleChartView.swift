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

    @State private var hoveredBarIndex: Int? = nil
    @State private var hoveredTouchY: CGFloat? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0
    @State private var isManualPriceScale: Bool = false
    @State private var manualCenterPrice: Double = 0.0
    @State private var manualPriceSpan: Double = 0.0
    @State private var currentPlotWidth: CGFloat = 320
    @State private var currentPlotHeight: CGFloat = 220
    @State private var didInitializeViewport: Bool = false

    private var defaultVisibleBars: Int {
        min(max(bars.count, 10), 42)
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
                        currentPlotWidth = pw
                        currentPlotHeight = ph
                        if !didInitializeViewport && !bars.isEmpty {
                            didInitializeViewport = true
                            resetViewport(plotWidth: pw)
                        }
                    }
                    .onChange(of: bars.count) { _ in
                        if !bars.isEmpty {
                            resetViewport(plotWidth: currentPlotWidth)
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
                        handleCanvasPan(dx: dx, dy: dy, totalDx: totalDx, totalDy: totalDy)
                    },
                    onPanEnded: {
                        hoveredBarIndex = nil
                    },
                    onPriceAxisZoom: { dy in
                        handlePriceAxisZoom(dy: dy)
                    },
                    onTimeAxisZoom: { dx in
                        handleTimeAxisZoom(dx: dx)
                    },
                    onPinchZoom: { scaleDelta, focalX in
                        handlePinchZoom(scaleDelta: scaleDelta, focalX: focalX)
                    },
                    onCrosshairChanged: { x in
                        if let locX = x {
                            updateHoveredBar(at: locX, totalWidth: currentPlotWidth, panOffset: panOffset)
                        } else {
                            hoveredBarIndex = nil
                            hoveredTouchY = nil
                        }
                    },
                    onCrosshairPointChanged: { pt in
                        if let pt = pt {
                            hoveredTouchY = max(0, min(currentPlotHeight, pt.y))
                        } else {
                            hoveredTouchY = nil
                        }
                    },
                    onPriceAxisDoubleTap: {
                        withAnimation(AppAnimations.springStandard) {
                            isManualPriceScale = false
                            manualCenterPrice = 0
                            manualPriceSpan = 0
                        }
                    },
                    onDoubleTapReset: {
                        withAnimation(AppAnimations.springStandard) {
                            resetViewport(plotWidth: currentPlotWidth)
                        }
                    }
                )
            )
        }
    }

    // MARK: - 1. HUD Header Bar
    private var hudHeaderView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Symbol & Timeframe Badge
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
        let plotWidth = max(10, size.width - 55)
        let plotHeight = max(10, size.height - 20)

        let baseCount = defaultVisibleBars
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(baseCount) / Double(effectiveZoom))
        let stepX = plotWidth / CGFloat(max(1.0, slotCount))
        let candleWidth = max(2.0, min(22.0, stepX * 0.72))

        let maxRightSpace = max(stepX * 6.0, plotWidth * 0.45)
        let totalContentWidth = CGFloat(bars.count) * stepX + maxRightSpace
        let minPan = min(0, plotWidth - totalContentWidth)
        let maxPan = stepX * 2.0
        let clampedPan = min(maxPan, max(minPan, panOffset))

        // TradingView Auto-Fitting vs Manual Locked Price Scale
        let autoBounds = computeAutoPriceBounds(stepX: stepX, clampedPan: clampedPan, plotWidth: plotWidth)
        let minP: Double
        let maxP: Double
        if isManualPriceScale && manualPriceSpan > 0 {
            minP = manualCenterPrice - (manualPriceSpan / 2.0)
            maxP = manualCenterPrice + (manualPriceSpan / 2.0)
        } else {
            minP = autoBounds.minP
            maxP = autoBounds.maxP
        }
        let span = max(0.0001, maxP - minP)

        return ZStack(alignment: .topLeading) {
            // Day / Session Vertical Dividers
            daySeparators(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, clampedPan: clampedPan)

            // Price Grid & Right Axis
            gridAndPriceAxis(width: plotWidth, height: plotHeight, minP: minP, maxP: maxP)

            // Volume Histogram (Subtle background)
            volumeHistogram(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, candleWidth: candleWidth, panOffset: clampedPan)

            // TradingView-aligned Footprint POC & Key Levels Overlay (Time-bounded segments + selective rays)
            footprintOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span, clampedPan: clampedPan)

            // Candlesticks
            ForEach(0..<bars.count, id: \.self) { i in
                let bar = bars[i]

                // Highlight Price Action pattern by changing candle color directly (InsideBar and Doji excluded)
                let matchedPattern = patterns.first(where: {
                    $0.barTimestamp == bar.timestamp && $0.type != .insideBar && $0.type != .doji
                })
                let isPattern = matchedPattern != nil
                let candleColor: Color = {
                    if let pat = matchedPattern {
                        if pat.type.isBullish {
                            return AppColors.patternBullish
                        } else {
                            return AppColors.patternBearish
                        }
                    }
                    return bar.isUp ? AppColors.candleUp : AppColors.candleDown
                }()

                let highD = (bar.high as NSDecimalNumber).doubleValue
                let lowD = (bar.low as NSDecimalNumber).doubleValue
                let openD = (bar.open as NSDecimalNumber).doubleValue
                let closeD = (bar.close as NSDecimalNumber).doubleValue

                let yHigh = plotHeight - CGFloat((highD - minP) / span) * plotHeight
                let yLow = plotHeight - CGFloat((lowD - minP) / span) * plotHeight
                let yOpen = plotHeight - CGFloat((openD - minP) / span) * plotHeight
                let yClose = plotHeight - CGFloat((closeD - minP) / span) * plotHeight

                let bodyTop = min(yOpen, yClose)
                let bodyHeight = max(1.5, abs(yOpen - yClose))
                let xCenter = CGFloat(i) * stepX + (stepX / 2.0) + clampedPan

                if xCenter >= -candleWidth && xCenter <= (plotWidth + candleWidth) {
                    ZStack {
                        // Wick
                        Rectangle()
                            .fill(candleColor)
                            .frame(width: isPattern ? 1.5 : 1.0, height: max(1, yLow - yHigh))
                            .position(x: xCenter, y: (yHigh + yLow) / 2.0)

                        // Real Body
                        RoundedRectangle(cornerRadius: 1)
                            .fill(candleColor)
                            .frame(width: candleWidth, height: bodyHeight)
                            .position(x: xCenter, y: bodyTop + bodyHeight / 2.0)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1)
                                    .stroke(candleColor.opacity(0.85), lineWidth: isPattern ? 1.0 : 0)
                            )
                    }
                }
            }

            // Time Axis
            timeAxis(width: plotWidth, height: plotHeight, stepX: stepX, panOffset: clampedPan)

            // TradingView Live Current Price Line & Badge
            currentPriceLine(plotWidth: plotWidth, plotHeight: plotHeight, minP: minP, span: span)

            // Dual-Axis Crosshair (Vertical + Horizontal + Badges)
            if let hIdx = hoveredBarIndex, hIdx < bars.count {
                crosshairOverlay(hIdx: hIdx, plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span, clampedPan: clampedPan)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - 3. Footprint Key Levels Overlay (TradingView Footprint Alignment)
    @ViewBuilder
    private func footprintOverlay(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // 1. Time-bounded Historical Session Profiles (Tokyo, London, NY, Daily, Weekly)
            ForEach(filteredTradingViewProfiles, id: \.snap.id) { item in
                sessionProfileSegment(
                    snap: item.snap,
                    tag: item.tag,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight,
                    stepX: stepX,
                    minP: minP,
                    span: span,
                    clampedPan: clampedPan
                )
            }

            // 2. Developing (Live) Ongoing Session & Multi-timeframe Profiles
            ForEach(activeDevelopingProfiles, id: \.sessionType) { dev in
                developingProfileSegment(
                    dev: dev,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight,
                    stepX: stepX,
                    minP: minP,
                    span: span,
                    clampedPan: clampedPan
                )
            }

            // 3. Standalone Intraday Levels (PDH / PDL for current trading day)
            intradayKeyLevels(
                plotWidth: plotWidth,
                plotHeight: plotHeight,
                stepX: stepX,
                minP: minP,
                span: span,
                clampedPan: clampedPan
            )
        }
    }

    private var activeDevelopingProfiles: [DevelopingProfile] {
        !developingProfiles.isEmpty ? developingProfiles : (developingProfile.map { [$0] } ?? [])
    }

    // MARK: - Filtered Profiles with TradingView Naming ([W-1], [D-1], [TY], etc.)
    private var filteredTradingViewProfiles: [(snap: SessionProfileSnapshot, tag: String)] {
        let daily = sessionProfiles.filter { $0.sessionType == .daily }.sorted { $0.startTime > $1.startTime }
        let weekly = sessionProfiles.filter { $0.sessionType == .weekly }.sorted { $0.startTime > $1.startTime }
        let tokyo = sessionProfiles.filter { $0.sessionType == .tokyo }.sorted { $0.startTime > $1.startTime }
        let london = sessionProfiles.filter { $0.sessionType == .london }.sorted { $0.startTime > $1.startTime }
        let ny = sessionProfiles.filter { $0.sessionType == .newYork }.sorted { $0.startTime > $1.startTime }

        var list: [(SessionProfileSnapshot, String)] = []

        // Up to 3 most recent Daily profiles
        for (idx, snap) in daily.prefix(3).enumerated() {
            let tag = idx == 0 ? "[D]" : "[D-\(idx)]"
            list.append((snap, tag))
        }
        // Up to 2 most recent Weekly profiles
        for (idx, snap) in weekly.prefix(2).enumerated() {
            let tag = idx == 0 ? "[W]" : "[W-\(idx)]"
            list.append((snap, tag))
        }
        // Most recent Tokyo session
        if let t = tokyo.first {
            list.append((t, "[TY]"))
        }
        // Most recent London session
        if let l = london.first {
            list.append((l, "[LD]"))
        }
        // Most recent New York session
        if let n = ny.first {
            list.append((n, "[NY]"))
        }

        return list
    }

    @ViewBuilder
    private func sessionProfileSegment(
        snap: SessionProfileSnapshot,
        tag: String,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat
    ) -> some View {
        let pocD = (snap.pocPrice as NSDecimalNumber).doubleValue
        if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
            let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
            let col = sessionColor(for: snap.sessionType)

            let startIdx = bars.firstIndex(where: { $0.date >= snap.startTime })
            let endIdx = bars.lastIndex(where: { $0.date <= snap.endTime })

            if let sI = startIdx ?? (bars.first.map { snap.endTime >= $0.date ? 0 : nil } ?? nil) {
                let eI = endIdx ?? min(bars.count - 1, sI)
                let x1 = CGFloat(sI) * stepX + (stepX / 2.0) + clampedPan
                let x2 = CGFloat(eI) * stepX + (stepX / 2.0) + clampedPan
                let segXEnd = max(x1 + stepX, x2)
                let isD1orW1 = snap.sessionType == .daily || snap.sessionType == .weekly
                let lineWidth: CGFloat = isD1orW1 ? 2.0 : 1.2

                // 1. Session Bounded Staircase POC line (Preserves bar-by-bar progressive step line)
                let sessionBars = bars.filter { $0.date >= snap.startTime && $0.date <= snap.endTime }
                if sessionBars.count >= 2 {
                    let steps = SessionFootprintEngine.computeStaircaseSteps(bars: sessionBars, symbol: symbol)
                    let staircase = buildStaircasePath(
                        steps: steps,
                        stepX: stepX,
                        minP: minP,
                        span: span,
                        plotHeight: plotHeight,
                        panOffset: clampedPan
                    )
                    staircase.stroke(col, lineWidth: lineWidth)
                } else if segXEnd >= 0 && x1 <= plotWidth {
                    Path { path in
                        path.move(to: CGPoint(x: x1, y: y))
                        path.addLine(to: CGPoint(x: segXEnd, y: y))
                    }
                    .stroke(col, lineWidth: lineWidth)
                }

                // 2. Untested (Naked) POC Ray
                if snap.isNaked {
                    let rayEndIdx = findRayEndIndex(after: eI, for: snap.pocPrice, in: bars)
                    let rayXEnd = CGFloat(rayEndIdx) * stepX + (stepX / 2.0) + clampedPan

                    if rayXEnd > segXEnd {
                        Path { path in
                            path.move(to: CGPoint(x: segXEnd, y: y))
                            path.addLine(to: CGPoint(x: rayXEnd, y: y))
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
    private func developingProfileSegment(
        dev: DevelopingProfile,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat
    ) -> some View {
        if let curPoc = dev.currentPoc {
            let pocD = (curPoc as NSDecimalNumber).doubleValue
            if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
                let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
                let col = sessionColor(for: dev.sessionType)

                let sIdx = bars.firstIndex(where: { $0.date >= dev.startTime }) ?? max(0, bars.count - 12)
                let x1 = CGFloat(sIdx) * stepX + (stepX / 2.0) + clampedPan
                let x2 = CGFloat(max(0, bars.count - 1)) * stepX + (stepX / 2.0) + clampedPan
                let isD1orW1 = dev.sessionType == .daily || dev.sessionType == .weekly
                let lineWidth: CGFloat = isD1orW1 ? 2.0 : 1.4

                if x2 >= 0 && x1 <= plotWidth {
                    let devBars = bars.filter { $0.date >= dev.startTime }
                    if devBars.count >= 2 {
                        let steps = SessionFootprintEngine.computeStaircaseSteps(bars: devBars, symbol: symbol)
                        let staircase = buildStaircasePath(
                            steps: steps,
                            stepX: stepX,
                            minP: minP,
                            span: span,
                            plotHeight: plotHeight,
                            panOffset: clampedPan
                        )
                        staircase.stroke(col, lineWidth: lineWidth)
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: x1, y: y))
                            path.addLine(to: CGPoint(x: x2, y: y))
                        }
                        .stroke(col, lineWidth: lineWidth)
                    }

                    // Faint dotted ray to the right edge
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
    private func intradayKeyLevels(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat
    ) -> some View {
        let intradayLevels = keyLevels.filter { $0.type == .pdh || $0.type == .pdl || $0.type == .pdc }
        if !intradayLevels.isEmpty && !bars.isEmpty {
            let todayStartIdx = findTodayStartIndex(in: bars)
            let x1 = CGFloat(todayStartIdx) * stepX + (stepX / 2.0) + clampedPan
            let x2 = CGFloat(bars.count - 1) * stepX + (stepX / 2.0) + clampedPan

            ForEach(intradayLevels) { lvl in
                let priceD = (lvl.price as NSDecimalNumber).doubleValue
                if priceD >= minP && priceD <= (minP + span) {
                    let y = plotHeight - CGFloat((priceD - minP) / span) * plotHeight

                    Path { path in
                        path.move(to: CGPoint(x: x1, y: y))
                        path.addLine(to: CGPoint(x: x2, y: y))
                    }
                    .stroke(AppColors.secondaryText.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                }
            }
        }
    }

    private func buildStaircasePath(
        steps: [(timestamp: Int64, pocPrice: Decimal)],
        stepX: CGFloat,
        minP: Double,
        span: Double,
        plotHeight: CGFloat,
        panOffset: CGFloat = 0.0
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

    private func findRayEndIndex(after endIndex: Int, for pocPrice: Decimal, in barList: [MarketBar]) -> Int {
        guard endIndex + 1 < barList.count else { return max(0, barList.count - 1) }
        for k in (endIndex + 1)..<barList.count {
            let b = barList[k]
            if b.low <= pocPrice && b.high >= pocPrice {
                return k
            }
        }
        return max(0, barList.count - 1)
    }

    private func findTodayStartIndex(in barList: [MarketBar]) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        return barList.firstIndex(where: { cal.isDateInToday($0.date) }) ?? max(0, barList.count - 24)
    }

    private func sessionColor(for type: FootprintSessionType) -> Color {
        switch type {
        case .tokyo: return AppColors.sessionTokyo
        case .london: return AppColors.sessionLondon
        case .newYork: return AppColors.sessionNewYork
        case .daily: return AppColors.sessionDaily
        case .weekly: return AppColors.sessionWeekly
        case .monthly: return AppColors.sessionMonthly
        }
    }

    // MARK: - 5. Grid & Axes
    private func gridAndPriceAxis(width: CGFloat, height: CGFloat, minP: Double, maxP: Double) -> some View {
        let levels = 4
        return ZStack(alignment: .topLeading) {
            // Crisp TradingView Pane Separators (Right Price Axis border + Bottom Time Axis border)
            Path { path in
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height + 20))
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width + 55, y: height))
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

                Text(formatPrice(Decimal(price)))
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .frame(width: 50, alignment: .leading)
                    .position(x: width + 28, y: clampedY)
            }

            // TradingView "A" (Auto Scale) Indicator Pill in bottom-right corner
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
                .position(x: width + 28, y: height + 10)
        }
    }

    private func timeAxis(width: CGFloat, height: CGFloat, stepX: CGFloat, panOffset: CGFloat = 0) -> some View {
        let count = bars.count
        let markInterval = max(1, count / 4)

        return ForEach(0..<count, id: \.self) { i in
            if i % markInterval == 0 || i == count - 1 {
                let x = CGFloat(i) * stepX + (stepX / 2.0) + panOffset
                if x >= 0 && x <= width {
                    let timeStr = formatBarTime(bars[i].timestamp)
                    Text(timeStr)
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                        .position(x: x, y: height + 9)
                }
            }
        }
    }

    // MARK: - 6. Volume Histogram
    private func volumeHistogram(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, candleWidth: CGFloat, panOffset: CGFloat = 0) -> some View {
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

    // MARK: - 6b. TradingView Live Current Price Line & Badge
    @ViewBuilder
    private func currentPriceLine(plotWidth: CGFloat, plotHeight: CGFloat, minP: Double, span: Double) -> some View {
        if let lastBar = bars.last {
            let lastPriceD = (lastBar.close as NSDecimalNumber).doubleValue
            let y = plotHeight - CGFloat((lastPriceD - minP) / span) * plotHeight
            let col = lastBar.isUp ? AppColors.candleUp : AppColors.candleDown

            // 1. Horizontal dashed line across chart
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: plotWidth, y: y))
            }
            .stroke(col.opacity(0.75), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))

            // 2. Right Axis Price Badge (only if crosshair is NOT hovering over a different bar)
            if hoveredBarIndex == nil {
                Text(formatPrice(lastBar.close))
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

    // MARK: - 6c. Dual-Axis Crosshair Overlay (Vertical + Horizontal + Badges)
    @ViewBuilder
    private func crosshairOverlay(
        hIdx: Int,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        clampedPan: CGFloat
    ) -> some View {
        if hIdx < bars.count {
            let hBar = bars[hIdx]
            let hX = CGFloat(hIdx) * stepX + (stepX / 2.0) + clampedPan
            let closeD = (hBar.close as NSDecimalNumber).doubleValue
            let yClose = plotHeight - CGFloat((closeD - minP) / span) * plotHeight
            let yCross = hoveredTouchY ?? max(0, min(plotHeight, yClose))
            let crossPrice = minP + Double((plotHeight - yCross) / max(1, plotHeight)) * span

            // 1. Vertical Hairline
            Path { path in
                path.move(to: CGPoint(x: hX, y: 0))
                path.addLine(to: CGPoint(x: hX, y: plotHeight))
            }
            .stroke(AppColors.secondaryText.opacity(0.45), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))

            // 2. Horizontal Hairline (follows finger Y for exact price reading)
            Path { path in
                path.move(to: CGPoint(x: 0, y: yCross))
                path.addLine(to: CGPoint(x: plotWidth, y: yCross))
            }
            .stroke(AppColors.secondaryText.opacity(0.45), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))

            // Candle Close Anchor Dot
            Circle()
                .fill(hBar.isUp ? AppColors.candleUp : AppColors.candleDown)
                .frame(width: 5, height: 5)
                .position(x: hX, y: max(2, min(plotHeight - 2, yClose)))

            // 3. Right Axis Price Badge
            Text(formatPrice(Decimal(crossPrice)))
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

            // 4. Bottom Time Badge
            Text(formatBarTime(hBar.timestamp))
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

    // MARK: - 6d. TradingView Day / Session Vertical Dividers
    @ViewBuilder
    private func daySeparators(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, clampedPan: CGFloat) -> some View {
        let cal: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = SessionFootprintEngine.sessionTimeZone
            return c
        }()

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

    // MARK: - Helpers
    private func levelColor(for level: KeyLevel) -> Color {
        switch level.type {
        case .sessionPoc(.tokyo):
            return AppColors.sessionTokyo
        case .sessionPoc(.london):
            return AppColors.sessionLondon
        case .sessionPoc(.newYork):
            return AppColors.sessionNewYork
        case .sessionPoc(.daily):
            return AppColors.sessionDaily
        case .sessionPoc(.weekly):
            return AppColors.sessionWeekly
        case .nakedPoc:
            return AppColors.sessionNaked
        case .pdh, .pdl, .pdc:
            return AppColors.primaryText.opacity(0.6)
        default:
            return AppColors.secondaryText
        }
    }

    private func updateHoveredBar(at x: CGFloat, totalWidth: CGFloat, stepX: CGFloat? = nil, panOffset: CGFloat = 0) {
        guard !bars.isEmpty, totalWidth > 0 else { return }
        let stX: CGFloat = {
            if let s = stepX, s > 0 { return s }
            let baseCount = defaultVisibleBars
            let effectiveZoom = max(0.25, min(6.0, zoomScale))
            let slotCount = max(6.0, Double(baseCount) / Double(effectiveZoom))
            return totalWidth / CGFloat(max(1.0, slotCount))
        }()
        let adjustedX = x - panOffset
        let idx = max(0, min(bars.count - 1, Int(adjustedX / stX)))
        if self.hoveredBarIndex != idx {
            self.hoveredBarIndex = idx
            NativeHaptics.selection()
        }
    }

    private func formatPrice(_ p: Decimal) -> String {
        let d = (p as NSDecimalNumber).doubleValue
        if d >= 100 { return String(format: "%.2f", d) }
        if d >= 10 { return String(format: "%.3f", d) }
        return String(format: "%.5f", d)
    }

    private func formatBarTime(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        if timeframe == "1d" || timeframe == "D" || timeframe == "D1" {
            formatter.dateFormat = "MM/dd"
        } else {
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }

    // MARK: - Unified TradingView Viewport & Gesture Handlers
    private func resetViewport(plotWidth: CGFloat) {
        let pw = max(10, plotWidth)
        zoomScale = 1.0
        isManualPriceScale = false
        manualCenterPrice = 0
        manualPriceSpan = 0
        hoveredBarIndex = nil
        let baseCount = defaultVisibleBars
        let stepX = pw / CGFloat(max(1, baseCount))
        let defaultRightMargin = stepX * 5.0
        let totalW = CGFloat(bars.count) * stepX + defaultRightMargin
        panOffset = min(0, pw - totalW)
    }

    private func computeAutoPriceBounds(stepX: CGFloat, clampedPan: CGFloat, plotWidth: CGFloat) -> (minP: Double, maxP: Double) {
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

    private func ensureManualPriceScaleInitialized(stepX: CGFloat, plotWidth: CGFloat) {
        guard !isManualPriceScale || manualPriceSpan <= 0 else { return }
        let maxRightSpace = max(stepX * 6.0, plotWidth * 0.45)
        let totalContentWidth = CGFloat(bars.count) * stepX + maxRightSpace
        let minPan = min(0, plotWidth - totalContentWidth)
        let maxPan = stepX * 2.0
        let clampedPan = min(maxPan, max(minPan, panOffset))
        let auto = computeAutoPriceBounds(stepX: stepX, clampedPan: clampedPan, plotWidth: plotWidth)
        manualCenterPrice = (auto.minP + auto.maxP) / 2.0
        manualPriceSpan = max(0.0001, auto.maxP - auto.minP)
        isManualPriceScale = true
    }

    private func handleCanvasPan(dx: CGFloat, dy: CGFloat, totalDx: CGFloat, totalDy: CGFloat) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let plotH = max(10, currentPlotHeight)
        let baseCount = defaultVisibleBars
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(baseCount) / Double(effectiveZoom))
        let stepX = plotW / CGFloat(max(1.0, slotCount))

        let maxRightSpace = max(stepX * 6.0, plotW * 0.45)
        let totalW = CGFloat(bars.count) * stepX + maxRightSpace
        let minOffset = min(0, plotW - totalW)
        let maxOffset = stepX * 2.0
        panOffset = min(maxOffset, max(minOffset, panOffset + dx))

        // Engage 2D vertical panning when already in manual price scale mode or when the user drags vertically
        if !isManualPriceScale && abs(totalDy) > 10 && abs(totalDy) > abs(totalDx) * 1.1 {
            ensureManualPriceScaleInitialized(stepX: stepX, plotWidth: plotW)
        }
        if isManualPriceScale && manualPriceSpan > 0 {
            let priceShift = (Double(dy) / Double(plotH)) * manualPriceSpan
            manualCenterPrice += priceShift
        }
    }

    private func handlePriceAxisZoom(dy: CGFloat) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let plotH = max(10, currentPlotHeight)
        let baseCount = defaultVisibleBars
        let effectiveZoom = max(0.25, min(6.0, zoomScale))
        let slotCount = max(6.0, Double(baseCount) / Double(effectiveZoom))
        let stepX = plotW / CGFloat(max(1.0, slotCount))

        ensureManualPriceScaleInitialized(stepX: stepX, plotWidth: plotW)
        let scaleChange = max(0.85, min(1.18, 1.0 + Double(dy / max(80, plotH)) * 1.8))
        manualPriceSpan = max(0.0001, manualPriceSpan * scaleChange)
    }

    private func handleTimeAxisZoom(dx: CGFloat) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let scaleDelta = max(0.85, min(1.18, 1.0 + (dx / max(90, plotW)) * 1.8))
        let baseCount = defaultVisibleBars
        let oldSlotCount = max(6.0, Double(baseCount) / Double(zoomScale))
        let oldStepX = plotW / CGFloat(max(1.0, oldSlotCount))
        let anchorX = max(plotW * 0.5, min(plotW, plotW - oldStepX * 5.0))
        applyHorizontalZoom(scaleDelta: scaleDelta, anchorX: anchorX)
    }

    private func handlePinchZoom(scaleDelta: CGFloat, focalX: CGFloat) {
        guard !bars.isEmpty else { return }
        let plotW = max(10, currentPlotWidth)
        let anchorX = max(0, min(plotW, focalX))
        applyHorizontalZoom(scaleDelta: scaleDelta, anchorX: anchorX)
    }

    private func applyHorizontalZoom(scaleDelta: CGFloat, anchorX: CGFloat) {
        let plotW = max(10, currentPlotWidth)
        let baseCount = defaultVisibleBars
        let oldZoom = zoomScale
        let newZoom = max(0.25, min(6.0, oldZoom * scaleDelta))
        guard abs(newZoom - oldZoom) > 0.0001 else { return }

        let oldSlotCount = max(6.0, Double(baseCount) / Double(oldZoom))
        let oldStepX = plotW / CGFloat(max(1.0, oldSlotCount))
        let barPosAtAnchor = (anchorX - panOffset) / oldStepX

        zoomScale = newZoom

        let newSlotCount = max(6.0, Double(baseCount) / Double(newZoom))
        let newStepX = plotW / CGFloat(max(1.0, newSlotCount))
        let maxRightSpace = max(newStepX * 6.0, plotW * 0.45)
        let newTotalW = CGFloat(bars.count) * newStepX + maxRightSpace
        let newMinOffset = min(0, plotW - newTotalW)
        let newMaxOffset = newStepX * 2.0

        let rawNewPan = anchorX - (barPosAtAnchor * newStepX)
        panOffset = min(newMaxOffset, max(newMinOffset, rawNewPan))
    }
}
