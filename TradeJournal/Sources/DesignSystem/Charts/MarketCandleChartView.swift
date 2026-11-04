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

    @State private var hoveredBarIndex: Int? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0
    @State private var lastDragX: CGFloat = 0.0
    @State private var currentPlotWidth: CGFloat = 320

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
        patterns: [DetectedCandlePattern] = []
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
    }

    public var body: some View {
        VStack(spacing: 4) {
            hudHeaderView

            GeometryReader { geo in
                let pw = max(10, geo.size.width - 55)
                candlestickPlotView(size: geo.size)
                    .onAppear {
                        if currentPlotWidth != pw { currentPlotWidth = pw }
                    }
            }
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastMagnification
                        lastMagnification = value
                        zoomScale = max(0.5, min(4.0, zoomScale * delta))
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let plotW = max(10, currentPlotWidth)
                        let baseCount = max(bars.count, 40)
                        let effectiveZoom = max(0.5, min(4.0, zoomScale))
                        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
                        let stepX = plotW / CGFloat(max(1, slotCount))
                        let totalW = CGFloat(bars.count) * stepX

                        if abs(value.translation.width) > 6 && totalW > plotW {
                            let delta = value.translation.width - lastDragX
                            lastDragX = value.translation.width
                            let minOffset = plotW - totalW
                            panOffset = min(0, max(minOffset, panOffset + delta))
                        } else {
                            updateHoveredBar(at: value.location.x, totalWidth: plotW, stepX: stepX, panOffset: panOffset)
                        }
                    }
                    .onEnded { _ in
                        lastDragX = 0
                        hoveredBarIndex = nil
                        let plotW = max(10, currentPlotWidth)
                        let baseCount = max(bars.count, 40)
                        let effectiveZoom = max(0.5, min(4.0, zoomScale))
                        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
                        let stepX = plotW / CGFloat(max(1, slotCount))
                        let totalW = CGFloat(bars.count) * stepX
                        if totalW > plotW {
                            let minOffset = plotW - totalW
                            panOffset = min(0, max(minOffset, panOffset))
                        } else {
                            panOffset = 0
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(AppAnimations.springStandard) {
                    zoomScale = 1.0
                    panOffset = 0.0
                }
            }
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

            // TradingView OHLC Inspector
            if let hIdx = hoveredBarIndex, hIdx < bars.count {
                let hBar = bars[hIdx]
                HStack(spacing: 5) {
                    Text("O \(formatPrice(hBar.open))")
                        .foregroundColor(AppColors.secondaryText)
                    Text("H \(formatPrice(hBar.high))")
                        .foregroundColor(AppColors.secondaryText)
                    Text("L \(formatPrice(hBar.low))")
                        .foregroundColor(AppColors.secondaryText)
                    Text("C \(formatPrice(hBar.close))")
                        .foregroundColor(hBar.isUp ? AppColors.candleUp : AppColors.candleDown)
                }
                .font(AppTypography.captionMicro)
            } else if let lastBar = bars.last {
                Text(formatPrice(lastBar.close))
                    .font(AppTypography.captionMicro)
                    .foregroundColor(lastBar.isUp ? AppColors.candleUp : AppColors.candleDown)
            }

            Spacer()

            if abs(zoomScale - 1.0) > 0.05 {
                AppBadge(String(format: "%.1fx", zoomScale), style: .brand)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 2. Candlestick Canvas Plot
    private func candlestickPlotView(size: CGSize) -> some View {
        let plotWidth = max(10, size.width - 55)
        let plotHeight = max(10, size.height - 20)

        let baseCount = max(bars.count, 40)
        let effectiveZoom = max(0.5, min(4.0, zoomScale))
        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
        let stepX = plotWidth / CGFloat(max(1, slotCount))
        let candleWidth = max(2.0, min(20.0, stepX * 0.72))

        let totalContentWidth = CGFloat(bars.count) * stepX
        let minPan = min(0, plotWidth - totalContentWidth)
        let clampedPan = totalContentWidth > plotWidth ? min(0, max(minPan, panOffset)) : 0

        let allPrices = bars.flatMap { [($0.high as NSDecimalNumber).doubleValue, ($0.low as NSDecimalNumber).doubleValue] }
        let rawMin = allPrices.min() ?? 1.0
        let rawMax = allPrices.max() ?? 2.0
        let padding = max(0.0001, (rawMax - rawMin) * 0.08)
        let minP = rawMin - padding
        let maxP = rawMax + padding
        let span = max(0.0001, maxP - minP)

        return ZStack(alignment: .topLeading) {
            // Day / Session Vertical Dividers
            daySeparators(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, clampedPan: clampedPan)

            // Price Grid & Right Axis
            gridAndPriceAxis(width: plotWidth, height: plotHeight, minP: minP, maxP: maxP)

            // Volume Histogram (Subtle background)
            volumeHistogram(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, candleWidth: candleWidth, panOffset: clampedPan)

            // TradingView-aligned Footprint POC & Key Levels Overlay (Time-bounded segments + selective rays)
            footprintOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span)

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

                guard xCenter >= -candleWidth && xCenter <= (plotWidth + candleWidth) else { EmptyView() }

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

            // Time Axis
            timeAxis(width: plotWidth, height: plotHeight, stepX: stepX, panOffset: clampedPan)

            // TradingView Live Current Price Line & Badge
            currentPriceLine(plotWidth: plotWidth, plotHeight: plotHeight, minP: minP, span: span)

            // Dual-Axis Crosshair (Vertical + Horizontal + Badges)
            if let hIdx = hoveredBarIndex, hIdx < bars.count {
                crosshairOverlay(hIdx: hIdx, plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span, clampedPan: clampedPan)
            }
        }
    }

    // MARK: - 3. Footprint Key Levels Overlay (TradingView Footprint Alignment)
    @ViewBuilder
    private func footprintOverlay(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double
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
                    span: span
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
                    span: span
                )
            }

            // 3. Standalone Intraday Levels (PDH / PDL for current trading day)
            intradayKeyLevels(
                plotWidth: plotWidth,
                plotHeight: plotHeight,
                stepX: stepX,
                minP: minP,
                span: span
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
        span: Double
    ) -> some View {
        let pocD = (snap.pocPrice as NSDecimalNumber).doubleValue
        if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
            let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
            let col = sessionColor(for: snap.sessionType)

            let startIdx = bars.firstIndex(where: { $0.date >= snap.startTime })
            let endIdx = bars.lastIndex(where: { $0.date <= snap.endTime })

            if let sI = startIdx ?? (bars.first.map { snap.endTime >= $0.date ? 0 : nil } ?? nil) {
                let eI = endIdx ?? min(bars.count - 1, sI)
                let x1 = CGFloat(sI) * stepX + (stepX / 2.0)
                let x2 = CGFloat(eI) * stepX + (stepX / 2.0)
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

                // 2. Untested (Naked) POC Ray
                if snap.isNaked {
                    let rayEndIdx = findRayEndIndex(after: eI, for: snap.pocPrice, in: bars)
                    let rayXEnd = CGFloat(rayEndIdx) * stepX + (stepX / 2.0)

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
    private func developingProfileSegment(
        dev: DevelopingProfile,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double
    ) -> some View {
        if let curPoc = dev.currentPoc {
            let pocD = (curPoc as NSDecimalNumber).doubleValue
            if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
                let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
                let col = sessionColor(for: dev.sessionType)

                let sIdx = bars.firstIndex(where: { $0.date >= dev.startTime }) ?? max(0, bars.count - 12)
                let x1 = CGFloat(sIdx) * stepX + (stepX / 2.0)
                let x2 = CGFloat(max(0, bars.count - 1)) * stepX + (stepX / 2.0)
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
        span: Double
    ) -> some View {
        let intradayLevels = keyLevels.filter { $0.type == .pdh || $0.type == .pdl || $0.type == .pdc }
        if !intradayLevels.isEmpty && !bars.isEmpty {
            let todayStartIdx = findTodayStartIndex(in: bars)
            let x1 = CGFloat(todayStartIdx) * stepX + (stepX / 2.0)
            let x2 = CGFloat(bars.count - 1) * stepX + (stepX / 2.0)

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

    private func buildStaircasePath(
        steps: [(timestamp: Int64, pocPrice: Decimal)],
        stepX: CGFloat,
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
            let xCenter = CGFloat(bIdx) * stepX + (stepX / 2.0)
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
        return ForEach(0...levels, id: \.self) { i in
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
            let y = plotHeight - CGFloat((closeD - minP) / span) * plotHeight

            // 1. Vertical Hairline
            Path { path in
                path.move(to: CGPoint(x: hX, y: 0))
                path.addLine(to: CGPoint(x: hX, y: plotHeight))
            }
            .stroke(AppColors.secondaryText.opacity(0.4), style: StrokeStyle(lineWidth: 1.0, dash: [2, 2]))

            // 2. Horizontal Hairline
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: plotWidth, y: y))
            }
            .stroke(AppColors.secondaryText.opacity(0.4), style: StrokeStyle(lineWidth: 1.0, dash: [2, 2]))

            // 3. Right Axis Price Badge
            Text(formatPrice(hBar.close))
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
                .position(x: plotWidth + 28, y: max(8, min(plotHeight - 8, y)))

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
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone

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
            let baseCount = max(bars.count, 40)
            let effectiveZoom = max(0.5, min(4.0, zoomScale))
            let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
            return totalWidth / CGFloat(max(1, slotCount))
        }()
        let adjustedX = x - panOffset
        let idx = Int(adjustedX / stX)
        if idx >= 0 && idx < bars.count && self.hoveredBarIndex != idx {
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
}
