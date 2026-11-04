import SwiftUI

// MARK: - Footprint Key Levels Overlay (TradingView Footprint Alignment)
extension SharedChartCanvas {

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
}
