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
    public let patterns: [DetectedCandlePattern]
    
    @State private var hoveredBarIndex: Int? = nil
    
    public init(
        bars: [MarketBar],
        symbol: String,
        timeframe: String = "M15",
        showStructure: Bool = true,
        showEMA: Bool = false,
        keyLevels: [KeyLevel] = [],
        patterns: [DetectedCandlePattern] = []
    ) {
        self.bars = bars
        self.symbol = symbol
        self.timeframe = timeframe
        self.showStructure = showStructure
        self.keyLevels = keyLevels
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
        HStack(alignment: .center, spacing: 8) {
            // Symbol
            Text(symbol)
                .font(AppTypography.cardHeaderUppercase)
                .foregroundColor(AppColors.primaryText)
            
            // Key Levels Pill Summary (if any)
            if !keyLevels.isEmpty {
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
            
            // Footprint Key Levels Overlay
            keyLevelsOverlay(width: plotWidth, height: plotHeight, minP: minP, span: span)
            
            // Candlesticks
            ForEach(0..<bars.count, id: \.self) { i in
                let bar = bars[i]
                let isUp = bar.isUp
                let color = isUp ? AppColors.profit : AppColors.loss
                
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
                        .fill(color)
                        .frame(width: 1, height: max(1, yLow - yHigh))
                        .position(x: xCenter, y: (yHigh + yLow) / 2.0)
                    
                    // Real Body
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: candleWidth, height: bodyHeight)
                        .position(x: xCenter, y: bodyTop + bodyHeight / 2.0)
                }
            }
            
            // Candlestick Pattern Markers
            candlestickPatternsOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span)
            
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
    
    // MARK: - 3. Footprint Key Levels Overlay
    private func keyLevelsOverlay(width: CGFloat, height: CGFloat, minP: Double, span: Double) -> some View {
        ForEach(keyLevels) { level in
            let priceD = (level.price as NSDecimalNumber).doubleValue
            if priceD >= minP && priceD <= (minP + span) {
                let y = height - CGFloat((priceD - minP) / span) * height
                let color = levelColor(for: level)
                let isDotted = level.isNaked
                
                ZStack(alignment: .trailing) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: isDotted ? 1.0 : 1.2, dash: isDotted ? [4, 4] : []))
                    
                    Text(level.label)
                        .font(AppTypography.captionMicro)
                        .foregroundColor(color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppColors.cardBackground.opacity(0.9))
                        .cornerRadius(2)
                        .position(x: width - 36, y: max(8, min(height - 8, y - 8)))
                }
            }
        }
    }
    
    // MARK: - 4. Candlestick Pattern Badges Overlay
    private func candlestickPatternsOverlay(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, minP: Double, span: Double) -> some View {
        ForEach(patterns) { pat in
            if let idx = bars.firstIndex(where: { $0.timestamp == pat.barTimestamp }) {
                let bar = bars[idx]
                let xCenter = CGFloat(idx) * stepX + (stepX / 2.0)
                let highD = (bar.high as NSDecimalNumber).doubleValue
                let lowD = (bar.low as NSDecimalNumber).doubleValue
                let yHigh = plotHeight - CGFloat((highD - minP) / span) * plotHeight
                let yLow = plotHeight - CGFloat((lowD - minP) / span) * plotHeight
                
                let yPos = pat.type.isBullish ? min(plotHeight - 6, yLow + 12) : max(6, yHigh - 12)
                let col = pat.type.isBullish ? AppColors.profit : AppColors.loss
                
                Text(pat.type.rawValue)
                    .font(AppTypography.captionMicro)
                    .foregroundColor(col)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(AppColors.cardBackground.opacity(0.9))
                    .cornerRadius(2)
                    .position(x: xCenter, y: yPos)
            }
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
            return AppColors.accentBlue // Blue
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
