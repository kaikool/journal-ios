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
    
    @State private var hoveredBarIndex: Int? = nil
    
    public init(
        visibleBars: [MarketBar],
        allBars: [MarketBar] = [],
        totalBarsCount: Int,
        trade: Trade,
        executions: [Execution],
        throughTimestamp: Int64,
        unrealizedPnl: Decimal,
        timeZone: TimeZone = .current,
        currency: String = "USD"
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
            
// Unified trade overlay (entry/exit lines, arrows, connecting line)
            tradeOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan)
            
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
            let clampedY = max(8, min(height - 8, y))
            
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            .stroke(AppColors.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            
            Text(Formatters.price(Decimal(price)))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 50, alignment: .leading)
                .position(x: width + 28, y: clampedY)
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
    
    // MARK: - 5. Unified Trade Overlay (Entry/Exit Lines, Fill Markers, Connecting Line)
    
    private func tradeOverlay(plotWidth: CGFloat, plotHeight: CGFloat, stepX: CGFloat, minP: Double, span: Double) -> some View {
        let entryD = (trade.avgEntry as NSDecimalNumber).doubleValue
        let yEntry = plotHeight - CGFloat((entryD - minP) / span) * plotHeight
        let openMs = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let closeMs = Int64((trade.closedAt ?? Date()).timeIntervalSince1970 * 1000)
        
        let entryBarIdx = visibleBars.firstIndex { $0.timestamp >= openMs }
        let hasReachedOpen = entryBarIdx != nil
        let entryX = CGFloat(entryBarIdx ?? 0) * stepX + (stepX / 2.0)
        
        let hasReachedExit = (trade.status != .open) && ((visibleBars.last?.timestamp ?? 0) >= closeMs || visibleBars.count >= totalBarsCount)
        
        return ZStack {
            // 1. Entry horizontal dashed reference line (always visible)
            Path { path in
                path.move(to: CGPoint(x: 0, y: yEntry))
                path.addLine(to: CGPoint(x: plotWidth, y: yEntry))
            }
            .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            
            // 2. Entry marker & label (shown once replay reaches open time)
            if hasReachedOpen {
                Text("ENTRY \(Formatters.price(trade.avgEntry))")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppColors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .position(x: min(plotWidth - 40, max(40, entryX)), y: max(10, yEntry - 12))
                
                Image(systemName: trade.direction == .long ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.accent)
                    .position(x: entryX, y: trade.direction == .long ? yEntry + 10 : yEntry - 10)
            }
            
            // 3. Exit line + label + final connecting line (shown once replay reaches exit time)
            if let avgExit = trade.avgExit, hasReachedExit {
                let exitD = (avgExit as NSDecimalNumber).doubleValue
                let yExit = plotHeight - CGFloat((exitD - minP) / span) * plotHeight
                let exitBarIdx = visibleBars.firstIndex { $0.timestamp >= closeMs } ?? (visibleBars.count - 1)
                let exitX = CGFloat(exitBarIdx) * stepX + (stepX / 2.0)
                let pnlColor = Formatters.pnlColor(trade.netPnl)
                
                // Exit horizontal dashed line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yExit))
                    path.addLine(to: CGPoint(x: plotWidth, y: yExit))
                }
                .stroke(pnlColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Connecting line from Entry to Exit
                if hasReachedOpen {
                    Path { path in
                        path.move(to: CGPoint(x: entryX, y: yEntry))
                        path.addLine(to: CGPoint(x: exitX, y: yExit))
                    }
                    .stroke(pnlColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                
                // Exit label
                Text("EXIT \(Formatters.price(avgExit)) (\(Formatters.formatPnL(trade.netPnl, currency: currency)))")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(pnlColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .position(x: min(plotWidth - 55, max(55, exitX)), y: max(10, yExit - 12))
                
                // Exit arrow marker
                Image(systemName: trade.direction == .long ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    .font(.system(size: 10))
                    .foregroundColor(pnlColor)
                    .position(x: exitX, y: trade.direction == .long ? yExit - 10 : yExit + 10)
            } else if hasReachedOpen, let curBar = visibleBars.last {
                // 4. In-progress trade tracking line: tracks current bar during replay or for open trades
                let curPrice = (curBar.close as NSDecimalNumber).doubleValue
                let yCur = plotHeight - CGFloat((curPrice - minP) / span) * plotHeight
                let curX = CGFloat(visibleBars.count - 1) * stepX + (stepX / 2.0)
                let curPnl = TradeReplayEngine.computeUnrealizedPnl(trade: trade, currentPrice: curBar.close, isLastBar: false)
                let curColor = Formatters.pnlColor(curPnl)
                
                Path { path in
                    path.move(to: CGPoint(x: entryX, y: yEntry))
                    path.addLine(to: CGPoint(x: curX, y: yCur))
                }
                .stroke(curColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                
                if trade.status == .open {
                    Text("LIVE \(Formatters.price(curBar.close))")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(curColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .position(x: min(plotWidth - 40, max(40, curX)), y: max(10, yCur - 12))
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculatePriceBounds() -> (minPrice: Double, maxPrice: Double) {
        let referenceBars = allBars.isEmpty ? visibleBars : allBars
        var lows = referenceBars.map { ($0.low as NSDecimalNumber).doubleValue }
        var highs = referenceBars.map { ($0.high as NSDecimalNumber).doubleValue }
        
        let entryD = (trade.avgEntry as NSDecimalNumber).doubleValue
        if entryD > 0 {
            lows.append(entryD)
            highs.append(entryD)
        }
        if let exit = trade.avgExit {
            let exitD = (exit as NSDecimalNumber).doubleValue
            if exitD > 0 {
                lows.append(exitD)
                highs.append(exitD)
            }
        }
        
        let minVal = lows.min() ?? 1.0
        let maxVal = highs.max() ?? 1.0
        let span = max(0.0001, maxVal - minVal)
        let margin = span * 0.08
        
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
