import SwiftUI

/// Professional candlestick chart and execution path view for Trade Replay.
/// Ported 1:1 from `@luxalgo/vela` and `trade-market-data.tsx` / `trade-chart.tsx`.
/// Ensures distinct horizontal coordinates for each bar without timestamp crowding.
public struct CandleChartView: View {
    let visibleBars: [MarketBar]
    let totalBarsCount: Int
    let trade: Trade
    let executions: [Execution]
    let throughTimestamp: Int64
    let unrealizedPnl: Decimal
    let timeZone: TimeZone
    let currency: String
    
    @State private var hoveredBarIndex: Int? = nil
    
    public init(
        visibleBars: [MarketBar],
        totalBarsCount: Int,
        trade: Trade,
        executions: [Execution],
        throughTimestamp: Int64,
        unrealizedPnl: Decimal,
        timeZone: TimeZone = .current,
        currency: String = "USD"
    ) {
        self.visibleBars = visibleBars
        self.totalBarsCount = max(visibleBars.count, totalBarsCount)
        self.trade = trade
        self.executions = executions
        self.throughTimestamp = throughTimestamp
        self.unrealizedPnl = unrealizedPnl
        self.timeZone = timeZone
        self.currency = currency
    }
    
    private var activeFills: [Execution] {
        executions.filter { Int64($0.executedAt.timeIntervalSince1970 * 1000) <= throughTimestamp }
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            // HUD Information Bar: shows detailed OHLC values for selected candle
            hudHeaderView
            
            // Candlestick Canvas drawing
            GeometryReader { geo in
                if visibleBars.isEmpty {
                    executionPathFallbackView(size: geo.size)
                } else {
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
            .frame(height: 240)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
            )
        }
    }
    
    // MARK: - 1. HUD Header
    
    private var activeHoveredBar: MarketBar? {
        guard let idx = hoveredBarIndex, idx >= 0, idx < visibleBars.count else {
            return visibleBars.last
        }
        return visibleBars[idx]
    }
    
    private var hudHeaderView: some View {
        HStack(spacing: 8) {
            if let bar = activeHoveredBar {
                Text(formatBarTime(bar.timestamp))
                    .font(AppTypography.monoCaption)
                    .foregroundColor(AppColors.primaryText)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text("O:")
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.price(bar.open))
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("H:")
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.price(bar.high))
                        .foregroundColor(AppColors.profit)
                    
                    Text("L:")
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.price(bar.low))
                        .foregroundColor(AppColors.loss)
                    
                    Text("C:")
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.price(bar.close))
                        .foregroundColor(bar.isUp ? AppColors.profit : AppColors.loss)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            } else {
                Text("No candle data available")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
    
    // MARK: - 2. Candlestick Main Plot
    
    private func candlestickPlotView(size: CGSize) -> some View {
        let rightAxisWidth: CGFloat = 55
        let bottomAxisHeight: CGFloat = 20
        let plotWidth = max(10, size.width - rightAxisWidth)
        let plotHeight = max(10, size.height - bottomAxisHeight)
        
        let bounds = calculatePriceBounds()
        let minP = bounds.minPrice
        let maxP = bounds.maxPrice
        let priceSpan = max(0.00001, maxP - minP)
        
        // Number of visible slots: minimum 15 to prevent oversized candles
        let slotCount = max(visibleBars.count, min(totalBarsCount, 50))
        let stepX = plotWidth / CGFloat(max(1, slotCount))
        let candleWidth = max(2.5, min(12.0, stepX * 0.7))
        
        return ZStack(alignment: .topLeading) {
            // Grid lines and right price axis
            gridAndPriceAxis(width: plotWidth, height: plotHeight, minP: minP, maxP: maxP, fullWidth: size.width)
            
            // Time axis (bottom)
            timeAxis(width: plotWidth, height: plotHeight, stepX: stepX, fullHeight: size.height)
            
// Core implementation detail
            volumeHistogram(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, candleWidth: candleWidth)
            
// Reference Entry & Exit lines
            referencePriceLines(plotWidth: plotWidth, plotHeight: plotHeight, minP: minP, span: priceSpan)
            
// Render candlesticks (wick + body) (Wick + Body)
            Canvas { context, _ in
                for (i, bar) in visibleBars.enumerated() {
                    let centerX = CGFloat(i) * stepX + (stepX / 2.0)
                    
                    let highD = (bar.high as NSDecimalNumber).doubleValue
                    let lowD = (bar.low as NSDecimalNumber).doubleValue
                    let openD = (bar.open as NSDecimalNumber).doubleValue
                    let closeD = (bar.close as NSDecimalNumber).doubleValue
                    
                    let yHigh = plotHeight - CGFloat((highD - minP) / priceSpan) * plotHeight
                    let yLow = plotHeight - CGFloat((lowD - minP) / priceSpan) * plotHeight
                    let yOpen = plotHeight - CGFloat((openD - minP) / priceSpan) * plotHeight
                    let yClose = plotHeight - CGFloat((closeD - minP) / priceSpan) * plotHeight
                    
                    let color = bar.isUp ? AppColors.profit : AppColors.loss
                    
// Draw candle wicks (Wick)
                    var wickPath = Path()
                    wickPath.move(to: CGPoint(x: centerX, y: yHigh))
                    wickPath.addLine(to: CGPoint(x: centerX, y: yLow))
                    context.stroke(wickPath, with: .color(color), lineWidth: 1.5)
                    
// Draw candle bodies (Body)
                    let bodyTop = min(yOpen, yClose)
                    let bodyHeight = max(2.0, abs(yClose - yOpen))
                    let bodyRect = CGRect(
                        x: centerX - (candleWidth / 2.0),
                        y: bodyTop,
                        width: candleWidth,
                        height: bodyHeight
                    )
                    context.fill(Path(bodyRect), with: .color(color))
                }
            }
            .frame(width: plotWidth, height: plotHeight)
            
// Core implementation detail
            fillsOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan)
            
// Core implementation detail
            if let hIdx = hoveredBarIndex, hIdx < visibleBars.count {
                let hX = CGFloat(hIdx) * stepX + (stepX / 2.0)
                Rectangle()
                    .fill(AppColors.primaryText.opacity(0.4))
                    .frame(width: 1, height: plotHeight)
                    .position(x: hX, y: plotHeight / 2.0)
            }
        }
    }
    
    // MARK: - 3. Grid & Axes
    
    private func gridAndPriceAxis(width: CGFloat, height: CGFloat, minP: Double, maxP: Double, fullWidth: CGFloat) -> some View {
        let levels = 4
        return ForEach(0...levels, id: \.self) { i in
            let ratio = Double(i) / Double(levels)
            let price = minP + ratio * (maxP - minP)
            let y = height - CGFloat(ratio) * height
            
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(AppColors.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            
            Text(Formatters.formatNumber(price))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 50, alignment: .leading)
                .position(x: width + 28, y: y)
        }
    }
    
    private func timeAxis(width: CGFloat, height: CGFloat, stepX: CGFloat, fullHeight: CGFloat) -> some View {
        let count = visibleBars.count
        let markInterval = max(1, count / 4)
        
        return ForEach(0..<count, id: \.self) { i in
            if i % markInterval == 0 || i == count - 1 {
                let x = CGFloat(i) * stepX + (stepX / 2.0)
                let timeStr = formatBarTime(visibleBars[i].timestamp)
                
                Text(timeStr)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(AppColors.secondaryText)
                    .position(x: x, y: height + 10)
            }
        }
    }
    
    // MARK: - 4. Volume Histogram
    
    private func volumeHistogram(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, candleWidth: CGFloat) -> some View {
        let maxVol = visibleBars.map { ($0.volume as NSDecimalNumber).doubleValue }.max() ?? 1.0
        let safeMaxVol = max(1.0, maxVol)
        let volAreaHeight = plotHeight * 0.18
        
        return ForEach(0..<visibleBars.count, id: \.self) { i in
            let bar = visibleBars[i]
            let v = (bar.volume as NSDecimalNumber).doubleValue
            let barH = CGFloat(v / safeMaxVol) * volAreaHeight
            let x = CGFloat(i) * stepX + (stepX / 2.0)
            let y = plotHeight - barH
            
            Rectangle()
                .fill((bar.isUp ? AppColors.profit : AppColors.loss).opacity(0.25))
                .frame(width: max(1.5, candleWidth * 0.8), height: barH)
                .position(x: x, y: y + barH / 2.0)
        }
    }
    
    // MARK: - 5. Reference Price Lines (Entry & Exit)
    
    private func referencePriceLines(plotWidth: CGFloat, plotHeight: CGFloat, minP: Double, span: Double) -> some View {
        let entryD = (trade.avgEntry as NSDecimalNumber).doubleValue
        let yEntry = plotHeight - CGFloat((entryD - minP) / span) * plotHeight
        
        return ZStack {
            // Entry Line
            Path { path in
                path.move(to: CGPoint(x: 0, y: yEntry))
                path.addLine(to: CGPoint(x: plotWidth, y: yEntry))
            }
            .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            
            Text("ENTRY: \(Formatters.price(trade.avgEntry))")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(AppColors.accent)
                .foregroundColor(.white)
                .cornerRadius(4)
                .position(x: 45, y: max(10, yEntry - 10))
            
// Core implementation detail
            if let avgExit = trade.avgExit {
                let exitD = (avgExit as NSDecimalNumber).doubleValue
                let yExit = plotHeight - CGFloat((exitD - minP) / span) * plotHeight
                let pnlColor = Formatters.pnlColor(trade.netPnl)
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yExit))
                    path.addLine(to: CGPoint(x: plotWidth, y: yExit))
                }
                .stroke(pnlColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                
                Text("EXIT: \(Formatters.price(avgExit)) (\(Formatters.formatPnL(trade.netPnl, currency: currency)))")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(pnlColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .position(x: plotWidth - 65, y: max(10, yExit - 10))
            }
        }
    }
    
    /// Fills overlay displaying execution arrows and lots on the candle timeline
    private func fillsOverlay(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, minP: Double, span: Double) -> some View {
        ForEach(activeFills) { fill in
            let fillMs = Int64(fill.executedAt.timeIntervalSince1970 * 1000)
            let barIndex = visibleBars.firstIndex { $0.timestamp >= fillMs } ?? (visibleBars.count - 1)
            let x = CGFloat(barIndex) * stepX + (stepX / 2.0)
            let fillPriceD = (fill.price as NSDecimalNumber).doubleValue
            let y = plotHeight - CGFloat((fillPriceD - minP) / span) * plotHeight
            
            let isBuy = fill.side == .buy
            
            HStack(spacing: 2) {
                Image(systemName: isBuy ? "triangle.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
                Text("\(isBuy ? "BUY" : "SELL") \(fill.quantity)")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(isBuy ? AppColors.profit : AppColors.loss)
            .foregroundColor(.white)
            .cornerRadius(4)
            .shadow(radius: 2)
            .position(x: x, y: isBuy ? y + 16 : y - 16)
        }
    }
    
    /// Fallback trajectory view when external candle feeds are not available
    private func executionPathFallbackView(size: CGSize) -> some View {
        let entryD = (trade.avgEntry as NSDecimalNumber).doubleValue
        let exitD = trade.avgExit.map { ($0 as NSDecimalNumber).doubleValue } ?? entryD
        
        let minP = min(entryD, exitD) * 0.998
        let maxP = max(entryD, exitD) * 1.002
        let span = max(0.0001, maxP - minP)
        
        let w = size.width - 24
        let h = size.height - 40
        let pnlColor = Formatters.pnlColor(trade.netPnl)
        
        let yEntry = h - CGFloat((entryD - minP) / span) * h + 20
        let yExit = h - CGFloat((exitD - minP) / span) * h + 20
        
        return ZStack {
            // Trajectory Line
            Path { path in
                path.move(to: CGPoint(x: 20, y: yEntry))
                path.addLine(to: CGPoint(x: w, y: yExit))
            }
            .stroke(pnlColor, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            
            // Entry Marker
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: trade.direction == .long ? "triangle.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8))
                    Text("ENTRY: \(Formatters.price(trade.avgEntry))")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppColors.accent)
                .foregroundColor(.white)
                .cornerRadius(4)
                
                Text(Formatters.formatDateTime(trade.openedAt, timeZone: timeZone))
                    .font(.system(size: 8))
                    .foregroundColor(AppColors.secondaryText)
            }
            .position(x: 65, y: max(25, yEntry - 20))
            
            // Exit Marker (if closed)
            if let closedAt = trade.closedAt, let avgExit = trade.avgExit {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: trade.direction == .long ? "arrowtriangle.down.fill" : "triangle.fill")
                            .font(.system(size: 8))
                        Text("EXIT: \(Formatters.price(avgExit))")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(pnlColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    
                    Text(Formatters.formatDateTime(closedAt, timeZone: timeZone))
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.secondaryText)
                }
                .position(x: w - 45, y: max(25, yExit - 20))
            }
            
            // Floating Net P&L Center Pill
            Text(Formatters.formatPnL(trade.netPnl, currency: currency))
                .font(AppTypography.captionBold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(pnlColor.opacity(0.18))
                .foregroundColor(pnlColor)
                .cornerRadius(12)
                .position(x: size.width / 2.0, y: (yEntry + yExit) / 2.0)
            
            // Footer notice
            VStack {
                Spacer()
                Text("Showing execution price path. Connect market data in Settings to load candles.")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.bottom, 6)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculatePriceBounds() -> (minPrice: Double, maxPrice: Double) {
        var lows = visibleBars.map { ($0.low as NSDecimalNumber).doubleValue }
        var highs = visibleBars.map { ($0.high as NSDecimalNumber).doubleValue }
        
        let entryD = (trade.avgEntry as NSDecimalNumber).doubleValue
        if entryD > 0 {
            lows.append(entryD)
            highs.append(entryD)
        }
        if let exit = trade.avgExit {
            let exitD = (exit as NSDecimalNumber).doubleValue
            lows.append(exitD)
            highs.append(exitD)
        }
        
        let minVal = lows.min() ?? 1.0
        let maxVal = highs.max() ?? 1.0
        let span = max(0.0001, maxVal - minVal)
        let margin = span * 0.06
        
        return (minPrice: minVal - margin, maxPrice: maxVal + margin)
    }
    
    private func updateHoveredBar(at x: CGFloat, totalWidth: CGFloat) {
        guard !visibleBars.isEmpty, totalWidth > 0 else { return }
        let slotCount = max(visibleBars.count, min(totalBarsCount, 50))
        let stepX = totalWidth / CGFloat(max(1, slotCount))
        let index = Int(x / stepX)
        if index >= 0 && index < visibleBars.count && self.hoveredBarIndex != index {
            self.hoveredBarIndex = index
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }
    
    private func formatBarTime(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let f = DateFormatter()
        f.timeZone = timeZone
        let spanMs = (visibleBars.last?.timestamp ?? timestamp) - (visibleBars.first?.timestamp ?? timestamp)
        if spanMs > 86_400_000 * 2 {
            f.dateFormat = "MM/dd"
        } else if spanMs > 86_400_000 {
            f.dateFormat = "MM/dd HH:mm"
        } else {
            f.dateFormat = "HH:mm"
        }
        return f.string(from: date)
    }
}
