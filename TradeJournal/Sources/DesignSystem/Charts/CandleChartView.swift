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
    let showMarketStructure: Bool
    let showLiquidity: Bool
    let showRSI: Bool
    let isLandscape: Bool
    @State private var activeRSIMAType: MomentumEngine.RSIMAType
    
    @State private var hoveredBarIndex: Int? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    @State private var panOffset: CGFloat = 0.0
    @State private var lastDragX: CGFloat = 0.0
    
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
        showLiquidity: Bool = true,
        showRSI: Bool = true,
        rsiMAType: MomentumEngine.RSIMAType = .ema,
        isLandscape: Bool = false
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
        self.showLiquidity = showLiquidity
        self.showRSI = showRSI
        self.isLandscape = isLandscape
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
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        candlestickPlotView(size: geo.size)
                    }
                    .frame(height: showRSI ? 220 : 260)
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
                        let totalW = CGFloat(visibleBars.count) * stepX
                        let minPan = min(0, plotWidth - totalW)
                        let clampedPan = totalW > plotWidth ? min(0, max(minPan, panOffset)) : 0
                        
                        rsiPlotView(size: geo.size, stepX: stepX, panOffset: clampedPan)
                    }
                    .frame(height: isLandscape ? 85 : 110)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastMagnification
                        lastMagnification = value
                        zoomScale = max(0.6, min(4.0, zoomScale * delta))
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                        let effectiveZoom = max(0.5, min(4.0, zoomScale))
                        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
                        let approxPlotWidth: CGFloat = isLandscape ? 600 : 300
                        let stepX = approxPlotWidth / CGFloat(max(1, slotCount))
                        let totalW = CGFloat(visibleBars.count) * stepX
                        
                        if zoomScale > 1.05 && abs(value.translation.width) > 4 && totalW > approxPlotWidth {
                            let delta = value.translation.width - lastDragX
                            lastDragX = value.translation.width
                            panOffset += delta
                        } else {
                            updateHoveredBar(at: value.location.x, totalWidth: approxPlotWidth, stepX: stepX, panOffset: panOffset)
                        }
                    }
                    .onEnded { _ in
                        lastDragX = 0
                        hoveredBarIndex = nil
                        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
                        let effectiveZoom = max(0.5, min(4.0, zoomScale))
                        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
                        let approxPlotWidth: CGFloat = isLandscape ? 600 : 300
                        let stepX = approxPlotWidth / CGFloat(max(1, slotCount))
                        let totalW = CGFloat(visibleBars.count) * stepX
                        if totalW > approxPlotWidth {
                            let minOffset = approxPlotWidth - totalW
                            panOffset = min(0, max(minOffset, panOffset))
                        } else {
                            panOffset = 0
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    zoomScale = 1.0
                    panOffset = 0.0
                }
            }
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
            )
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
    
    private var currentTrendBias: TrendBias? {
        guard visibleBars.count >= 10 else { return nil }
        return MovingAverageEngine.analyzeTimeframe(bars: visibleBars, timeframe: resolution.rawValue)?.trend
    }
    
    private var hudHeaderView: some View {
        let trend = currentTrendBias
        let hoveredTimeStr: String? = hoveredBarIndex != nil ? activeHoveredBar.map { formatBarTime($0.timestamp) } : nil
        
        return HStack(alignment: .center, spacing: 8) {
            // 1. Symbol
            Text(trade.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppColors.primaryText)
            
            // 2. Trend Capsule Pill (▲ Bullish, ▼ Bearish, ⇄ Pullback)
            if let t = trend {
                let isBull = t == .bullish || t == .strongBullish
                let isBear = t == .bearish || t == .strongBearish
                let color = isBull ? AppColors.profit : (isBear ? AppColors.loss : AppColors.warning)
                
                HStack(spacing: 4) {
                    Text(isBull ? "▲" : (isBear ? "▼" : "⇄"))
                        .font(.system(size: 8.5, weight: .bold))
                    Text(t.label.replacingOccurrences(of: " ▲▲", with: "")
                                .replacingOccurrences(of: " ▲", with: "")
                                .replacingOccurrences(of: " ▼▼", with: "")
                                .replacingOccurrences(of: " ▼", with: "")
                                .replacingOccurrences(of: " ⇄", with: "")
                                .replacingOccurrences(of: " ▬", with: ""))
                        .font(.system(size: 9.5, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(color.opacity(0.12))
                .foregroundColor(color)
                .clipShape(Capsule())
            }
            
            // 3. Hovered Time (if touching/scrubbing candle)
            if let timeStr = hoveredTimeStr {
                Text(timeStr)
                    .font(AppTypography.monoCaption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            // 4. Zoom Indicator (if user pinched)
            if abs(zoomScale - 1.0) > 0.05 {
                Text(String(format: "%.1fx", zoomScale))
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(AppColors.brand.opacity(0.15))
                    .foregroundColor(AppColors.brand)
                    .clipShape(Capsule())
            }
            
            // 5. Minimalist Legend Dots (EMA 21 cyan, EMA 50 orange, BSL amber, SSL mint)
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.85, blue: 1.0))
                        .frame(width: 5, height: 5)
                    Text("EMA 21")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                    Text("EMA 50")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.62, blue: 0.2))
                        .frame(width: 5, height: 5)
                    Text("BSL-H")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.82, blue: 0.95))
                        .frame(width: 5, height: 5)
                    Text("BSL-L")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                if showRSI {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(red: 0.65, green: 0.45, blue: 0.95))
                            .frame(width: 5, height: 5)
                        Text("RSI")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.82, blue: 0.2))
                            .frame(width: 5, height: 5)
                        Text("WMA 45")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
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
        
        let bounds = calculatePriceBounds()
        let minP = bounds.minPrice
        let maxP = bounds.maxPrice
        let priceSpan = max(0.00001, maxP - minP)
        
        // Base slot count scaled by pinch zoom:
        let baseCount = max(visibleBars.count, min(totalBarsCount, 50))
        let effectiveZoom = max(0.5, min(4.0, zoomScale))
        let slotCount = max(8, Double(baseCount) / Double(effectiveZoom))
        let stepX = plotWidth / CGFloat(max(1, slotCount))
        let candleWidth = max(2.5, min(24.0, stepX * 0.7))
        
        let totalContentWidth = CGFloat(visibleBars.count) * stepX
        let minPan = min(0, plotWidth - totalContentWidth)
        let clampedPan = totalContentWidth > plotWidth ? min(0, max(minPan, panOffset)) : 0
        
        return ZStack(alignment: .topLeading) {
            // Grid lines and right price axis
            gridAndPriceAxis(width: plotWidth, height: plotHeight, minP: minP, maxP: maxP, fullWidth: size.width)
            
            // Time axis (bottom) - only shown on candlestick canvas if RSI sub-window is hidden
            if !showRSI {
                timeAxis(width: plotWidth, height: plotHeight, stepX: stepX, fullHeight: size.height, panOffset: clampedPan)
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
                    
                    let rawYHigh = plotHeight - CGFloat((highD - minP) / priceSpan) * plotHeight
                    let rawYLow = plotHeight - CGFloat((lowD - minP) / priceSpan) * plotHeight
                    let rawYOpen = plotHeight - CGFloat((openD - minP) / priceSpan) * plotHeight
                    let rawYClose = plotHeight - CGFloat((closeD - minP) / priceSpan) * plotHeight
                    
                    let yHigh = max(0, min(plotHeight, rawYHigh))
                    let yLow = max(0, min(plotHeight, rawYLow))
                    let yOpen = max(0, min(plotHeight, rawYOpen))
                    let yClose = max(0, min(plotHeight, rawYClose))
                    
                    let color = bar.isUp ? AppColors.profit : AppColors.loss
                    
                    var wickPath = Path()
                    wickPath.move(to: CGPoint(x: centerX, y: yHigh))
                    wickPath.addLine(to: CGPoint(x: centerX, y: yLow))
                    context.stroke(wickPath, with: .color(color), lineWidth: 1.5)
                    
                    let bodyTop = min(yOpen, yClose)
                    let bodyHeight = max(2.5, abs(yClose - yOpen))
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
            
            // Dynamic EMA 21 & EMA 50 Overlay
            if showMarketStructure {
                emaOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan, panOffset: clampedPan)
            }
            
            // Liquidity Overlay (EQH / EQL Pools, Sweeps / SFPs)
            if showLiquidity {
                liquidityOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan, panOffset: clampedPan)
            }
            
            // Unified trade overlay (entry/exit lines, arrows, connecting line)
            tradeOverlay(plotWidth: plotWidth, plotHeight: plotHeight, stepX: stepX, minP: minP, span: priceSpan, panOffset: clampedPan)
            
            if let hIdx = hoveredBarIndex, hIdx < visibleBars.count {
                let hX = CGFloat(hIdx) * stepX + (stepX / 2.0) + clampedPan
                if hX >= 0 && hX <= plotWidth {
                    Rectangle()
                        .fill(AppColors.primaryText.opacity(0.4))
                        .frame(width: 1, height: plotHeight)
                        .position(x: hX, y: plotHeight / 2.0)
                }
            }
            
            // Zoom scale pill indicator (shows dynamically during pinch zoom in landscape)
            if isLandscape && abs(zoomScale - 1.0) > 0.05 {
                Text(String(format: "%.1fx", zoomScale))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.brand.opacity(0.2))
                    .foregroundColor(AppColors.brand)
                    .clipShape(Capsule())
                    .position(x: 32, y: 16)
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
                .font(AppTypography.number(9, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
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
                        .font(AppTypography.number(9, weight: .regular))
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
        let volAreaHeight = plotHeight * 0.18
        
        return ForEach(0..<visibleBars.count, id: \.self) { i in
            let bar = visibleBars[i]
            let v = (bar.volume as NSDecimalNumber).doubleValue
            let barH = CGFloat(v / safeMaxVol) * volAreaHeight
            let x = CGFloat(i) * stepX + (stepX / 2.0) + panOffset
            if x >= -candleWidth && x <= (plotWidth + candleWidth) {
                let y = plotHeight - barH
                Rectangle()
                    .fill((bar.isUp ? AppColors.profit : AppColors.loss).opacity(0.25))
                    .frame(width: max(1.5, candleWidth * 0.8), height: barH)
                    .position(x: x, y: y + barH / 2.0)
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
            
            // 2. Entry marker & label: "EN" xanh không cần giá
            if let entryIdx = entryBarIdx {
                let entryX = CGFloat(entryIdx) * stepX + (stepX / 2.0) + panOffset
                
                Text("EN")
                    .font(.system(size: 8, weight: .black))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(AppColors.profit)
                    .foregroundColor(.white)
                    .cornerRadius(3)
                    .position(x: min(plotWidth - 20, max(20, entryX)), y: max(8, yEntry - 10))
                
                Image(systemName: trade.direction == .long ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundColor(AppColors.profit)
                    .position(x: entryX, y: trade.direction == .long ? yEntry + 8 : yEntry - 8)
            }
            
            // 3. Exit line + label: "EX" đỏ không cần giá + connecting line
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
                
                // Exit badge: "EX" đỏ
                Text("EX")
                    .font(.system(size: 8, weight: .black))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(exitColor)
                    .foregroundColor(.white)
                    .cornerRadius(3)
                    .position(x: min(plotWidth - 20, max(20, exitX)), y: max(8, yExit - 10))
                
                // Exit arrow marker
                Image(systemName: trade.direction == .long ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    .font(.system(size: 8))
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
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
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
    
    // MARK: - 6. Dynamic EMA 21 & EMA 50 Overlay
    
    @ViewBuilder
    private func emaOverlay(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat = 0
    ) -> some View {
        if visibleBars.count >= 10 {
            let ema21 = MovingAverageEngine.calculateEMA(period: 21, bars: visibleBars)
            let ema50 = MovingAverageEngine.calculateEMA(period: 50, bars: visibleBars)
            
            ZStack {
                // 1. EMA 50 (Orange)
                if ema50.count == visibleBars.count {
                    Path { path in
                        for (idx, val) in ema50.enumerated() {
                            let x = CGFloat(idx) * stepX + (stepX / 2.0) + panOffset
                            let pD = (val as NSDecimalNumber).doubleValue
                            let y = plotHeight - CGFloat((pD - minP) / span) * plotHeight
                            let clampedY = max(2, min(plotHeight - 2, y))
                            if idx == 0 { path.move(to: CGPoint(x: x, y: clampedY)) }
                            else { path.addLine(to: CGPoint(x: x, y: clampedY)) }
                        }
                    }
                    .stroke(Color.orange.opacity(0.85), lineWidth: 1.2)
                }
                
                // 2. EMA 21 (Cyan)
                if ema21.count == visibleBars.count {
                    Path { path in
                        for (idx, val) in ema21.enumerated() {
                            let x = CGFloat(idx) * stepX + (stepX / 2.0) + panOffset
                            let pD = (val as NSDecimalNumber).doubleValue
                            let y = plotHeight - CGFloat((pD - minP) / span) * plotHeight
                            let clampedY = max(2, min(plotHeight - 2, y))
                            if idx == 0 { path.move(to: CGPoint(x: x, y: clampedY)) }
                            else { path.addLine(to: CGPoint(x: x, y: clampedY)) }
                        }
                    }
                    .stroke(Color.cyan.opacity(0.9), lineWidth: 1.4)
                }
            }
        }
    }
    
    // MARK: - 7. Institutional Liquidity Overlay (Resting Pools & SFP Sweeps)
    
    @ViewBuilder
    private func liquidityOverlay(
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        stepX: CGFloat,
        minP: Double,
        span: Double,
        panOffset: CGFloat = 0
    ) -> some View {
        if visibleBars.count >= 5 {
            let curPrice = visibleBars.last?.close ?? 0
            let pivots = LiquidityEngine.identifyPivots(bars: visibleBars, window: 2, timeframe: resolution.label)
            let simResult = LiquidityEngine.simulate(
                bars: visibleBars,
                pivots: pivots,
                sessionBarsCount: visibleBars.count
            )
            
            // Priority filtering: active pools, limit to top 2 closest BSL and top 2 closest SSL
            let topBSL = Array(simResult.restingBuySide.filter { $0.price > curPrice }.prefix(2))
            let topSSL = Array(simResult.restingSellSide.filter { $0.price < curPrice }.prefix(2))
            let displayPools = topBSL + topSSL
            
            ZStack {
                // 1. Resting Liquidity Pools (Bounded Levels & Clustered Zones)
                ForEach(displayPools) { pool in
                    let pD = (pool.price as NSDecimalNumber).doubleValue
                    let rawY = plotHeight - CGFloat((pD - minP) / span) * plotHeight
                    let clampedY = max(8, min(plotHeight - 8, rawY))
                    
                    let isBuySide = pool.type == .buySide
                    let poolColor = isBuySide ? Color(red: 1.0, green: 0.62, blue: 0.2) : Color(red: 0.2, green: 0.82, blue: 0.95)
                    let poolLabel = isBuySide ? "BSL-H" : "BSL-L"
                    
                    // Zone rectangle if rangeMin != rangeMax (e.g. EQH/EQL clusters)
                    if pool.rangeMin != pool.rangeMax {
                        let topD = (pool.topPrice as NSDecimalNumber).doubleValue
                        let botD = (pool.bottomPrice as NSDecimalNumber).doubleValue
                        let topY = plotHeight - CGFloat((topD - minP) / span) * plotHeight
                        let botY = plotHeight - CGFloat((botD - minP) / span) * plotHeight
                        let zoneH = max(2, abs(botY - topY))
                        let zoneMinY = min(topY, botY)
                        
                        Rectangle()
                            .fill(poolColor.opacity(0.10))
                            .frame(width: plotWidth, height: zoneH)
                            .position(x: plotWidth / 2.0, y: zoneMinY + zoneH / 2.0)
                    }
                    
                    // Horizontal dashed pool line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: clampedY))
                        path.addLine(to: CGPoint(x: plotWidth, y: clampedY))
                    }
                    .stroke(poolColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))
                    
                    // Pool tag badge
                    Text(poolLabel)
                        .font(.system(size: 7.5, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(poolColor.opacity(0.18))
                        .foregroundColor(poolColor)
                        .cornerRadius(3)
                        .position(x: min(plotWidth - 50, max(50, plotWidth - 55)), y: max(10, clampedY - 8))
                }
                
                // 2. Liquidity Sweeps (Discrete SFP Markers)
                ForEach(Array(simResult.sweeps.prefix(6))) { sweep in
                    if sweep.barIndex < visibleBars.count {
                        let x = CGFloat(sweep.barIndex) * stepX + (stepX / 2.0) + panOffset
                        if x >= 0 && x <= plotWidth {
                            let isHighSweep = sweep.sweepType == .buySideSwept
                            let wickD = (sweep.wickExtreme as NSDecimalNumber).doubleValue
                            let rawY = plotHeight - CGFloat((wickD - minP) / span) * plotHeight
                            let clampedY = max(8, min(plotHeight - 8, rawY))
                            
                            let sweepColor = isHighSweep ? Color(red: 1.0, green: 0.55, blue: 0.2) : Color(red: 0.2, green: 0.85, blue: 0.6)
                            
                            VStack(spacing: 1) {
                                if isHighSweep {
                                    Text("SW")
                                        .font(.system(size: 6.5, weight: .black))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(sweepColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(2)
                                    Image(systemName: "arrowtriangle.down.fill")
                                        .font(.system(size: 5))
                                        .foregroundColor(sweepColor)
                                } else {
                                    Image(systemName: "arrowtriangle.up.fill")
                                        .font(.system(size: 5))
                                        .foregroundColor(sweepColor)
                                    Text("SW")
                                        .font(.system(size: 6.5, weight: .black))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(sweepColor)
                                        .foregroundColor(.white)
                                        .cornerRadius(2)
                                }
                            }
                            .position(x: x, y: isHighSweep ? max(10, clampedY - 12) : min(plotHeight - 10, clampedY + 12))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 8. RSI Sub-Window View & Plot
    
    private var rsiSeries: [Double?] {
        let reference = allBars.isEmpty ? visibleBars : allBars
        return MomentumEngine.computeRSISeries(bars: reference, period: 14)
    }
    
    private var visibleRsi: [Double?] {
        Array(rsiSeries.prefix(visibleBars.count))
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
            
            // 2. WMA 45 Curve of RSI 14 (Gold / Amber)
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
            
            // 3. Active / Hovered dot and cursor line
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
