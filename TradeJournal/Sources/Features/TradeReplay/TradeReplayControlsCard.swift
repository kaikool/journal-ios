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
                    ModalCircleButton(icon: "backward.end.fill", action: {
                NativeHaptics.lightImpact()
                onReset()
            })
                    .disabled(barsCount == 0)
                    
                    // Step back
                    ModalCircleButton(icon: "chevron.left", action: {
                        NativeHaptics.lightImpact()
                        onStep(-1)
                    })
                    .disabled(currentStep <= 1 || barsCount == 0)
                    
                    // Play / Pause
                    AppActionPill(
                        isPlaying ? "Pause" : "Play",
                        icon: isPlaying ? "pause.fill" : "play.fill",
                        isPrimary: true
                    ) {
                        onTogglePlay()
                    }
                    .disabled(barsCount == 0)
                    
                    // Step forward
                    ModalCircleButton(icon: "chevron.right", action: {
                        NativeHaptics.lightImpact()
                        onStep(1)
                    })
                    .disabled(currentStep >= barsCount || barsCount == 0)
                    
                    // Forward to end
                    ModalCircleButton(icon: "forward.end.fill", action: {
                NativeHaptics.lightImpact()
                onForwardToEnd()
            })
                    .disabled(barsCount == 0)
                    
                    Spacer(minLength: 4)
                    
                    // Replay Speed menu
                    AppCompactDropdown(
                        selection: Binding(
                            get: { replaySpeed },
                            set: { replaySpeed = $0; onSpeedChanged() }
                        ),
                        options: [1.0, 2.0, 4.0],
                        titleFor: { "\(Int($0))x" },
                        height: 34
                    )
                    
                    // Fullscreen Landscape Trigger (placed directly next to Speed button)
                    if let onLandscape = onOpenLandscape {
                        ModalCircleButton(icon: "arrow.up.left.and.arrow.down.right", action: {
                NativeHaptics.lightImpact()
                onLandscape()
            })
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
