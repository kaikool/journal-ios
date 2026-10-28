import SwiftUI

// MARK: - Pure Market Candlestick Chart (Multi-Timeframe Structure View)
// Displays clean institutional candlestick price action without requiring trade execution overlays
public struct MarketCandleChartView: View {
    public let bars: [MarketBar]
    public let symbol: String
    public let timeframe: String
    public let showEMA: Bool
    
    @State private var hoveredBarIndex: Int? = nil
    
    public init(bars: [MarketBar], symbol: String, timeframe: String = "M15", showEMA: Bool = true) {
        self.bars = bars
        self.symbol = symbol
        self.timeframe = timeframe
        self.showEMA = showEMA
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
        let activeIdx: Int? = {
            if let idx = hoveredBarIndex, idx < bars.count {
                return idx
            }
            return bars.isEmpty ? nil : (bars.count - 1)
        }()
        let activeBar: MarketBar? = activeIdx.map { bars[$0] }
        
        let ema21Series = MovingAverageEngine.calculateEMA(period: 21, bars: bars)
        let ema50Series = MovingAverageEngine.calculateEMA(period: 50, bars: bars)
        let activeEMA21 = activeIdx.flatMap { $0 < ema21Series.count ? ema21Series[$0] : nil }
        let activeEMA50 = activeIdx.flatMap { $0 < ema50Series.count ? ema50Series[$0] : nil }
        
        let trend = MovingAverageEngine.analyzeTimeframe(bars: bars, timeframe: timeframe, symbol: symbol)?.trend
        
        return VStack(spacing: 3) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                    Text("•")
                        .foregroundColor(AppColors.secondaryText.opacity(0.5))
                    Text(timeframe)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.brand)
                }
                
                if let t = trend {
                    let isBull = t == .bullish || t == .strongBullish
                    let isBear = t == .bearish || t == .strongBearish
                    let c = isBull ? AppColors.profit : (isBear ? AppColors.loss : AppColors.warning)
                    Text(t.rawValue)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(c.opacity(0.15))
                        .foregroundColor(c)
                        .cornerRadius(3)
                }
                
                Spacer()
                
                if let bar = activeBar {
                    let isUp = bar.isUp
                    let color = isUp ? AppColors.profit : AppColors.loss
                    HStack(spacing: 6) {
                        Text("O \(formatPrice(bar.open))")
                        Text("H \(formatPrice(bar.high))")
                        Text("L \(formatPrice(bar.low))")
                        Text("C \(formatPrice(bar.close))")
                            .foregroundColor(color)
                            .fontWeight(.semibold)
                    }
                    .font(AppTypography.number(9, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Sub-row: Dynamic Causal EMA 21 & 50 numeric display
            if showEMA, activeEMA21 != nil || activeEMA50 != nil {
                HStack(spacing: 8) {
                    if let e21 = activeEMA21 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.85, blue: 1.0))
                                .frame(width: 5, height: 5)
                            Text("EMA 21: \(formatPrice(e21))")
                                .font(AppTypography.number(8.5, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.85, blue: 1.0))
                        }
                    }
                    if let e50 = activeEMA50 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                            Text("EMA 50: \(formatPrice(e50))")
                                .font(AppTypography.number(8.5, weight: .semibold))
                                .foregroundColor(Color.orange)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
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
            
            // Dynamic EMA 21 & EMA 50 Curves (Strictly Causal, No Lookahead Bias)
            if showEMA {
                emaCurvesOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: span)
            }
            
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
    
    // MARK: - 2b. EMA Curves Overlay
    @ViewBuilder
    private func emaCurvesOverlay(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double
    ) -> some View {
        if bars.count >= 2 {
            let ema21 = MovingAverageEngine.calculateEMA(period: 21, bars: bars)
            let ema50 = MovingAverageEngine.calculateEMA(period: 50, bars: bars)
            
            ZStack {
                // EMA 50 (Orange)
                if ema50.count == bars.count {
                    Path { path in
                        for (idx, val) in ema50.enumerated() {
                            let x = CGFloat(idx) * stepX + (stepX / 2.0)
                            let pD = (val as NSDecimalNumber).doubleValue
                            let y = plotHeight - CGFloat((pD - minP) / span) * plotHeight
                            let clampedY = max(2, min(plotHeight - 2, y))
                            if idx == 0 { path.move(to: CGPoint(x: x, y: clampedY)) }
                            else { path.addLine(to: CGPoint(x: x, y: clampedY)) }
                        }
                    }
                    .stroke(Color.orange.opacity(0.85), lineWidth: 1.3)
                }
                
                // EMA 21 (Cyan)
                if ema21.count == bars.count {
                    Path { path in
                        for (idx, val) in ema21.enumerated() {
                            let x = CGFloat(idx) * stepX + (stepX / 2.0)
                            let pD = (val as NSDecimalNumber).doubleValue
                            let y = plotHeight - CGFloat((pD - minP) / span) * plotHeight
                            let clampedY = max(2, min(plotHeight - 2, y))
                            if idx == 0 { path.move(to: CGPoint(x: x, y: clampedY)) }
                            else { path.addLine(to: CGPoint(x: x, y: clampedY)) }
                        }
                    }
                    .stroke(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.95), lineWidth: 1.5)
                }
            }
        }
    }
    
    // MARK: - 3. Grid & Axes
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
    
    // MARK: - 4. Volume Histogram
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
