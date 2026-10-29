import SwiftUI

/// Playback Controls Card with timeline scrubber slider and spring physics buttons
public struct TradeReplayControlsCard: View {
    @Binding public var currentStep: Int
    @Binding public var replaySpeed: Double
    public let isPlaying: Bool
    public let barsCount: Int
    public let currentBar: MarketBar?
    public let isLoadingCandles: Bool
    public let timeZone: TimeZone
    
    public var onTogglePlay: () -> Void
    public var onStep: (Int) -> Void
    public var onReset: () -> Void
    public var onForwardToEnd: () -> Void
    public var onSpeedChanged: () -> Void
    public var onOpenLandscape: (() -> Void)?
    
    public init(
        currentStep: Binding<Int>,
        replaySpeed: Binding<Double>,
        isPlaying: Bool,
        barsCount: Int,
        currentBar: MarketBar?,
        isLoadingCandles: Bool,
        timeZone: TimeZone,
        onTogglePlay: @escaping () -> Void,
        onStep: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onForwardToEnd: @escaping () -> Void,
        onSpeedChanged: @escaping () -> Void,
        onOpenLandscape: (() -> Void)? = nil
    ) {
        self._currentStep = currentStep
        self._replaySpeed = replaySpeed
        self.isPlaying = isPlaying
        self.barsCount = barsCount
        self.currentBar = currentBar
        self.isLoadingCandles = isLoadingCandles
        self.timeZone = timeZone
        self.onTogglePlay = onTogglePlay
        self.onStep = onStep
        self.onReset = onReset
        self.onForwardToEnd = onForwardToEnd
        self.onSpeedChanged = onSpeedChanged
        self.onOpenLandscape = onOpenLandscape
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(spacing: 12) {
                // Scrubber Slider
                if barsCount > 1 {
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { Double(currentStep) },
                                set: { currentStep = Int($0) }
                            ),
                            in: 1...Double(barsCount),
                            step: 1
                        )
                        .tint(AppColors.brand)
                    }
                }
                
                // Playback controls row
                HStack(spacing: 8) {
                    // Restart
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onReset()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 34, height: 34)
                            .background(AppColors.cardBackground.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .disabled(barsCount == 0)
                    
                    // Step back
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onStep(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(currentStep <= 1 ? AppColors.secondaryText.opacity(0.3) : AppColors.primaryText)
                            .frame(width: 34, height: 34)
                            .background(AppColors.cardBackground.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .disabled(currentStep <= 1 || barsCount == 0)
                    
                    // Play / Pause
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onTogglePlay()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(isPlaying ? "Pause" : "Play")
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(AppColors.brand)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: AppColors.brand.opacity(0.25), radius: 3, x: 0, y: 1.5)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .disabled(barsCount == 0)
                    .fixedSize()
                    
                    // Step forward
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onStep(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(currentStep >= barsCount ? AppColors.secondaryText.opacity(0.3) : AppColors.primaryText)
                            .frame(width: 34, height: 34)
                            .background(AppColors.cardBackground.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .disabled(currentStep >= barsCount || barsCount == 0)
                    
                    // Forward to end
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onForwardToEnd()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 34, height: 34)
                            .background(AppColors.cardBackground.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .disabled(barsCount == 0)
                    
                    Spacer(minLength: 4)
                    
                    // Replay Speed menu
                    Menu {
                        Button("1×") { replaySpeed = 1.0; onSpeedChanged() }
                        Button("2×") { replaySpeed = 2.0; onSpeedChanged() }
                        Button("4×") { replaySpeed = 4.0; onSpeedChanged() }
                    } label: {
                        HStack(spacing: 3) {
                            Text("\(Int(replaySpeed))×")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .frame(height: 34)
                        .padding(.horizontal, 8)
                        .background(AppColors.secondaryBackground)
                        .foregroundColor(AppColors.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .fixedSize()
                    
                    // Fullscreen Landscape Trigger (placed directly next to Speed button)
                    if let onLandscape = onOpenLandscape {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            onLandscape()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .frame(width: 34, height: 34)
                                .background(AppColors.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                        .accessibilityLabel("Fullscreen Landscape Chart")
                    }
                }
                
                // Timestamp and count caption
                if let curBar = currentBar {
                    let formattedTime = Formatters.formatDateTime(curBar.date, timeZone: timeZone)
                    HStack {
                        Text("\(currentStep) / \(barsCount) candles • Through: \(formattedTime)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                    }
                } else if isLoadingCandles && barsCount == 0 {
                    HStack {
                        Text("Awaiting market data to enable playback…")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        Spacer()
                    }
                }
            }
        }
    }
}
