import SwiftUI

/// Dedicated Fullscreen Landscape Chart View for Trade Replay.
/// Maximizes horizontal chart real estate for deep market structure, institutional liquidity, and RSI inspection.
public struct TradeReplayLandscapeChartView: View {
    let trade: Trade
    let executions: [Execution]
    @Binding var currentStep: Int
    @Binding var replaySpeed: Double
    @Binding var selectedResolution: MarketResolution
    @Binding var showMarketStructure: Bool
    @Binding var showLiquidity: Bool
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
        showLiquidity: Binding<Bool>,
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
        self._showLiquidity = showLiquidity
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
            Button {
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Exit")
                        .font(AppTypography.pill)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.secondaryBackground)
                .foregroundColor(AppColors.primaryText)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit Landscape View")
            
            // Symbol & Direction
            Text(trade.symbol)
                .font(.system(size: 15, weight: .bold))
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
            Text("\(pnl >= 0 ? "+" : "")\(Formatters.formatCurrency(pnl, currency: reportingCurrency))")
                .font(AppTypography.number(12, weight: .bold))
                .foregroundColor(pnlColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(pnlColor.opacity(0.12))
                .cornerRadius(6)
                .lineLimit(1)
                .fixedSize()
            
            Spacer()
            
            // Current candle timestamp
            if let curBar = frame.currentBar {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.formatDateTime(curBar.date, timeZone: timeZone))
                        .font(AppTypography.number(11, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            
            // Orientation flip button (toggles 90° rotation for devices with portrait orientation lock)
            Button {
                isForceLandscape90.toggle()
            } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 11, weight: .bold))
                    .padding(7)
                    .background(AppColors.secondaryBackground)
                    .foregroundColor(AppColors.secondaryText)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Landscape Rotation")
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
            
            ForEach(TradeReplayView.replayResolutions) { res in
                let isSelected = res == selectedResolution
                let title: String = {
                    switch res {
                    case .m15: return "15m"
                    case .h1: return "1h"
                    case .h4: return "4h"
                    case .d1: return "1D"
                    default: return res.rawValue.uppercased()
                    }
                }()
                Button {
                    guard selectedResolution != res else { return }
                    selectedResolution = res
                } label: {
                    Text(title)
                        .font(AppTypography.pill)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(isSelected ? AppColors.accent : AppColors.secondaryBackground)
                        .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Trend Regime Pill
            if let t = currentTrendBias {
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
            
            // Minimalist Legend Dots (EMA 21, EMA 50, BSL, SSL, RSI 14)
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
                    Text("BSL")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.82, blue: 0.95))
                        .frame(width: 5, height: 5)
                    Text("SSL")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.65, green: 0.45, blue: 0.95))
                        .frame(width: 5, height: 5)
                    Text("RSI 14")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }
    
    // MARK: - 3. Candlestick Chart Container
    private var chartContainer: some View {
        Group {
            if bars.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(AppColors.brand)
                    Text("Loading Candles…")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    showLiquidity: true,
                    showRSI: true,
                    isLandscape: true
                )
            }
        }
    }
    
    // MARK: - 4. Bottom Center Replay Playback Controller Capsule
    private var bottomPlayerBar: some View {
        HStack(spacing: 10) {
            // Reset to beginning
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onReset()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 30, height: 30)
                    .background(AppColors.secondaryBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(bars.isEmpty)
            .accessibilityLabel("Reset Replay")
            
            // Step back 1 bar
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(currentStep <= 1 ? AppColors.secondaryText.opacity(0.3) : AppColors.primaryText)
                    .frame(width: 30, height: 30)
                    .background(AppColors.secondaryBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(currentStep <= 1 || bars.isEmpty)
            .accessibilityLabel("Step Backward")
            
            // Play / Pause (Large central button)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onTogglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(AppColors.brand)
                    .clipShape(Circle())
                    .shadow(color: AppColors.brand.opacity(0.35), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(bars.isEmpty)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            
            // Step forward 1 bar
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onStep(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(currentStep >= bars.count ? AppColors.secondaryText.opacity(0.3) : AppColors.primaryText)
                    .frame(width: 30, height: 30)
                    .background(AppColors.secondaryBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(currentStep >= bars.count || bars.isEmpty)
            .accessibilityLabel("Step Forward")
            
            // Forward to end
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onForwardToEnd()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 30, height: 30)
                    .background(AppColors.secondaryBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
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
            Menu {
                Button("1×") { replaySpeed = 1.0; onSpeedChanged() }
                Button("2×") { replaySpeed = 2.0; onSpeedChanged() }
                Button("4×") { replaySpeed = 4.0; onSpeedChanged() }
            } label: {
                HStack(spacing: 2) {
                    Text("\(Int(replaySpeed))×")
                        .font(.system(size: 11, weight: .bold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppColors.secondaryBackground)
                .foregroundColor(AppColors.primaryText)
                .cornerRadius(6)
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(AppColors.cardBackground.opacity(0.94))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}
