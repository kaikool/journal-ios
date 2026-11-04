import SwiftUI

// MARK: - Unified Candlestick, Grid & Crosshair Rendering Engine
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

    // MARK: 8. Cached Bar Time Formatting
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
