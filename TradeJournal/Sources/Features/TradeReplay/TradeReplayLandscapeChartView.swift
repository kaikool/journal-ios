import SwiftUI

/// Dedicated Fullscreen Landscape Chart View for Trade Replay.
/// Maximizes horizontal chart real estate for deep market structure, EMA trend, and RSI inspection.
public struct TradeReplayLandscapeChartView: View {
    let trade: Trade
    let executions: [Execution]
    @Binding var currentStep: Int
    @Binding var replaySpeed: Double
    @Binding var selectedResolution: MarketResolution
    @Binding var showMarketStructure: Bool
    @Binding var showRSI: Bool
    let bars: [MarketBar]
    let frame: ReplayFrame
    let isPlaying: Bool
    let isLoadingCandles: Bool
    let reportingCurrency: String
    let timeZone: TimeZone
    let onTogglePlay: () -> Void
    let onStep: (Int) -> Void
    let onReset: () -> Void
    let onForwardToEnd: () -> Void
    let onSpeedChanged: () -> Void
    let onDismiss: () -> Void
    
    @State private var isForceLandscape90: Bool = true
    
    public init(
        trade: Trade,
        executions: [Execution],
        currentStep: Binding<Int>,
        replaySpeed: Binding<Double>,
        selectedResolution: Binding<MarketResolution>,
        showMarketStructure: Binding<Bool>,
        showRSI: Binding<Bool>,
        bars: [MarketBar],
        frame: ReplayFrame,
        isPlaying: Bool,
        isLoadingCandles: Bool,
        reportingCurrency: String,
        timeZone: TimeZone,
        onTogglePlay: @escaping () -> Void,
        onStep: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onForwardToEnd: @escaping () -> Void,
        onSpeedChanged: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.trade = trade
        self.executions = executions
        self._currentStep = currentStep
        self._replaySpeed = replaySpeed
        self._selectedResolution = selectedResolution
        self._showMarketStructure = showMarketStructure
        self._showRSI = showRSI
        self.bars = bars
        self.frame = frame
        self.isPlaying = isPlaying
        self.isLoadingCandles = isLoadingCandles
        self.reportingCurrency = reportingCurrency
        self.timeZone = timeZone
        self.onTogglePlay = onTogglePlay
        self.onStep = onStep
        self.onReset = onReset
        self.onForwardToEnd = onForwardToEnd
        self.onSpeedChanged = onSpeedChanged
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        GeometryReader { geo in
            let isNativeLandscape = geo.size.width > geo.size.height
            let rotate = !isNativeLandscape && isForceLandscape90
            let targetWidth = rotate ? geo.size.height : geo.size.width
            let targetHeight = rotate ? geo.size.width : geo.size.height
            
            ZStack {
                VStack(spacing: 6) {
                    // 1. Top Navigation & Info Bar
                    topNavBar
                    
                    // 2. Timeframes & Indicators Bar (Clean two-column layout like Replay)
                    controlsBar
                    
                    // 3. Wide Edge-to-Edge Candlestick Chart
                    chartContainer
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 4. Bottom Center Replay Playback Controller
                    HStack {
                        Spacer()
                        bottomPlayerBar
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .frame(width: targetWidth, height: targetHeight)
                .rotationEffect(rotate ? .degrees(90) : .degrees(0))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(AppColors.background.ignoresSafeArea())
        }
        .statusBarHidden(true)
    }
    
    // MARK: - 1. Top Navigation & Status Bar
    private var topNavBar: some View {
        HStack(spacing: 10) {
            // Dismiss button
            ModalDismissButton {
                onDismiss()
            }
            
            // Symbol & Direction
            Text(trade.symbol)
                .font(AppTypography.rowPrimary)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .fixedSize()
            
            AppBadge(
                text: trade.direction.rawValue.uppercased(),
                color: trade.direction == .long ? AppColors.profit : AppColors.loss
            )
            .fixedSize()
            
            // Unrealized / Realized P&L Badge
            let pnl = frame.unrealizedPnl
            let pnlColor = pnl >= 0 ? AppColors.profit : AppColors.loss
            AppBadge(
                "\(pnl >= 0 ? "+" : "")\(Formatters.formatCurrency(pnl, currency: reportingCurrency))",
                style: pnl >= 0 ? .profit : .loss
            )
            .fixedSize()
            
            Spacer()
            
            // Current candle timestamp
            if let curBar = frame.currentBar {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.formatDateTime(curBar.date, timeZone: timeZone))
                        .font(AppTypography.number(11, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            
            // Orientation flip button (toggles 90° rotation for devices with portrait orientation lock)
            ModalCircleButton(icon: "rotate.right", label: "Toggle Landscape Rotation") {
                isForceLandscape90.toggle()
            }
        }
    }
    
    // MARK: - 2. Timeframes & Indicators Bar
    private var currentTrendBias: TrendBias? {
        guard !bars.isEmpty else { return nil }
        return MovingAverageEngine.analyzeTimeframe(bars: frame.visibleBars, timeframe: selectedResolution.rawValue)?.trend
    }
    
    private var controlsBar: some View {
        HStack(spacing: 8) {
            // Timeframe Resolution Selector
            Text("TF:")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .fixedSize()
            
            AppSegmentedBar(
                selection: $selectedResolution,
                items: TradeReplayView.replayResolutions,
                titleFor: { res in
                    switch res {
                    case .m15: return "15m"
                    case .h1: return "1h"
                    case .h4: return "4h"
                    default: return res.rawValue.uppercased()
                    }
                },
                height: 28
            )
            
            Spacer()
            
            // Trend Regime Pill
            if let t = currentTrendBias {
                let isBull = t == .bullish || t == .strongBullish
                let isBear = t == .bearish || t == .strongBearish
                let color = isBull ? AppColors.profit : (isBear ? AppColors.loss : AppColors.warning)
                let icon = isBull ? "arrow.up" : (isBear ? "arrow.down" : "arrow.left.and.right")
                let cleanLabel = t.label
                    .replacingOccurrences(of: " ▲▲", with: "")
                    .replacingOccurrences(of: " ▲", with: "")
                    .replacingOccurrences(of: " ▼▼", with: "")
                    .replacingOccurrences(of: " ▼", with: "")
                    .replacingOccurrences(of: " ⇄", with: "")
                    .replacingOccurrences(of: " ▬", with: "")
                
                AppBadge(cleanLabel, icon: icon, color: color)
            }
        }
    }
    
    // MARK: - 3. Candlestick Chart Container
    private var chartContainer: some View {
        Group {
            if bars.isEmpty {
                LoadingView("Loading Candles…", size: 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appCardStyle(cornerRadius: 12)
            } else {
                CandleChartView(
                    visibleBars: frame.visibleBars,
                    allBars: bars,
                    totalBarsCount: bars.count,
                    trade: trade,
                    executions: executions,
                    throughTimestamp: frame.throughTimestamp,
                    unrealizedPnl: frame.unrealizedPnl,
                    timeZone: timeZone,
                    currency: reportingCurrency,
                    resolution: selectedResolution,
                    showMarketStructure: true,
                    showRSI: true,
                    isLandscape: true
                )
            }
        }
    }
    
    // MARK: - 4. Bottom Center Replay Playback Controller Capsule
    private var bottomPlayerBar: some View {
        AppFloatingBar {
            // Reset to beginning
            ModalCircleButton(icon: "backward.end.fill", action: {
                        NativeHaptics.lightImpact()
                        onReset()
                    })
            .disabled(bars.isEmpty)
            .accessibilityLabel("Reset Replay")
            
            // Step back 1 bar
            ModalCircleButton(icon: "chevron.left", action: {
                NativeHaptics.lightImpact()
                onStep(-1)
            })
            .disabled(currentStep <= 1 || bars.isEmpty)
            .accessibilityLabel("Step Backward")
            
            // Play / Pause (Large central button)
            ModalCircleButton(icon: isPlaying ? "pause.fill" : "play.fill", action: {
                        NativeHaptics.mediumImpact()
                        onTogglePlay()
                    })
            .disabled(bars.isEmpty)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            
            // Step forward 1 bar
            ModalCircleButton(icon: "chevron.right", action: {
                NativeHaptics.lightImpact()
                onStep(1)
            })
            .disabled(currentStep >= bars.count || bars.isEmpty)
            .accessibilityLabel("Step Forward")
            
            // Forward to end
            ModalCircleButton(icon: "forward.end.fill", action: {
                        NativeHaptics.lightImpact()
                        onForwardToEnd()
                    })
            .disabled(bars.isEmpty)
            .accessibilityLabel("Forward To End")
            
            // Divider
            Divider()
                .frame(height: 18)
                .background(AppColors.border.opacity(0.6))
            
            // Scrubber Slider
            if bars.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(currentStep) },
                        set: { currentStep = Int($0) }
                    ),
                    in: 1...Double(bars.count),
                    step: 1
                )
                .tint(AppColors.brand)
                .frame(width: 140)
            }
            
            // Step Counter
            Text("\(currentStep)/\(bars.count)")
                .font(AppTypography.number(11, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .frame(minWidth: 46)
                .lineLimit(1)
                .fixedSize()
            
            // Speed Menu
            AppCompactDropdown(
                selection: Binding(
                    get: { replaySpeed },
                    set: { replaySpeed = $0; onSpeedChanged() }
                ),
                options: [1.0, 2.0, 4.0],
                titleFor: { "\(Int($0))×" },
                height: 28
            )
        }
    }
}
