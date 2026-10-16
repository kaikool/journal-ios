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
                        VStack(spacing: 12) {
                            EmptyStateView(
                                icon: isLoadingCandles ? "waveform.path.ecg" : "chart.line.uptrend.xyaxis",
                                title: isLoadingCandles ? "Đang tải nến lịch sử" : "Chưa có dữ liệu nến",
                                message: isLoadingCandles ? "Đang kết nối sàn giao dịch để tải nến cho \(trade.symbol)..." : (candleErrorMessage.isEmpty ? "Không có dữ liệu nến từ sàn giao dịch." : candleErrorMessage)
                            )
                            if !isLoadingCandles {
                                Button {
                                    Task { await loadMarketCandles() }
                                } label: {
                                    Label("Tải lại nến", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
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
                candleErrorMessage = "Sàn giao dịch (\(provider)) không có dữ liệu nến cho khoảng thời gian vào lệnh này."
            }
        } catch {
            candleErrorMessage = error.localizedDescription
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
}
