import SwiftUI

/// Trade Replay screen to review historical candlesticks and execution progression step-by-step.
/// Ported 1:1 from `trade-market-data.tsx`, `trade-replay.ts`, and `excursions.ts`.
/// Adheres strictly to Apple HIG with crisp typography and smooth playback controls.
public struct TradeReplayView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    public let isModal: Bool
    let trade: Trade
    let executions: [Execution]

    public static let replayResolutions: [MarketResolution] = [.m15, .h1, .h4]

    @State private var bars: [MarketBar] = []
    @State private var rawSourceBars: [MarketBar] = []
    @State private var currentStep: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playbackTask: Task<Void, Never>? = nil
    @State private var isLoadingCandles: Bool = true
    @State private var candleErrorMessage: String = ""
    @State private var selectedResolution: MarketResolution = .m15
    @State private var replaySpeed: Double = 2.0
    @State private var excursionEstimate: ExcursionEstimate? = nil
    @State private var showMarketStructure: Bool = true
    @State private var showRSI: Bool = true
    @State private var showLandscapeChart: Bool = false
    @State private var keyLevels: [KeyLevel] = []
    @State private var sessionProfiles: [SessionProfileSnapshot] = []
    @State private var developingProfile: DevelopingProfile? = nil
    @State private var developingProfiles: [DevelopingProfile] = []
    @State private var priceActionPatterns: [DetectedCandlePattern] = []
    @State private var isChartInteracting: Bool = false

    public init(trade: Trade, executions: [Execution], isModal: Bool = false) {
        self.trade = trade
        self.executions = executions
        self.isModal = isModal
        let durationMs = trade.durationMs ?? (trade.closedAt.map { Int64($0.timeIntervalSince(trade.openedAt) * 1000) } ?? 3_600_000)
        let minutes = Double(max(60_000, durationMs)) / 60_000.0
        let res: MarketResolution = {
            if minutes <= 60 * 48 { return .m15 }
            if minutes <= 60 * 24 * 14 { return .h1 }
            return .h4
        }()

        let cached = TradeReplayCacheStore.shared.getBars(for: trade.id, resolution: res.rawValue) ?? []
        if !cached.isEmpty {
            self._selectedResolution = State(initialValue: res)
            self._bars = State(initialValue: cached)
            self._rawSourceBars = State(initialValue: cached)
            self._currentStep = State(initialValue: cached.count)
            self._isLoadingCandles = State(initialValue: false)
            self._excursionEstimate = State(initialValue: TradeReplayEngine.estimateExcursions(
                trade: trade,
                fills: executions,
                bars: cached,
                resolution: res
            ))
        } else {
            self._selectedResolution = State(initialValue: res)
            self._bars = State(initialValue: [])
            self._rawSourceBars = State(initialValue: [])
            self._currentStep = State(initialValue: 0)
            self._isLoadingCandles = State(initialValue: true)
            self._excursionEstimate = State(initialValue: nil)
        }
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
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        // Header: Trade info and dynamic replay P&L
                        TradeReplayHeaderCard(
                            trade: trade,
                            frame: frame,
                            bars: bars,
                            currentStep: currentStep,
                            isLoadingCandles: isLoadingCandles,
                            reportingCurrency: env.currentCurrency
                        )

                        // Professional Candlestick Chart (with integrated 15m/1h/4h timeframe selector and pure gesture pinch-zoom)
                        chartCard

                        // Replay Playback Controls (Play/Pause, Step, Speed, Fullscreen)
                        TradeReplayControlsCard(
                            currentStep: $currentStep,
                            replaySpeed: $replaySpeed,
                            isPlaying: isPlaying,
                            barsCount: bars.count,
                            currentBar: frame.currentBar,
                            isLoadingCandles: isLoadingCandles,
                            timeZone: env.currentTimeZone,
                            onTogglePlay: togglePlay,
                            onStep: { delta in step(by: delta) },
                            onReset: resetReplay,
                            onForwardToEnd: forwardToEnd,
                            onSpeedChanged: restartTimerIfPlaying,
                            onOpenLandscape: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showLandscapeChart = true
                                }
                            }
                        )

                        // MAE & MFE Excursion Statistics
                        TradeReplayExcursionCard(
                            excursionEstimate: excursionEstimate,
                            isLoadingCandles: isLoadingCandles,
                            barsCount: bars.count,
                            reportingCurrency: env.currentCurrency
                        )

                        // Broker Data Notes
                        dataCoverageNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
                .scrollDisabled(isChartInteracting)
                .scrollDismissesKeyboard(.interactively)
                .background(AppColors.background)
                .navigationTitle("Replay - \(trade.symbol)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ModalDismissButton { dismiss() }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        ModalPrimaryButton("Done") { dismiss() }
                    }
                }
            }

            if showLandscapeChart {
                TradeReplayLandscapeChartView(
                    trade: trade,
                    executions: executions,
                    currentStep: $currentStep,
                    replaySpeed: $replaySpeed,
                    selectedResolution: $selectedResolution,
                    showMarketStructure: $showMarketStructure,
                    showRSI: $showRSI,
                    bars: bars,
                    frame: frame,
                    isPlaying: isPlaying,
                    isLoadingCandles: isLoadingCandles,
                    reportingCurrency: env.currentCurrency,
                    timeZone: env.currentTimeZone,
                    keyLevels: keyLevels,
                    sessionProfiles: sessionProfiles,
                    developingProfile: developingProfile,
                    developingProfiles: developingProfiles,
                    patterns: priceActionPatterns,
                    onTogglePlay: togglePlay,
                    onStep: { delta in step(by: delta) },
                    onReset: resetReplay,
                    onForwardToEnd: forwardToEnd,
                    onSpeedChanged: restartTimerIfPlaying,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showLandscapeChart = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .task(id: "\(trade.id)_\(selectedResolution.rawValue)") {
            await loadMarketCandles()
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: - Candlestick Chart Card
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
                .appSubCardStyle(cornerRadius: 6, padding: 8)
            }

            if isLoadingCandles && bars.isEmpty {
                LoadingView("Fetching candles for \(trade.symbol) (\(selectedResolution == .d1 ? "1D" : selectedResolution.rawValue))", size: 64)
                    .frame(height: 270)
                    .appCardStyle(cornerRadius: 16)
            } else if bars.isEmpty {
                AppEmptyState(
                    icon: "chart.xyaxis.line",
                    title: "No Candle Data Available",
                    message: "Market data could not be retrieved for \(trade.symbol)"
                )
                .frame(height: 270)
                .appCardStyle(cornerRadius: 16)
            } else {
                ZStack(alignment: .topTrailing) {
                    CandleChartView(
                        visibleBars: frame.visibleBars,
                        allBars: bars,
                        totalBarsCount: bars.count,
                        trade: trade,
                        executions: executions,
                        throughTimestamp: frame.throughTimestamp,
                        unrealizedPnl: frame.unrealizedPnl,
                        timeZone: env.currentTimeZone,
                        currency: env.currentCurrency,
                        resolution: selectedResolution,
                        showMarketStructure: true,
                        showRSI: true,
                        keyLevels: keyLevels,
                        sessionProfiles: sessionProfiles,
                        developingProfile: developingProfile,
                        developingProfiles: developingProfiles,
                        patterns: priceActionPatterns,
                        onResolutionChange: { newRes in
                            self.selectedResolution = newRes
                        },
                        onInteractionChanged: { isInteracting in
                            isChartInteracting = isInteracting
                        }
                    )

                    if isLoadingCandles {
                        HStack(spacing: 8) {
                            AppBadge("Updating...", variant: .secondary)
                            Spacer()
                        }
                        .padding(8)
                    }
                }
            }
        }
    }

    // MARK: - Data Coverage Note
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
        stopTimer()

        let isOpenTrade = (trade.status == .open || trade.closedAt == nil)

        // 1. Check local disk cache for this exact resolution ONLY if trade is fully closed
        if !isOpenTrade,
           let cached = TradeReplayCacheStore.shared.getBars(for: trade.id, resolution: selectedResolution.rawValue),
           cached.count >= 40 {
            self.bars = cached
            self.currentStep = cached.count
            self.excursionEstimate = TradeReplayEngine.estimateExcursions(
                trade: trade,
                fills: executions,
                bars: cached,
                resolution: selectedResolution
            )
            persistExcursionsIfCalculated(self.excursionEstimate)
            await updateFootprintAndPatterns(for: cached)
            self.isLoadingCandles = false
            return
        }

        isLoadingCandles = true
        candleErrorMessage = ""

        do {
            let (_, fetchedBars) = try await MarketDataService.shared.fetchBarsForTrade(
                trade: trade,
                config: TradeDataStore.shared.marketConnections,
                resolution: selectedResolution.rawValue,
                forceRefresh: isOpenTrade
            )

            if !fetchedBars.isEmpty {
                // Auto-align broker server timezone offset and trim to replay window
                // (80 bars before open for market swings and RSI-14 warmup, 15 bars after close)
                let alignedBars = TradeReplayEngine.alignAndTrimBars(
                    bars: fetchedBars,
                    trade: trade,
                    resolution: selectedResolution,
                    preBarsCount: 80,
                    postBarsCount: 15
                )
                self.bars = alignedBars
                self.currentStep = alignedBars.count
                if !isOpenTrade {
                    TradeReplayCacheStore.shared.saveBars(alignedBars, for: trade.id, resolution: selectedResolution.rawValue)
                }
                self.excursionEstimate = TradeReplayEngine.estimateExcursions(
                    trade: trade,
                    fills: executions,
                    bars: alignedBars,
                    resolution: selectedResolution
                )
                persistExcursionsIfCalculated(self.excursionEstimate)
            } else {
                candleErrorMessage = "Real market data unavailable for \(trade.symbol). Displaying simulated estimate."
                applySimulatedBars()
            }
        } catch {
            candleErrorMessage = "Unable to fetch market data: \(error.localizedDescription). Displaying simulated estimate."
            applySimulatedBars()
        }

        await updateFootprintAndPatterns(for: self.bars)
        isLoadingCandles = false
    }

    private func updateFootprintAndPatterns(for activeBars: [MarketBar]) async {
        guard !activeBars.isEmpty else { return }
        let (levels, profiles, dev, devList) = await SessionFootprintCoordinator.shared.loadKeyLevels(for: trade.symbol, recentBars: activeBars)
        let pats = SessionFootprintCoordinator.shared.scanConfluentPatterns(bars: activeBars, keyLevels: levels)
        await MainActor.run {
            self.keyLevels = levels
            self.sessionProfiles = profiles
            self.developingProfile = dev
            self.developingProfiles = devList
            self.priceActionPatterns = pats
        }
    }

    private func applySimulatedBars() {
        let simulated = TradeReplayEngine.generateBarsFromTrade(
            trade: trade,
            fills: executions,
            resolution: selectedResolution
        )
        self.bars = simulated
        self.currentStep = simulated.count
        self.excursionEstimate = TradeReplayEngine.estimateExcursions(
            trade: trade,
            fills: executions,
            bars: simulated,
            resolution: selectedResolution
        )
        persistExcursionsIfCalculated(self.excursionEstimate)
    }

    private func persistExcursionsIfCalculated(_ estimate: ExcursionEstimate?) {
        guard let estimate = estimate, (estimate.mae != nil || estimate.mfe != nil) else { return }
        Task { @MainActor in
            TradeDataStore.shared.updateTradeExcursions(
                key: trade.key,
                mae: estimate.mae,
                mfe: estimate.mfe,
                maePoints: estimate.maePoints,
                mfePoints: estimate.mfePoints
            )
        }
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
        playbackTask = Task { @MainActor in
            while !Task.isCancelled && isPlaying {
                let intervalSeconds = 0.5 / replaySpeed
                let nanoseconds = UInt64(intervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled && isPlaying else { break }
                if self.currentStep < self.bars.count {
                    self.currentStep += 1
                } else {
                    self.pauseReplay()
                    break
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
        playbackTask?.cancel()
        playbackTask = nil
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
