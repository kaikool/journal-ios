import SwiftUI

/// Hardware-accelerated, interactive swipeable container for trade cards.
/// Provides native left swipe (Delete) and right swipe (AI Coach / Audit) actions with full-travel auto-execution, Apple spring physics, and haptics.
public struct SwipeableTradeRow<Content: View>: View {
    let content: Content
    let isLive: Bool
    let onDelete: () -> Void
    let onAICoach: () -> Void
    let onTap: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipedLeft: Bool = false
    @State private var isSwipedRight: Bool = false
    @State private var hasTriggeredRevealHaptic: Bool = false
    @State private var hasTriggeredFullSwipeHaptic: Bool = false
    
    private let actionButtonWidth: CGFloat = 84
    private let revealThreshold: CGFloat = 65
    private let fullSwipeThreshold: CGFloat = 155
    
    public init(
        isLive: Bool = false,
        onDelete: @escaping () -> Void,
        onAICoach: @escaping () -> Void,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isLive = isLive
        self.onDelete = onDelete
        self.onAICoach = onAICoach
        self.onTap = onTap
        self.content = content()
    }
    
    private var isFullSwipeRight: Bool {
        dragOffset >= fullSwipeThreshold
    }
    
    private var isFullSwipeLeft: Bool {
        dragOffset <= -fullSwipeThreshold
    }
    
    public var body: some View {
        ZStack {
            // Background Action Buttons
            HStack(spacing: 0) {
                // Left side action (revealed on Right Swipe): AI Coach / Live Coach
                ZStack {
                    LinearGradient(
                        colors: isLive
                            ? [AppColors.brand, Color(red: 0.15, green: 0.75, blue: 0.95)]
                            : [AppColors.brand, Color(red: 0.45, green: 0.35, blue: 0.95)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    
                    VStack(spacing: 3) {
                        Image(systemName: isLive ? "bolt.fill" : "sparkles")
                            .font(.system(size: isFullSwipeRight ? 22 : 18, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(isFullSwipeRight ? 1.15 : 1.0)
                        
                        Text(isLive ? (isFullSwipeRight ? "Release to Coach" : "Live Coach") : (isFullSwipeRight ? "Release to Audit" : "AI Audit"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(max(0.65, min(1.2, abs(dragOffset) / actionButtonWidth)))
                }
                .frame(width: max(0, dragOffset))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    NativeHaptics.mediumImpact()
                    resetPosition()
                    onAICoach()
                }
                
                Spacer(minLength: 0)
                
                // Right side action (revealed on Left Swipe): Delete
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.25, blue: 0.25), Color(red: 0.82, green: 0.15, blue: 0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: isFullSwipeLeft ? 21 : 17, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(isFullSwipeLeft ? 1.15 : 1.0)
                        
                        Text(isFullSwipeLeft ? "Release to Delete" : "Delete")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(max(0.65, min(1.2, abs(dragOffset) / actionButtonWidth)))
                }
                .frame(width: max(0, -dragOffset))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    NativeHaptics.heavyImpact()
                    resetPosition()
                    onDelete()
                }
            }
            
            // Foreground Card
            content
                .offset(x: dragOffset)
                .contentShape(Rectangle())
                .onTapGesture {
                    if dragOffset != 0 {
                        resetPosition()
                    } else {
                        NativeHaptics.lightImpact()
                        onTap()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 15, coordinateSpace: .local)
                        .onChanged { value in
                            let h = value.translation.width
                            let v = value.translation.height
                            
                            // Strictly prioritize horizontal swipe over vertical scroll
                            guard abs(h) > abs(v) * 1.15 else { return }
                            
                            if h < 0 {
                                // Swiping Left (Delete)
                                let absH = -h
                                if absH >= fullSwipeThreshold {
                                    dragOffset = h
                                    if !hasTriggeredFullSwipeHaptic {
                                        hasTriggeredFullSwipeHaptic = true
                                        NativeHaptics.mediumImpact()
                                    }
                                } else if absH > actionButtonWidth {
                                    let excess = absH - actionButtonWidth
                                    dragOffset = -(actionButtonWidth + excess * 0.72)
                                    hasTriggeredFullSwipeHaptic = false
                                    if absH > revealThreshold && !hasTriggeredRevealHaptic {
                                        hasTriggeredRevealHaptic = true
                                        NativeHaptics.lightImpact()
                                    }
                                } else {
                                    dragOffset = h
                                    hasTriggeredRevealHaptic = false
                                    hasTriggeredFullSwipeHaptic = false
                                }
                            } else {
                                // Swiping Right (AI Coach)
                                if h >= fullSwipeThreshold {
                                    dragOffset = h
                                    if !hasTriggeredFullSwipeHaptic {
                                        hasTriggeredFullSwipeHaptic = true
                                        NativeHaptics.mediumImpact()
                                    }
                                } else if h > actionButtonWidth {
                                    let excess = h - actionButtonWidth
                                    dragOffset = actionButtonWidth + excess * 0.72
                                    hasTriggeredFullSwipeHaptic = false
                                    if h > revealThreshold && !hasTriggeredRevealHaptic {
                                        hasTriggeredRevealHaptic = true
                                        NativeHaptics.lightImpact()
                                    }
                                } else {
                                    dragOffset = h
                                    hasTriggeredRevealHaptic = false
                                    hasTriggeredFullSwipeHaptic = false
                                }
                            }
                        }
                        .onEnded { value in
                            let h = value.translation.width
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            hasTriggeredRevealHaptic = false
                            hasTriggeredFullSwipeHaptic = false
                            
                            // 1. Full Swipe Right -> Auto-execute AI Coach
                            if h >= fullSwipeThreshold || velocity > 380 {
                                NativeHaptics.heavyImpact()
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                                    dragOffset = 380
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                    resetPosition()
                                    onAICoach()
                                }
                            }
                            // 2. Partial Swipe Right -> Lock Action Button Open
                            else if h >= revealThreshold || velocity > 140 {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    dragOffset = actionButtonWidth
                                    isSwipedRight = true
                                    isSwipedLeft = false
                                }
                            }
                            // 3. Full Swipe Left -> Auto-execute Delete
                            else if h <= -fullSwipeThreshold || velocity < -380 {
                                NativeHaptics.heavyImpact()
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                                    dragOffset = -380
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                    resetPosition()
                                    onDelete()
                                }
                            }
                            // 4. Partial Swipe Left -> Lock Delete Button Open
                            else if h <= -revealThreshold || velocity < -140 {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    dragOffset = -actionButtonWidth
                                    isSwipedLeft = true
                                    isSwipedRight = false
                                }
                            }
                            // 5. Cancel / Below threshold -> Snap back to center
                            else {
                                resetPosition()
                            }
                        }
                )
        }
    }
    
    private func resetPosition() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            dragOffset = 0
            isSwipedLeft = false
            isSwipedRight = false
        }
    }
}
