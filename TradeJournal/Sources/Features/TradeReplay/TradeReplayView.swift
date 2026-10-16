import SwiftUI
import Charts

public struct TradeReplayView: View {
    @EnvironmentObject private var env: AppEnvironment
    let trade: Trade
    let executions: [Execution]
    
    @State private var bars: [MarketBar] = []
    @State private var currentStep: Int = 1
    @State private var isPlaying: Bool = false
    @State private var timer: Timer? = nil
    @State private var dataSourceName: String = ""
    @State private var isLoadingCandles: Bool = false
    @State private var candleErrorMessage: String = ""
    
    public init(trade: Trade, executions: [Execution]) {
        self.trade = trade
        self.executions = executions
    }
    
    private var frame: ReplayFrame {
        TradeReplayEngine.frame(
            bars: bars,
            fills: executions,
            trade: trade,
            barIndex: currentStep,
            barDurationMs: 60_000
        )
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header: Trade info and floating PnL
            AppCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(trade.symbol)
                                .font(AppTypography.headline)
                            AppBadge(
                                text: trade.direction.rawValue.uppercased(),
                                color: trade.direction == .long ? AppColors.profit : AppColors.loss
                            )
                            if !dataSourceName.isEmpty {
                                AppBadge(
                                    text: dataSourceName,
                                    color: AppColors.accent
                                )
                            }
                        }
                        Text("Vào lệnh: \(trade.avgEntry) • KL: \(trade.quantity)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("P&L Tạm Tính")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(frame.unrealizedPnl, currency: env.currentCurrency))
                            .font(AppTypography.headline.bold())
                            .foregroundColor(Formatters.pnlColor(frame.unrealizedPnl))
                    }
                }
            }
            
            // Replay Chart View
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if isLoadingCandles {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Đang tải nến lịch sử từ sàn...")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        } else {
                            Text("Nến hiện tại: \(currentStep) / \(bars.count)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        if let lastBar = frame.visibleBars.last {
                            Text("Giá: \(lastBar.close)")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                    }
                    
                    if !candleErrorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.warning)
                            Text(candleErrorMessage)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(6)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                    }
                    
                    if frame.visibleBars.isEmpty {
                        EmptyStateView(
                            icon: "waveform.path.ecg",
                            title: "Đang tải dữ liệu nến",
                            message: "Chuẩn bị nến lịch sử cho quá trình Replay."
                        )
                        .frame(height: 220)
                    } else {
                        Chart {
                            // Entry baseline
                            RuleMark(y: .value("Entry", (trade.avgEntry as NSDecimalNumber).doubleValue))
                                .foregroundStyle(AppColors.accent)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .annotation(position: .leading) {
                                    Text("Entry")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(AppColors.accent)
                                }
                            
                            ForEach(frame.visibleBars) { bar in
                                let o = (bar.open as NSDecimalNumber).doubleValue
                                let c = (bar.close as NSDecimalNumber).doubleValue
                                let h = (bar.high as NSDecimalNumber).doubleValue
                                let l = (bar.low as NSDecimalNumber).doubleValue
                                let isUp = c >= o
                                
                                BarMark(
                                    x: .value("Index", bar.timestamp),
                                    yStart: .value("Low", l),
                                    yEnd: .value("High", h),
                                    width: 1.5
                                )
                                .foregroundStyle(isUp ? AppColors.profit : AppColors.loss)
                                
                                BarMark(
                                    x: .value("Index", bar.timestamp),
                                    yStart: .value("Open", o),
                                    yEnd: .value("Close", c),
                                    width: 8
                                )
                                .foregroundStyle(isUp ? AppColors.profit : AppColors.loss)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis(.hidden)
                        .frame(height: 220)
                    }
                    
                    // Slider scrubber
                    if bars.count > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(currentStep) },
                                set: { currentStep = Int($0) }
                            ),
                            in: 1...Double(bars.count),
                            step: 1
                        )
                        .tint(AppColors.accent)
                    }
                    
                    // Playback Controls
                    HStack(spacing: 20) {
                        Button(action: { resetReplay() }) {
                            Image(systemName: "backward.end.fill")
                                .font(.title3)
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Button(action: { step(by: -1) }) {
                            Image(systemName: "backward.fill")
                                .font(.title3)
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Button(action: { togglePlay() }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 38))
                                .foregroundColor(AppColors.accent)
                        }
                        
                        Button(action: { step(by: 1) }) {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Button(action: { forwardToEnd() }) {
                            Image(systemName: "forward.end.fill")
                                .font(.title3)
                                .foregroundColor(AppColors.primaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Trade Replay")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.background)
        .task {
            await loadMarketCandles()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Market Data & Replay Actions
    
    private func loadMarketCandles() async {
        guard bars.isEmpty else { return }
        isLoadingCandles = true
        candleErrorMessage = ""
        
        do {
            let (provider, fetchedBars) = try await MarketDataService.shared.fetchBarsForTrade(
                trade: trade,
                config: TradeDataStore.shared.marketConnections
            )
            if !fetchedBars.isEmpty {
                self.bars = fetchedBars
                self.dataSourceName = provider
                self.currentStep = min(5, fetchedBars.count)
            } else {
                candleErrorMessage = "Không có nến lịch sử từ sàn. Đang dùng mô phỏng."
                generateSyntheticBarsFallback()
            }
        } catch {
            candleErrorMessage = "\(error.localizedDescription) • Đang dùng mô phỏng."
            generateSyntheticBarsFallback()
        }
        isLoadingCandles = false
    }
    
    private func togglePlay() {
        if isPlaying {
            isPlaying = false
            timer?.invalidate()
            timer = nil
        } else {
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                if currentStep < bars.count {
                    currentStep += 1
                } else {
                    isPlaying = false
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }
    
    private func step(by delta: Int) {
        currentStep = max(1, min(bars.count, currentStep + delta))
    }
    
    private func resetReplay() {
        currentStep = 1
        isPlaying = false
        timer?.invalidate()
    }
    
    private func forwardToEnd() {
        currentStep = bars.count
        isPlaying = false
        timer?.invalidate()
    }
    
    /// Dự phòng mô phỏng khi chưa có mạng hoặc chưa nhập OANDA
    private func generateSyntheticBarsFallback() {
        guard bars.isEmpty else { return }
        self.dataSourceName = "Mô phỏng nội suy"
        
        let entryPrice = (trade.avgEntry as NSDecimalNumber).doubleValue
        let exitPrice = ((trade.avgExit ?? trade.avgEntry) as NSDecimalNumber).doubleValue
        let startTime = Int64(trade.openedAt.timeIntervalSince1970 * 1000)
        let totalBars = 30
        
        var generated: [MarketBar] = []
        var currentPrice = entryPrice
        let priceStep = (exitPrice - entryPrice) / Double(totalBars)
        
        for i in 0..<totalBars {
            let t = startTime + Int64(i * 60_000)
            let wiggle = (Double(i % 3) - 1.0) * (abs(exitPrice - entryPrice) * 0.15 + 0.5)
            let open = currentPrice
            let close = currentPrice + priceStep + wiggle
            let high = max(open, close) + abs(wiggle) * 0.5 + 0.2
            let low = min(open, close) - abs(wiggle) * 0.5 - 0.2
            currentPrice = close
            
            generated.append(MarketBar(
                timestamp: t,
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: Decimal(100)
            ))
        }
        
        self.bars = generated
        self.currentStep = min(5, generated.count)
    }
}
