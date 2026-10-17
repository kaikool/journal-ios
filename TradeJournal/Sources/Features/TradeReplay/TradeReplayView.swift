import SwiftUI

/// Trade Replay screen to review historical candlesticks and execution progression step-by-step.
/// Ported 1:1 from `trade-market-data.tsx`, `trade-replay.ts`, and `excursions.ts`.
/// Adheres strictly to Apple HIG with crisp typography and smooth playback controls.
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
    @State private var selectedResolution: MarketResolution = .m15
    @State private var replaySpeed: Double = 2.0
    @State private var excursionEstimate: ExcursionEstimate? = nil
    
    public init(trade: Trade, executions: [Execution]) {
        self.trade = trade
        self.executions = executions
        let durationMs = trade.durationMs ?? (trade.closedAt != nil ? Int64(trade.closedAt!.timeIntervalSince(trade.openedAt) * 1000) : 3_600_000)
        let minutes = Double(max(60_000, durationMs)) / 60_000.0
        let res: MarketResolution = {
            if minutes <= 90 { return .m1 }
            if minutes <= 60 * 8 { return .m5 }
            if minutes <= 60 * 48 { return .m15 }
            if minutes <= 60 * 24 * 10 { return .h1 }
            return .d1
        }()
        self._selectedResolution = State(initialValue: res)
    }
    
    private var frame: ReplayFrame {
        TradeReplayEngine.frame(
            bars: bars,
            fills: executions,
            trade: trade,
            barIndex: currentStep,
            resolution: selectedResolution
        )
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header: Trade info and dynamic replay P&L
                headerCard
                
                // Timeframe Selector: 1m, 5m, 15m, 1h, 1d
                resolutionSelectorBar
                
                // Professional Candlestick Chart
                chartCard
                
                // Replay Playback Controls (Play/Pause, Step, Speed)
                playbackControlsCard
                
                // MAE & MFE Excursion Statistics
                excursionMetricsCard
                
                // Broker Data Notes
                dataCoverageNote
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Trade Replay")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(trade.id)_\(selectedResolution.rawValue)") {
            await loadMarketCandles()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    // MARK: - 1. Header Card
    
    private var headerCard: some View {
        AppCard {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Text(trade.symbol)
                            .font(AppTypography.headline)
                        
                        AppBadge(
                            text: trade.direction.rawValue.uppercased(),
                            color: trade.direction == .long ? AppColors.profit : AppColors.loss
                        )
                        
                        if !dataSourceName.isEmpty {
                            AppBadge(text: dataSourceName, color: AppColors.accent)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("UNREALIZED P&L")
                            .font(AppTypography.cardTitle)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text(Formatters.formatPnL(frame.unrealizedPnl, currency: env.currentCurrency))
                            .font(AppTypography.financialNumber(size: 18, weight: .bold))
                            .foregroundColor(Formatters.pnlColor(frame.unrealizedPnl))
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                HStack {
                    Text("Entry: \(Formatters.price(trade.avgEntry)) • Qty: \(Formatters.formatNumber(trade.quantity))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    if let curBar = frame.currentBar {
                        Text("Bar Close: \(Formatters.price(curBar.close))")
                            .font(AppTypography.captionBold)
                            .foregroundColor(curBar.isUp ? AppColors.profit : AppColors.loss)
                    }
                }
            }
        }
    }
    
    // MARK: - 2. Timeframe Resolution Selector (1m, 5m, 15m, 1h, 1d)
    
    private var resolutionSelectorBar: some View {
        HStack(spacing: 8) {
            Text("Resolution:")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            
            ForEach(MarketResolution.allCases) { res in
                let isSelected = res == selectedResolution
                Button {
                    guard selectedResolution != res else { return }
                    selectedResolution = res
                } label: {
                    Text(res.rawValue)
                        .font(AppTypography.pill)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isSelected ? AppColors.accent : AppColors.secondaryBackground)
                        .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            if isLoadingCandles {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading…")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - 3. Candlestick Chart Card
    
    private var chartCard: some View {
        VStack(spacing: 8) {
            if !candleErrorMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppColors.warning)
                    Text(candleErrorMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                }
                .padding(8)
                .background(AppColors.secondaryBackground)
                .cornerRadius(6)
            }
            
            CandleChartView(
                visibleBars: frame.visibleBars,
                totalBarsCount: bars.count,
                trade: trade,
                executions: executions,
                throughTimestamp: frame.throughTimestamp,
                unrealizedPnl: frame.unrealizedPnl,
                timeZone: env.currentTimeZone,
                currency: env.currentCurrency
            )
        }
    }
    
    // MARK: - 4. Playback Controls Card
    
    private var playbackControlsCard: some View {
        AppCard {
            VStack(spacing: 12) {
                // Scrubber Slider
                if bars.count > 1 {
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { Double(currentStep) },
                                set: {
                                    currentStep = Int($0)
                                    pauseReplay()
                                }
                            ),
                            in: 1...Double(bars.count),
                            step: 1
                        )
                        .tint(AppColors.accent)
                    }
                }
                
                // Playback controls row
                HStack(spacing: 16) {
                    // Restart
                    Button(action: { resetReplay() }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                    }
                    .disabled(bars.isEmpty)
                    
                    // Step back
                    Button(action: { step(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(currentStep <= 1 ? AppColors.secondaryText.opacity(0.3) : AppColors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                    }
                    .disabled(currentStep <= 1 || bars.isEmpty)
                    
                    // Play / Pause
                    Button(action: { togglePlay() }) {
                        HStack(spacing: 6) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                            Text(isPlaying ? "Pause" : "Play")
                                .font(AppTypography.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .disabled(bars.isEmpty)
                    
                    // Step forward
                    Button(action: { step(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(currentStep >= bars.count ? AppColors.secondaryText.opacity(0.3) : AppColors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                    }
                    .disabled(currentStep >= bars.count || bars.isEmpty)
                    
                    // Forward to end
                    Button(action: { forwardToEnd() }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                    }
                    .disabled(bars.isEmpty)
                    
                    Spacer()
                    
                    // Replay Speed menu
                    Menu {
                        Button("1×") { replaySpeed = 1.0; restartTimerIfPlaying() }
                        Button("2×") { replaySpeed = 2.0; restartTimerIfPlaying() }
                        Button("4×") { replaySpeed = 4.0; restartTimerIfPlaying() }
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(Int(replaySpeed))×")
                                .font(AppTypography.captionBold)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryBackground)
                        .foregroundColor(AppColors.primaryText)
                        .cornerRadius(6)
                    }
                }
                
                // Timestamp and count caption
                if let curBar = frame.currentBar {
                    let formattedTime = Formatters.formatDateTime(curBar.date, timeZone: env.currentTimeZone)
                    HStack {
                        Text("\(currentStep) / \(bars.count) candles • Through: \(formattedTime)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - 5. Excursion Metrics (MAE / MFE)
    
    private var excursionMetricsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("EXCURSION ESTIMATES (MAE & MFE)")
                    .font(AppTypography.cardTitle)
                    .foregroundColor(AppColors.secondaryText)
                
                HStack(spacing: 12) {
                    // MAE
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated MAE · adverse")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        if let mae = excursionEstimate?.mae {
                            Text(Formatters.formatCurrency(mae, currency: env.currentCurrency))
                                .font(AppTypography.financialNumber(size: 16, weight: .bold))
                                .foregroundColor(AppColors.loss)
                        } else {
                            Text("Unavailable")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 36)
                    
                    // MFE
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated MFE · favorable")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        if let mfe = excursionEstimate?.mfe {
                            Text(Formatters.formatCurrency(mfe, currency: env.currentCurrency))
                                .font(AppTypography.financialNumber(size: 16, weight: .bold))
                                .foregroundColor(AppColors.profit)
                        } else {
                            Text("Unavailable")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    // MARK: - 6. Data Coverage Note
    
    private var dataCoverageNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Data coverage & estimate limits:")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.secondaryText)
            
            Text("Candles are revealed at bar close; this is not a tick-by-tick simulation. Excursion estimates use observed candles only.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText.opacity(0.8))
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Replay Actions & Data Loading
    
    private func loadMarketCandles() async {
        isLoadingCandles = true
        candleErrorMessage = ""
        stopTimer()
        
        do {
            let (provider, fetchedBars) = try await MarketDataService.shared.fetchBarsForTrade(
                trade: trade,
                config: TradeDataStore.shared.marketConnections,
                resolution: selectedResolution.rawValue
            )
            
            if !fetchedBars.isEmpty {
                self.bars = fetchedBars
                self.dataSourceName = provider
                self.currentStep = min(10, fetchedBars.count)
                self.excursionEstimate = TradeReplayEngine.estimateExcursions(
                    trade: trade,
                    fills: executions,
                    bars: fetchedBars,
                    resolution: selectedResolution
                )
            } else {
                let simulated = TradeReplayEngine.generateBarsFromTrade(
                    trade: trade,
                    fills: executions,
                    resolution: selectedResolution
                )
                self.bars = simulated
                self.dataSourceName = "Price Path Replay"
                self.currentStep = min(6, simulated.count)
                self.excursionEstimate = TradeReplayEngine.estimateExcursions(
                    trade: trade,
                    fills: executions,
                    bars: simulated,
                    resolution: selectedResolution
                )
            }
        } catch {
            let simulated = TradeReplayEngine.generateBarsFromTrade(
                trade: trade,
                fills: executions,
                resolution: selectedResolution
            )
            self.bars = simulated
            self.dataSourceName = "Execution Path"
            self.currentStep = min(6, simulated.count)
            self.excursionEstimate = TradeReplayEngine.estimateExcursions(
                trade: trade,
                fills: executions,
                bars: simulated,
                resolution: selectedResolution
            )
        }
        isLoadingCandles = false
    }
    
    private func togglePlay() {
        if isPlaying {
            pauseReplay()
        } else {
            startReplay()
        }
    }
    
    private func startReplay() {
        guard !bars.isEmpty else { return }
        if currentStep >= bars.count {
            currentStep = 1
        }
        isPlaying = true
        startTimer()
    }
    
    private func pauseReplay() {
        isPlaying = false
        stopTimer()
    }
    
    private func startTimer() {
        stopTimer()
        let interval = 0.5 / replaySpeed
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                if self.currentStep < self.bars.count {
                    self.currentStep += 1
                } else {
                    self.pauseReplay()
                }
            }
        }
    }
    
    private func restartTimerIfPlaying() {
        if isPlaying {
            startTimer()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func step(by delta: Int) {
        pauseReplay()
        currentStep = max(1, min(bars.count, currentStep + delta))
    }
    
    private func resetReplay() {
        pauseReplay()
        currentStep = 1
    }
    
    private func forwardToEnd() {
        pauseReplay()
        currentStep = bars.count
    }
}

/// Wrapper view for Trade Replay allowing selection of any filtered trade in the account
public struct TradeReplayHubView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @State private var selectedTradeId: String = ""
    
    public init() {}
    
    private var trades: [Trade] {
        dataStore.filteredTrades
    }
    
    private var activeTrade: Trade? {
        if let found = trades.first(where: { $0.id == selectedTradeId }) {
            return found
        }
        return trades.first
    }
    
    private var tradeExecutions: [Execution] {
        guard let t = activeTrade else { return [] }
        return dataStore.executions.filter { t.executionIds.contains($0.id) }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if trades.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.secondaryText.opacity(0.6))
                    Text("No Trades to Replay")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Text("Import trades or sync your account to view candle replays.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            } else {
                // Select Trade Card
                AppCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SELECT TRADE TO REPLAY")
                            .font(AppTypography.cardTitle)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Picker("Trade", selection: Binding(
                            get: { activeTrade?.id ?? "" },
                            set: { selectedTradeId = $0 }
                        )) {
                            ForEach(trades) { t in
                                let sign = t.netPnl >= 0 ? "+" : ""
                                Text("\(t.symbol) - \(t.direction.rawValue.uppercased()) (\(sign)\(Formatters.currency(t.netPnl)))")
                                    .tag(t.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                
                if let trade = activeTrade {
                    TradeReplayView(trade: trade, executions: tradeExecutions)
                        .id(trade.id)
                }
            }
        }
        .background(AppColors.background.ignoresSafeArea())
    }
}
