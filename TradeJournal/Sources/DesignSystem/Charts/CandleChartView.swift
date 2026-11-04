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
    @State private var activeRSIMAType: MomentumEngine.RSIMAType

    @State private var hoveredBarIndex: Int? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0
    @State private var panOffsetY: CGFloat = 0.0
    @State private var lastDragX: CGFloat = 0.0
    @State private var lastDragY: CGFloat = 0.0
    @State private var priceScaleMultiplier: CGFloat = 1.0
    @State private var lastPriceDragY: CGFloat = 0.0
    @State private var lastTimeDragX: CGFloat = 0.0
    @State private var currentPlotWidth: CGFloat = 320

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
        onResolutionChange: ((MarketResolution) -> Void)? = nil
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
        self._activeRSIMAType = State(initialValue: rsiMAType)
    }

    private var activeFills: [Execution] {
        executions.filter { Int64($0.executedAt.timeIntervalSince1970 * 1000) <= throughTimestamp }
    }

    public var body: some View {
        VStack(spacing: 4) {
            // HUD Information Bar: Sleek, Minimalist (No OHLC, No numeric EMA values, Minimal Legends)
            if !isLandscape {
                hudHeaderView
            }

            // Unified Canvas Card: Candlesticks + optional RSI Sub-Window
            VStack(spacing: 0) {
                // 1. Candlestick Canvas drawing
                if isLandscape {
                    GeometryReader { geo in
                        candlestickPlotView(size: geo.size)
                            .onAppear {
                                let plotW = max(10, geo.size.width - 55)
                                currentPlotWidth = plotW
                                let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                                let stepX = plotW / CGFloat(max(1, baseCount))
                                let rightMargin = stepX * 5.0
                                let totalW = CGFloat(visibleBars.count) * stepX + rightMargin
                                if totalW > plotW && panOffset == 0 {
                                    panOffset = plotW - totalW
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                } else {
                    GeometryReader { geo in
                        candlestickPlotView(size: geo.size)
                            .onAppear {
                                let plotW = max(10, geo.size.width - 55)
                                currentPlotWidth = plotW
                                let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                                let stepX = plotW / CGFloat(max(1, baseCount))
                                let rightMargin = stepX * 5.0
                                let totalW = CGFloat(visibleBars.count) * stepX + rightMargin
                                if totalW > plotW && panOffset == 0 {
                                    panOffset = plotW - totalW
                                }
                            }
                    }
                    .frame(height: showRSI ? 220 : 260)
                    .clipped()
                }

                // 2. RSI Sub-Window (Underneath)
                if showRSI {
                    Divider()
                        .background(AppColors.border.opacity(0.4))

                    GeometryReader { geo in
                        let rightAxisWidth: CGFloat = 55
                        let plotWidth = max(10, geo.size.width - rightAxisWidth)
                        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                        let effectiveZoom = max(0.5, min(4.0, zoomScale))
                        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
                        let stepX = plotWidth / CGFloat(max(1, slotCount))
                        let rightMargin = stepX * 5.0
                        let totalW = CGFloat(visibleBars.count) * stepX + rightMargin
                        let minPan = min(0, plotWidth - totalW)
                        let clampedPan = totalW > plotWidth ? min(0, max(minPan, panOffset)) : 0

                        rsiPlotView(size: geo.size, stepX: stepX, panOffset: clampedPan)
                    }
                    .frame(height: isLandscape ? 85 : 110)
                    .clipped()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastMagnification
                        lastMagnification = value
                        let oldZoom = zoomScale
                        let newZoom = max(0.5, min(4.0, oldZoom * delta))
                        zoomScale = newZoom

                        // Maintain viewport anchor during pinch zoom
                        let plotW = max(10, currentPlotWidth)
                        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                        let oldSlotCount = max(8, Double(baseCount) / Double(oldZoom))
                        let oldStepX = plotW / CGFloat(max(1, oldSlotCount))
                        let oldRightMargin = oldStepX * 5.0
                        let oldTotalW = CGFloat(visibleBars.count) * oldStepX + oldRightMargin
                        let oldMinOffset = min(0, plotW - oldTotalW)

                        let newSlotCount = max(8, Double(baseCount) / Double(newZoom))
                        let newStepX = plotW / CGFloat(max(1, newSlotCount))
                        let newRightMargin = newStepX * 5.0
                        let newTotalW = CGFloat(visibleBars.count) * newStepX + newRightMargin
                        let newMinOffset = min(0, plotW - newTotalW)

                        if oldMinOffset < 0 && newMinOffset < 0 {
                            let progress = panOffset / oldMinOffset
                            panOffset = min(0, max(newMinOffset, progress * newMinOffset))
                        }
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let plotW = max(10, currentPlotWidth)
                        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                        let effectiveZoom = max(0.5, min(4.0, zoomScale))
                        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
                        let stepX = plotW / CGFloat(max(1, slotCount))
                        let rightMargin = stepX * 5.0
                        let totalW = CGFloat(visibleBars.count) * stepX + rightMargin

                        let dx = value.translation.width - lastDragX
                        let dy = value.translation.height - lastDragY
                        lastDragX = value.translation.width
                        lastDragY = value.translation.height

                        // Smooth zero-deadzone horizontal time panning
                        if totalW > plotW {
                            let minOffset = plotW - totalW
                            panOffset = min(0, max(minOffset, panOffset + dx))
                        }

                        // Smooth 1-finger vertical price panning
                        panOffsetY += dy
                    }
                    .onEnded { _ in
                        lastDragX = 0
                        lastDragY = 0
                        hoveredBarIndex = nil
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.2)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if let loc = drag?.location {
                                updateHoveredBar(at: loc.x, totalWidth: currentPlotWidth, panOffset: panOffset)
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        hoveredBarIndex = nil
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(AppAnimations.springStandard) {
                    zoomScale = 1.0
                    panOffsetY = 0.0
                    priceScaleMultiplier = 1.0
                    let plotW = max(10, currentPlotWidth)
                    let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                    let stepX = plotW / CGFloat(max(1, baseCount))
                    let rightMargin = stepX * 5.0
                    let totalW = CGFloat(visibleBars.count) * stepX + rightMargin
                    panOffset = min(0, plotW - totalW)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Candlestick chart for \(trade.symbol), \(visibleBars.count) bars visible.")
        }
    }

    // MARK: - 1. HUD Header Bar (Sleek, Minimalist, Pre-Trade Aligned)

    private var activeHoveredBar: MarketBar? {
        guard let idx = hoveredBarIndex, idx >= 0, idx < visibleBars.count else {
            return visibleBars.last
        }
        return visibleBars[idx]
    }

    private var activeHoveredIndex: Int? {
        if let idx = hoveredBarIndex, idx >= 0, idx < visibleBars.count {
            return idx
        }
        return visibleBars.isEmpty ? nil : (visibleBars.count - 1)
    }

    private var hudHeaderView: some View {
        HStack(alignment: .center, spacing: 8) {
            // 1. Symbol
            Text(trade.symbol)
                .font(AppTypography.actionButtonCompact)
                .foregroundColor(AppColors.primaryText)

            Spacer()

            // Timeframe Resolution Selector Tabs: 15m, 1h, 4h
            if onResolutionChange != nil {
                AppSegmentedBar(
                    selection: Binding(
                        get: { resolution },
                        set: { onResolutionChange?($0) }
                    ),
                    items: [MarketResolution.m15, .h1, .h4],
                    titleFor: { res in
                        switch res {
                        case .m15: return "15m"
                        case .h1: return "1h"
                        case .h4: return "4h"
                        default: return res.rawValue.uppercased()
                        }
                    },
                    height: 28
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 2. Candlestick Main Plot

    private func candlestickPlotView(size: CGSize) -> some View {
        let rightAxisWidth: CGFloat = 55
        let bottomAxisHeight: CGFloat = showRSI ? 0 : 20
        let plotWidth = max(10, size.width - rightAxisWidth)
        let plotHeight = max(10, size.height - bottomAxisHeight)

        // Base slot count scaled by pinch zoom:
        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
        let effectiveZoom = max(0.5, min(4.0, zoomScale))
        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
        let stepX = plotWidth / CGFloat(max(1, slotCount))
        let candleWidth = max(2.5, min(24.0, stepX * 0.7))

        let rightMarginBars: CGFloat = 5.0
        let rightMarginWidth = stepX * rightMarginBars
        let totalContentWidth = CGFloat(visibleBars.count) * stepX + rightMarginWidth
        let minPan = min(0, plotWidth - totalContentWidth)
        let clampedPan = totalContentWidth > plotWidth ? min(0, max(minPan, panOffset)) : 0

        // TradingView Dynamic Viewport Auto-Scaling with 2D Pan and Price Scale Multiplier
        let bounds = calculateViewportPriceBounds(stepX: stepX, clampedPan: clampedPan, plotWidth: plotWidth)
        let rawPriceSpan = max(0.00001, (bounds.maxPrice - bounds.minPrice) * Double(priceScaleMultiplier))
        let centerPrice = (bounds.minPrice + bounds.maxPrice) / 2.0
        let yPriceShift = (Double(panOffsetY) / Double(plotHeight)) * rawPriceSpan
        let shiftedCenter = centerPrice + yPriceShift
        let minP = shiftedCenter - (rawPriceSpan / 2.0)
        let maxP = shiftedCenter + (rawPriceSpan / 2.0)
        let priceSpan = max(0.00001, maxP - minP)

        return ZStack(alignment: .topLeading) {
            // Grid lines and right price axis
            gridAndPriceAxis(width: plotWidth, height: plotHeight, minP: minP, maxP: maxP, fullWidth: size.width)

            // Dedicated right Price Axis touch target for vertical price scale zoom
            Color.clear
                .frame(width: rightAxisWidth, height: plotHeight)
                .contentShape(Rectangle())
                .position(x: plotWidth + (rightAxisWidth / 2.0), y: plotHeight / 2.0)
                .gesture(priceAxisDragGesture(plotHeight: plotHeight))

            // Time axis (bottom) - only shown on candlestick canvas if RSI sub-window is hidden
            if !showRSI {
                timeAxis(width: plotWidth, height: plotHeight, stepX: stepX, fullHeight: size.height, panOffset: clampedPan)

                // Dedicated bottom Time Axis touch target for horizontal zoom
                Color.clear
                    .frame(width: plotWidth, height: 20)
                    .contentShape(Rectangle())
                    .position(x: plotWidth / 2.0, y: plotHeight + 10)
                    .gesture(timeAxisDragGesture(plotWidth: plotWidth))
            }

            volumeHistogram(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, candleWidth: candleWidth, panOffset: clampedPan)

            // Render candlesticks (Wick + Body)
            Canvas { context, _ in
                for (i, bar) in visibleBars.enumerated() {
                    let centerX = CGFloat(i) * stepX + (stepX / 2.0) + clampedPan
                    guard centerX >= -candleWidth && centerX <= (plotWidth + candleWidth) else { continue }

                    let highD = (bar.high as NSDecimalNumber).doubleValue
                    let lowD = (bar.low as NSDecimalNumber).doubleValue
                    let openD = (bar.open as NSDecimalNumber).doubleValue
                    let closeD = (bar.close as NSDecimalNumber).doubleValue

                    let yHigh = plotHeight - CGFloat((highD - minP) / priceSpan) * plotHeight
                    let yLow = plotHeight - CGFloat((lowD - minP) / priceSpan) * plotHeight
                    let yOpen = plotHeight - CGFloat((openD - minP) / priceSpan) * plotHeight
                    let yClose = plotHeight - CGFloat((closeD - minP) / priceSpan) * plotHeight

                    // Highlight Price Action pattern by changing candle color directly (InsideBar and Doji excluded)
                    let matchedPattern = patterns.first(where: {
                        $0.barTimestamp == bar.timestamp && $0.type != .insideBar && $0.type != .doji
                    })
                    let candleColor: Color
                    let isPattern = matchedPattern != nil
                    if let pat = matchedPattern {
                        if pat.type.isBullish {
                            candleColor = AppColors.patternBullish
                        } else {
                            candleColor = AppColors.patternBearish
                        }
                    } else {
                        candleColor = bar.isUp ? AppColors.candleUp : AppColors.candleDown
                    }

                    var wickPath = Path()
                    wickPath.move(to: CGPoint(x: centerX, y: yHigh))
                    wickPath.addLine(to: CGPoint(x: centerX, y: yLow))
                    context.stroke(wickPath, with: .color(candleColor), lineWidth: isPattern ? 1.5 : 1.0)

                    let bodyTop = min(yOpen, yClose)
                    let bodyHeight = max(1.5, abs(yClose - yOpen))
                    let bodyRect = CGRect(
                        x: centerX - (candleWidth / 2.0),
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

            // TradingView Day / Session Vertical Dividers
            daySeparators(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, clampedPan: clampedPan)

            // TradingView-aligned Footprint POC & Key Levels Overlay (Time-bounded segments + selective rays)
            footprintOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan, panOffset: clampedPan)

            // Unified trade overlay (entry/exit lines, arrows, connecting line)
            tradeOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan, panOffset: clampedPan)

            // TradingView Current Live Price Line & Price Badge
            currentPriceLine(plotWidth: plotWidth, plotHeight: plotHeight, minP: minP, span: priceSpan)

            // Full Dual-Axis Crosshair (Vertical + Horizontal + Time/Price Badges)
            if let hIdx = hoveredBarIndex, hIdx < visibleBars.count {
                crosshairOverlay(hIdx: hIdx, plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan, clampedPan: clampedPan)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Footprint Key Levels Overlay (TradingView Footprint Alignment)
    @ViewBuilder
    private func footprintOverlay(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat
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
                    panOffset: panOffset
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
                    panOffset: panOffset
                )
            }

            // 3. Standalone Intraday Levels (PDH / PDL for current trading day)
            intradayKeyLevels(
                plotWidth: plotWidth,
                plotHeight: plotHeight,
                stepX: stepX,
                minP: minP,
                span: span,
                panOffset: panOffset
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
        panOffset: CGFloat
    ) -> some View {
        let pocD = (snap.pocPrice as NSDecimalNumber).doubleValue
        if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
            let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
            let col = sessionColor(for: snap.sessionType)

            // Find bar indices that correspond to this session
            let startIdx = visibleBars.firstIndex(where: { $0.date >= snap.startTime })
            let endIdx = visibleBars.lastIndex(where: { $0.date <= snap.endTime })

            if let sI = startIdx ?? (visibleBars.first.map { snap.endTime >= $0.date ? 0 : nil } ?? nil) {
                let eI = endIdx ?? min(visibleBars.count - 1, sI)
                let x1 = CGFloat(sI) * stepX + (stepX / 2.0) + panOffset
                let x2 = CGFloat(eI) * stepX + (stepX / 2.0) + panOffset
                let segXEnd = max(x1 + stepX, x2)
                let isD1orW1 = snap.sessionType == .daily || snap.sessionType == .weekly
                let lineWidth: CGFloat = isD1orW1 ? 2.0 : 1.2

                // 1. Session Bounded Staircase POC line (Preserves bar-by-bar progressive step line)
                let sessionBars = visibleBars.filter { $0.date >= snap.startTime && $0.date <= snap.endTime }
                if sessionBars.count >= 2 {
                    let steps = SessionFootprintEngine.computeStaircaseSteps(bars: sessionBars, symbol: trade.symbol)
                    let staircase = buildStaircasePath(
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

                // 2. Untested (Naked) POC Ray: Faint dotted line extending to the right with TradingView tag
                if snap.isNaked {
                    let rayEndIdx = findRayEndIndex(after: eI, for: snap.pocPrice, in: visibleBars)
                    let rayXEnd = CGFloat(rayEndIdx) * stepX + (stepX / 2.0) + panOffset

                    if rayXEnd > segXEnd && segXEnd <= plotWidth {
                        Path { path in
                            path.move(to: CGPoint(x: max(0, segXEnd), y: y))
                            path.addLine(to: CGPoint(x: min(plotWidth, rayXEnd), y: y))
                        }
                        .stroke(col.opacity(0.65), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))

                        // Sleek bracket tag at right edge matching TradingView ([W-1], [D-1], [TY], etc.)
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
        panOffset: CGFloat
    ) -> some View {
        if let curPoc = dev.currentPoc {
            let pocD = (curPoc as NSDecimalNumber).doubleValue
            if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
                let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
                let col = sessionColor(for: dev.sessionType)

                let sIdx = visibleBars.firstIndex(where: { $0.date >= dev.startTime }) ?? max(0, visibleBars.count - 12)
                let x1 = CGFloat(sIdx) * stepX + (stepX / 2.0) + panOffset
                let x2 = CGFloat(max(0, visibleBars.count - 1)) * stepX + (stepX / 2.0) + panOffset
                let isD1orW1 = dev.sessionType == .daily || dev.sessionType == .weekly
                let lineWidth: CGFloat = isD1orW1 ? 2.0 : 1.4

                if x2 >= 0 && x1 <= plotWidth {
                    let devBars = visibleBars.filter { $0.date >= dev.startTime }
                    if devBars.count >= 2 {
                        let steps = SessionFootprintEngine.computeStaircaseSteps(bars: devBars, symbol: trade.symbol)
                        let staircase = buildStaircasePath(
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
        panOffset: CGFloat
    ) -> some View {
        let intradayLevels = keyLevels.filter { $0.type == .pdh || $0.type == .pdl || $0.type == .pdc }
        if !intradayLevels.isEmpty && !visibleBars.isEmpty {
            let todayStartIdx = findTodayStartIndex(in: visibleBars)
            let x1 = CGFloat(todayStartIdx) * stepX + (stepX / 2.0) + panOffset
            let x2 = CGFloat(visibleBars.count - 1) * stepX + (stepX / 2.0) + panOffset

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
        panOffset: CGFloat,
        minP: Double,
        span: Double,
        plotHeight: CGFloat
    ) -> Path {
        var path = Path()
        guard !steps.isEmpty else { return path }

        var barIndexMap: [Int64: Int] = [:]
        for (i, b) in visibleBars.enumerated() {
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

    private func findRayEndIndex(after endIndex: Int, for pocPrice: Decimal, in bars: [MarketBar]) -> Int {
        guard endIndex + 1 < bars.count else { return max(0, bars.count - 1) }
        for k in (endIndex + 1)..<bars.count {
            let b = bars[k]
            if b.low <= pocPrice && b.high >= pocPrice {
                return k
            }
        }
        return max(0, bars.count - 1)
    }

    private func findTodayStartIndex(in bars: [MarketBar]) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SessionFootprintEngine.sessionTimeZone
        return bars.firstIndex(where: { cal.isDateInToday($0.date) }) ?? max(0, bars.count - 24)
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

    // MARK: - 3. Grid & Axes

    private func gridAndPriceAxis(width: CGFloat, height: CGFloat, minP: Double, maxP: Double, fullWidth: CGFloat) -> some View {
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

            Text(Formatters.price(Decimal(price), symbol: trade.symbol))
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.secondaryText.opacity(0.8))
                .frame(width: 50, alignment: .leading)
                .position(x: width + 28, y: clampedY)
        }
    }

    private func timeAxis(width: CGFloat, height: CGFloat, stepX: CGFloat, fullHeight: CGFloat, panOffset: CGFloat = 0) -> some View {
        let count = visibleBars.count
        let markInterval = max(1, count / 4)

        return ForEach(0..<count, id: \.self) { i in
            if i % markInterval == 0 || i == count - 1 {
                let x = CGFloat(i) * stepX + (stepX / 2.0) + panOffset
                if x >= 0 && x <= width {
                    let timeStr = formatBarTime(visibleBars[i].timestamp)
                    Text(timeStr)
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                        .position(x: x, y: height + 10)
                }
            }
        }
    }

    // MARK: - 4. Volume Histogram

    private func volumeHistogram(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, candleWidth: CGFloat, panOffset: CGFloat = 0) -> some View {
        let maxVol = visibleBars.map { ($0.volume as NSDecimalNumber).doubleValue }.max() ?? 1.0
        let safeMaxVol = max(1.0, maxVol)
        let volAreaHeight = plotHeight * 0.16

        return ForEach(0..<visibleBars.count, id: \.self) { i in
            let bar = visibleBars[i]
            let v = (bar.volume as NSDecimalNumber).doubleValue
            let barH = CGFloat(v / safeMaxVol) * volAreaHeight
            let x = CGFloat(i) * stepX + (stepX / 2.0) + panOffset
            if x >= -candleWidth && x <= (plotWidth + candleWidth) {
                let y = plotHeight - barH
                Rectangle()
                    .fill((bar.isUp ? AppColors.candleUp : AppColors.candleDown).opacity(0.22))
                    .frame(width: max(1.5, candleWidth * 0.75), height: barH)
                    .position(x: x, y: y + barH / 2.0)
            }
        }
    }

    // MARK: - 4b. TradingView Live Current Price Line & Badge

    @ViewBuilder
    private func currentPriceLine(plotWidth: CGFloat, plotHeight: CGFloat, minP: Double, span: Double) -> some View {
        if let lastBar = visibleBars.last {
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
                Text(Formatters.price(lastBar.close, symbol: trade.symbol))
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

    // MARK: - 4c. Dual-Axis Crosshair Overlay (Vertical + Horizontal + Badges)

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
        if hIdx < visibleBars.count {
            let hBar = visibleBars[hIdx]
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
            Text(Formatters.price(hBar.close, symbol: trade.symbol))
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

    // MARK: - 4d. TradingView Day / Session Vertical Dividers

    @ViewBuilder
    private func daySeparators(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, clampedPan: CGFloat) -> some View {
        let cal: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = SessionFootprintEngine.sessionTimeZone
            return c
        }()

        ForEach(1..<visibleBars.count, id: \.self) { i in
            let curr = visibleBars[i]
            let prev = visibleBars[i - 1]
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

    // MARK: - 5. Unified Trade Overlay (Entry/Exit Lines, Fill Markers, Connecting Line)

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
            // 1. Entry horizontal dashed reference line (always visible)
            Path { path in
                path.move(to: CGPoint(x: 0, y: yEntry))
                path.addLine(to: CGPoint(x: plotWidth, y: yEntry))
            }
            .stroke(AppColors.accent.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // 2. Entry marker & label: "EN"
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

            // 3. Exit line + label: "EX" + connecting line
            if let exitIdx = exitBarIdx, trade.status != .open {
                let exitD = ((trade.avgExit ?? trade.avgEntry) as NSDecimalNumber).doubleValue
                let yExit = plotHeight - CGFloat((exitD - minP) / span) * plotHeight
                let exitX = CGFloat(exitIdx) * stepX + (stepX / 2.0) + panOffset
                let exitColor = AppColors.loss

                // Exit horizontal dashed line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yExit))
                    path.addLine(to: CGPoint(x: plotWidth, y: yExit))
                }
                .stroke(exitColor.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Connecting line from Entry to Exit
                if let entryIdx = entryBarIdx {
                    let entryX = CGFloat(entryIdx) * stepX + (stepX / 2.0) + panOffset
                    Path { path in
                        path.move(to: CGPoint(x: entryX, y: yEntry))
                        path.addLine(to: CGPoint(x: exitX, y: yExit))
                    }
                    .stroke(exitColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }

                // Exit badge: "EX"
                Text("EX")
                    .font(AppTypography.badgeMarker)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(exitColor)
                    .foregroundColor(.white)
                    .cornerRadius(3)
                    .position(x: min(plotWidth - 20, max(20, exitX)), y: max(8, yExit - 10))

                // Exit arrow marker
                Image(systemName: trade.direction == .long ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    .font(AppTypography.badgeMarker)
                    .foregroundColor(exitColor)
                    .position(x: exitX, y: trade.direction == .long ? yExit - 8 : yExit + 8)
            } else if let entryIdx = entryBarIdx, let curBar = visibleBars.last {
                // 4. In-progress trade tracking line: tracks current bar during replay or for open trades
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

    // MARK: - Helpers

    private func calculateViewportPriceBounds(stepX: CGFloat, clampedPan: CGFloat, plotWidth: CGFloat) -> (minPrice: Double, maxPrice: Double) {
        guard !visibleBars.isEmpty, stepX > 0 else { return (1.0, 2.0) }
        let leftX = -clampedPan
        let rightX = leftX + plotWidth
        let startIdx = max(0, min(visibleBars.count - 1, Int(floor(leftX / stepX))))
        let endIdx = max(0, min(visibleBars.count - 1, Int(ceil(rightX / stepX))))

        let slice = visibleBars[startIdx...endIdx]
        let lows = slice.map { ($0.low as NSDecimalNumber).doubleValue }
        let highs = slice.map { ($0.high as NSDecimalNumber).doubleValue }

        let minVal = lows.min() ?? 1.0
        let maxVal = highs.max() ?? 2.0
        let rawSpan = max(0.0001, maxVal - minVal)
        let pad = rawSpan * 0.10
        return (minPrice: minVal - pad, maxPrice: maxVal + pad)
    }

    private func updateHoveredBar(at x: CGFloat, totalWidth: CGFloat, stepX: CGFloat? = nil, panOffset: CGFloat = 0) {
        guard !visibleBars.isEmpty, totalWidth > 0 else { return }
        let stX: CGFloat = {
            if let s = stepX, s > 0 { return s }
            let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
            let effectiveZoom = max(0.5, min(4.0, zoomScale))
            let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
            return totalWidth / CGFloat(max(1, slotCount))
        }()
        let adjustedX = x - panOffset
        let index = Int(adjustedX / stX)
        if index >= 0 && index < visibleBars.count && self.hoveredBarIndex != index {
            self.hoveredBarIndex = index
            NativeHaptics.selection()
        }
    }

    private func formatBarTime(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let spanMs = (visibleBars.last?.timestamp ?? timestamp) - (visibleBars.first?.timestamp ?? timestamp)
        let f: DateFormatter
        if spanMs > 86_400_000 * 2 {
            f = ChartDateFormatters.dayFormatter
        } else if spanMs > 86_400_000 {
            f = ChartDateFormatters.dayTimeFormatter
        } else {
            f = ChartDateFormatters.timeFormatter
        }
        if f.timeZone != timeZone {
            f.timeZone = timeZone
        }
        return f.string(from: date)
    }

    // MARK: - 8. RSI Sub-Window View & Plot

    private var rsiSeries: [Double?] {
        let reference = allBars.isEmpty ? visibleBars : allBars
        return MomentumEngine.computeRSISeries(bars: reference, period: 14)
    }

    private var visibleRsi: [Double?] {
        Array(rsiSeries.prefix(visibleBars.count))
    }

    // EMA 9 of RSI 14
    private var rsiEma9Series: [Double?] {
        MomentumEngine.computeEMA(series: rsiSeries, period: 9)
    }

    private var visibleRsiEma9: [Double?] {
        Array(rsiEma9Series.prefix(visibleBars.count))
    }

    // WMA 45 of RSI 14
    private var rsiWma45Series: [Double?] {
        MomentumEngine.computeWMA(series: rsiSeries, period: 45)
    }

    private var visibleRsiWma45: [Double?] {
        Array(rsiWma45Series.prefix(visibleBars.count))
    }

    private func rsiPlotView(size: CGSize, stepX: CGFloat? = nil, panOffset: CGFloat = 0) -> some View {
        let rightAxisWidth: CGFloat = 55
        let bottomAxisHeight: CGFloat = 18
        let plotWidth = max(10, size.width - rightAxisWidth)
        let plotHeight = max(10, size.height - bottomAxisHeight)

        let stX: CGFloat = {
            if let s = stepX, s > 0 { return s }
            let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
            let effectiveZoom = max(0.5, min(4.0, zoomScale))
            let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
            return plotWidth / CGFloat(max(1, slotCount))
        }()

        let y70 = plotHeight * 0.30
        let y50 = plotHeight * 0.50
        let y30 = plotHeight * 0.70
        let bandH = y30 - y70

        return ZStack(alignment: .topLeading) {
            // Shaded 30-70 band
            Rectangle()
                .fill(Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.06))
                .frame(width: plotWidth, height: bandH)
                .position(x: plotWidth / 2.0, y: y70 + bandH / 2.0)

            // 70 Line & Label
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

            // 50 Line & Label
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

            // 30 Line & Label
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
            Path { path in
                var isFirst = true
                for (i, rsiOpt) in visibleRsi.enumerated() {
                    guard let rsi = rsiOpt else { continue }
                    let x = CGFloat(i) * stX + (stX / 2.0) + panOffset
                    let y = plotHeight - CGFloat(rsi / 100.0) * plotHeight
                    let clampedY = max(2, min(plotHeight - 2, y))
                    if isFirst {
                        path.move(to: CGPoint(x: x, y: clampedY))
                        isFirst = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: clampedY))
                    }
                }
            }
            .stroke(Color(red: 0.65, green: 0.45, blue: 0.95), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .clipped()

            // 2. EMA 9 Curve of RSI 14 (Sky Blue / Cyan)
            Path { path in
                var isFirst = true
                for (i, emaOpt) in visibleRsiEma9.enumerated() {
                    guard let ema = emaOpt else { continue }
                    let x = CGFloat(i) * stX + (stX / 2.0) + panOffset
                    let y = plotHeight - CGFloat(ema / 100.0) * plotHeight
                    let clampedY = max(2, min(plotHeight - 2, y))
                    if isFirst {
                        path.move(to: CGPoint(x: x, y: clampedY))
                        isFirst = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: clampedY))
                    }
                }
            }
            .stroke(Color(red: 0.22, green: 0.74, blue: 0.97), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            .clipped()

            // 3. WMA 45 Curve of RSI 14 (Gold / Amber)
            Path { path in
                var isFirst = true
                for (i, maOpt) in visibleRsiWma45.enumerated() {
                    guard let ma = maOpt else { continue }
                    let x = CGFloat(i) * stX + (stX / 2.0) + panOffset
                    let y = plotHeight - CGFloat(ma / 100.0) * plotHeight
                    let clampedY = max(2, min(plotHeight - 2, y))
                    if isFirst {
                        path.move(to: CGPoint(x: x, y: clampedY))
                        isFirst = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: clampedY))
                    }
                }
            }
            .stroke(Color(red: 1.0, green: 0.82, blue: 0.2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .clipped()

            // 4. Active / Hovered dot and cursor line
            if let hIdx = hoveredBarIndex, hIdx < visibleBars.count {
                let hX = CGFloat(hIdx) * stX + (stX / 2.0) + panOffset
                if hX >= 0 && hX <= plotWidth {
                    Rectangle()
                        .fill(AppColors.primaryText.opacity(0.4))
                        .frame(width: 1, height: plotHeight)
                        .position(x: hX, y: plotHeight / 2.0)

                    // RSI dot
                    if hIdx < visibleRsi.count, let rsi = visibleRsi[hIdx] {
                        let rsiY = plotHeight - CGFloat(rsi / 100.0) * plotHeight
                        let clampedY = max(2, min(plotHeight - 2, rsiY))
                        Circle()
                            .fill(Color(red: 0.65, green: 0.45, blue: 0.95))
                            .frame(width: 5, height: 5)
                            .position(x: hX, y: clampedY)
                    }

                    // EMA 9 dot
                    if hIdx < visibleRsiEma9.count, let ema = visibleRsiEma9[hIdx] {
                        let emaY = plotHeight - CGFloat(ema / 100.0) * plotHeight
                        let clampedY = max(2, min(plotHeight - 2, emaY))
                        Circle()
                            .fill(Color(red: 0.22, green: 0.74, blue: 0.97))
                            .frame(width: 5, height: 5)
                            .position(x: hX, y: clampedY)
                    }

                    // WMA 45 dot
                    if hIdx < visibleRsiWma45.count, let ma = visibleRsiWma45[hIdx] {
                        let maY = plotHeight - CGFloat(ma / 100.0) * plotHeight
                        let clampedY = max(2, min(plotHeight - 2, maY))
                        Circle()
                            .fill(Color(red: 1.0, green: 0.82, blue: 0.2))
                            .frame(width: 5, height: 5)
                            .position(x: hX, y: clampedY)
                    }
                }
            }

            // Time Axis at bottom of RSI
            timeAxis(width: plotWidth, height: plotHeight, stepX: stX, fullHeight: size.height, panOffset: panOffset)

            // Dedicated bottom Time Axis touch target for horizontal zoom
            Color.clear
                .frame(width: plotWidth, height: bottomAxisHeight)
                .contentShape(Rectangle())
                .position(x: plotWidth / 2.0, y: plotHeight + (bottomAxisHeight / 2.0))
                .gesture(timeAxisDragGesture(plotWidth: plotWidth))
        }
    }

    // MARK: - Price Axis & Time Axis Drag Gestures (TradingView Axis Zoom)
    private func priceAxisDragGesture(plotHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let dy = value.translation.height - lastPriceDragY
                lastPriceDragY = value.translation.height
                // Dragging down compresses price (increases span multiplier), dragging up expands (decreases span multiplier)
                let scaleChange = 1.0 + (dy / max(100, plotHeight)) * 1.5
                priceScaleMultiplier = max(0.15, min(6.0, priceScaleMultiplier * scaleChange))
            }
            .onEnded { _ in
                lastPriceDragY = 0
            }
    }

    private func timeAxisDragGesture(plotWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let dx = value.translation.width - lastTimeDragX
                lastTimeDragX = value.translation.width
                // Dragging right expands time zoom (wider candles), dragging left compresses time zoom (narrower candles)
                let scaleChange = 1.0 + (dx / max(100, plotWidth)) * 1.8
                zoomScale = max(0.5, min(4.0, zoomScale * scaleChange))
            }
            .onEnded { _ in
                lastTimeDragX = 0
            }
    }
}

private enum ChartDateFormatters {
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
