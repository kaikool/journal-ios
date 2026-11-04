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
    public let patterns: [DetectedCandlePattern]

    @State private var hoveredBarIndex: Int? = nil

    public init(
        bars: [MarketBar],
        symbol: String,
        timeframe: String = "M15",
        showStructure: Bool = true,
        showEMA: Bool = false,
        keyLevels: [KeyLevel] = [],
        sessionProfiles: [SessionProfileSnapshot] = [],
        developingProfile: DevelopingProfile? = nil,
        patterns: [DetectedCandlePattern] = []
    ) {
        self.bars = bars
        self.symbol = symbol
        self.timeframe = timeframe
        self.showStructure = showStructure
        self.keyLevels = keyLevels
        self.sessionProfiles = sessionProfiles
        self.developingProfile = developingProfile
        self.patterns = patterns
    }

    public var body: some View {
        VStack(spacing: 4) {
            hudHeaderView

            GeometryReader { geo in
                candlestickPlotView(size: geo.size)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateHoveredBar(at: value.location.x, totalWidth: geo.size.width - 55)
                            }
                            .onEnded { _ in
                                hoveredBarIndex = nil
                            }
                    )
            }
        }
    }

    // MARK: - 1. HUD Header Bar
    private var hudHeaderView: some View {
        let hoveredPattern: DetectedCandlePattern? = {
            guard let idx = hoveredBarIndex, idx < bars.count else { return nil }
            let bar = bars[idx]
            return patterns.first(where: { $0.barTimestamp == bar.timestamp })
        }()

        return HStack(alignment: .center, spacing: 8) {
            // Symbol
            Text(symbol)
                .font(AppTypography.cardHeaderUppercase)
                .foregroundColor(AppColors.primaryText)

            // Hovered Price Action Pattern Pill (Clean HUD presentation, zero chart canvas clutter)
            if let pat = hoveredPattern {
                AppBadge(
                    pat.type.displayName,
                    style: pat.type.isBullish ? .profit : (pat.type.isBearish ? .loss : .brand)
                )
                if let lvl = pat.confluenceKeyLevel {
                    AppBadge("@ \(lvl.label)", variant: .secondary)
                }
            } else if !keyLevels.isEmpty {
                // Key Levels Pill Summary (if any)
                HStack(spacing: 4) {
                    ForEach(keyLevels.prefix(3)) { lvl in
                        Text("\(lvl.label): \(formatPrice(lvl.price))")
                            .font(AppTypography.captionMicro)
                            .foregroundColor(levelColor(for: lvl))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppColors.cardBackground)
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 2. Candlestick Canvas Plot
    private func candlestickPlotView(size: CGSize) -> some View {
        let count = max(1, bars.count)
        let plotWidth = max(10, size.width - 55)
        let plotHeight = max(10, size.height - 20)
        let stepX = plotWidth / CGFloat(count)
        let candleWidth = max(1.5, min(14.0, stepX * 0.75))

        let allPrices = bars.flatMap { [($0.high as NSDecimalNumber).doubleValue, ($0.low as NSDecimalNumber).doubleValue] }
        let rawMin = allPrices.min() ?? 1.0
        let rawMax = allPrices.max() ?? 2.0
        let padding = max(0.0001, (rawMax - rawMin) * 0.08)
        let minP = rawMin - padding
        let maxP = rawMax + padding
        let span = max(0.0001, maxP - minP)

        return ZStack(alignment: .topLeading) {
            // Price Grid & Right Axis
            gridAndPriceAxis(width: plotWidth, height: plotHeight, minP: minP, maxP: maxP)

            // Volume Histogram (Subtle background)
            volumeHistogram(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, candleWidth: candleWidth)

            // TradingView-aligned Footprint POC & Key Levels Overlay (Time-bounded segments + selective rays)
            footprintOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span)

            // Candlesticks
            ForEach(0..<bars.count, id: \.self) { i in
                let bar = bars[i]

                // Highlight Price Action pattern by changing candle color directly (Zero text clutter)
                let matchedPattern = patterns.first(where: { $0.barTimestamp == bar.timestamp })
                let isPattern = matchedPattern != nil
                let candleColor: Color = {
                    if let pat = matchedPattern {
                        if pat.type.isBullish {
                            return AppColors.patternBullish
                        } else if pat.type.isBearish {
                            return AppColors.patternBearish
                        } else {
                            return AppColors.patternNeutral
                        }
                    }
                    return bar.isUp ? AppColors.profit : AppColors.loss
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
                let bodyHeight = max(1.0, abs(yOpen - yClose))
                let xCenter = CGFloat(i) * stepX + (stepX / 2.0)

                ZStack {
                    // Wick
                    Rectangle()
                        .fill(candleColor)
                        .frame(width: isPattern ? 1.5 : 1, height: max(1, yLow - yHigh))
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
            timeAxis(width: plotWidth, height: plotHeight, stepX: stepX)

            // Hover vertical crosshair line
            if let hIdx = hoveredBarIndex, hIdx < bars.count {
                let hX = CGFloat(hIdx) * stepX + (stepX / 2.0)
                Rectangle()
                    .fill(AppColors.primaryText.opacity(0.35))
                    .frame(width: 1, height: plotHeight)
                    .position(x: hX, y: plotHeight / 2.0)
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

            // 2. Developing (Live) Ongoing Session Profile
            if let dev = developingProfile {
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

                // 1. Session Bounded Solid POC line (Only spans this session's candles, zero text over candles)
                if segXEnd >= 0 && x1 <= plotWidth {
                    Path { path in
                        path.move(to: CGPoint(x: max(0, x1), y: y))
                        path.addLine(to: CGPoint(x: min(plotWidth, segXEnd), y: y))
                    }
                    .stroke(col, lineWidth: lineWidth)
                }

                // 2. Untested (Naked) POC Ray
                if snap.isNaked {
                    var rayEndIdx = bars.count - 1
                    if eI + 1 < bars.count {
                        for k in (eI + 1)..<bars.count {
                            let b = bars[k]
                            if b.low <= snap.pocPrice && b.high >= snap.pocPrice {
                                rayEndIdx = k
                                break
                            }
                        }
                    }
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

                // 3. Immediate Prior Staircase Step
                if let priorPoc = snap.priorStepPocPrice, isD1orW1 {
                    let priorD = (priorPoc as NSDecimalNumber).doubleValue
                    if priorD >= (minP - span * 0.05) && priorD <= (minP + span * 1.05) {
                        let priorY = plotHeight - CGFloat((priorD - minP) / span) * plotHeight
                        Path { path in
                            path.move(to: CGPoint(x: max(0, x1), y: priorY))
                            path.addLine(to: CGPoint(x: min(plotWidth, segXEnd), y: priorY))
                        }
                        .stroke(col.opacity(0.4), style: StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
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
        let pocD = (dev.currentPoc as NSDecimalNumber).doubleValue
        if pocD >= (minP - span * 0.05) && pocD <= (minP + span * 1.05) {
            let y = plotHeight - CGFloat((pocD - minP) / span) * plotHeight
            let col = sessionColor(for: dev.sessionType)

            let sIdx = bars.firstIndex(where: { $0.date >= dev.startTime }) ?? max(0, bars.count - 12)
            let x1 = CGFloat(sIdx) * stepX + (stepX / 2.0)
            let x2 = CGFloat(max(0, bars.count - 1)) * stepX + (stepX / 2.0)

            if x2 >= 0 && x1 <= plotWidth {
                // Solid line for current active session
                Path { path in
                    path.move(to: CGPoint(x: max(0, x1), y: y))
                    path.addLine(to: CGPoint(x: min(plotWidth, x2), y: y))
                }
                .stroke(col, lineWidth: 1.8)

                // Faint dotted ray to the right edge
                if x2 < plotWidth {
                    Path { path in
                        path.move(to: CGPoint(x: x2, y: y))
                        path.addLine(to: CGPoint(x: plotWidth, y: y))
                    }
                    .stroke(col.opacity(0.65), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))
                }

                let devTag = dev.sessionType == .daily ? "[D]" : (dev.sessionType == .weekly ? "[W]" : "[TY]")
                Text(devTag)
                    .font(AppTypography.captionMicro)
                    .foregroundColor(col)
                    .position(x: plotWidth - 14, y: max(6, min(plotHeight - 6, y - 6)))
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
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = SessionFootprintEngine.sessionTimeZone
            let todayStartIdx = bars.firstIndex(where: { cal.isDateInToday($0.date) }) ?? max(0, bars.count - 24)
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
                    .stroke(AppColors.secondaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))

                    Text(lvl.label)
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(AppColors.cardBackground.opacity(0.9))
                        .cornerRadius(2)
                        .position(x: min(plotWidth - 24, max(24, x2 - 16)), y: max(8, min(plotHeight - 8, y - 7)))
                }
            }
        }
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
            .stroke(AppColors.border.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))

            Text(formatPrice(Decimal(price)))
                .font(AppTypography.number(9, weight: .regular))
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 50, alignment: .leading)
                .position(x: width + 28, y: clampedY)
        }
    }

    private func timeAxis(width: CGFloat, height: CGFloat, stepX: CGFloat) -> some View {
        let count = bars.count
        let markInterval = max(1, count / 4)

        return ForEach(0..<count, id: \.self) { i in
            if i % markInterval == 0 || i == count - 1 {
                let x = CGFloat(i) * stepX + (stepX / 2.0)
                let timeStr = formatBarTime(bars[i].timestamp)

                Text(timeStr)
                    .font(AppTypography.number(9, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
                    .position(x: x, y: height + 9)
            }
        }
    }

    // MARK: - 6. Volume Histogram
    private func volumeHistogram(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, candleWidth: CGFloat) -> some View {
        let maxVol = bars.map { ($0.volume as NSDecimalNumber).doubleValue }.max() ?? 1.0
        let safeMaxVol = max(1.0, maxVol)
        let volAreaHeight = plotHeight * 0.18

        return ForEach(0..<bars.count, id: \.self) { i in
            let bar = bars[i]
            let vol = (bar.volume as NSDecimalNumber).doubleValue
            let height = CGFloat(vol / safeMaxVol) * volAreaHeight
            let xCenter = CGFloat(i) * stepX + (stepX / 2.0)
            let color = bar.isUp ? AppColors.profit.opacity(0.18) : AppColors.loss.opacity(0.18)

            Rectangle()
                .fill(color)
                .frame(width: max(1, candleWidth * 0.8), height: max(1, height))
                .position(x: xCenter, y: plotHeight - height / 2.0)
        }
    }

    // MARK: - Helpers
    private func levelColor(for level: KeyLevel) -> Color {
        switch level.type {
        case .sessionPoc(.tokyo):
            return Color(red: 0.0, green: 0.72, blue: 0.83) // Cyan
        case .sessionPoc(.london):
            return Color(red: 1.0, green: 0.70, blue: 0.0) // Amber
        case .sessionPoc(.newYork):
            return Color(red: 0.67, green: 0.0, blue: 1.0) // Purple
        case .sessionPoc(.daily):
            return AppColors.profit // Green
        case .sessionPoc(.weekly):
            return AppColors.accent // Blue
        case .nakedPoc:
            return AppColors.loss.opacity(0.85) // Reddish dotted ray
        case .pdh, .pdl, .pdc:
            return AppColors.primaryText.opacity(0.6)
        default:
            return AppColors.secondaryText
        }
    }

    private func updateHoveredBar(at x: CGFloat, totalWidth: CGFloat) {
        guard !bars.isEmpty, totalWidth > 0 else { return }
        let stepX = totalWidth / CGFloat(bars.count)
        let idx = Int(x / stepX)
        hoveredBarIndex = max(0, min(bars.count - 1, idx))
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
