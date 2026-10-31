import SwiftUI

/// Hardware-accelerated, interactive swipeable container for trade cards.
/// Provides native left swipe (Delete) and right swipe (AI Coach) actions with Apple spring physics and haptics.
public struct SwipeableTradeRow<Content: View>: View {
    let content: Content
    let onDelete: () -> Void
    let onAICoach: () -> Void
    let onTap: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isSwipedLeft: Bool = false
    @State private var isSwipedRight: Bool = false
    @State private var hasTriggeredThresholdHaptic: Bool = false
    
    private let actionButtonWidth: CGFloat = 72
    private let triggerThreshold: CGFloat = 80
    
    public init(
        onDelete: @escaping () -> Void,
        onAICoach: @escaping () -> Void,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onDelete = onDelete
        self.onAICoach = onAICoach
        self.onTap = onTap
        self.content = content()
    }
    
    public var body: some View {
        ZStack {
            // Background Action Buttons
            HStack(spacing: 0) {
                // Left side action (revealed on Right Swipe): AI Coach
                ZStack {
                    LinearGradient(
                        colors: [AppColors.brand, AppColors.brand.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    
                    VStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("AI Coach")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(max(0.6, min(1.15, abs(dragOffset) / actionButtonWidth)))
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
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Text("Delete")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(max(0.6, min(1.15, abs(dragOffset) / actionButtonWidth)))
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
                            
                            // Apply rubber-banding resistance beyond button width
                            if h < 0 {
                                // Swiping Left (Delete)
                                let excess = max(0, -h - actionButtonWidth)
                                dragOffset = -(actionButtonWidth + excess * 0.35)
                                
                                if -h > triggerThreshold && !hasTriggeredThresholdHaptic {
                                    hasTriggeredThresholdHaptic = true
                                    NativeHaptics.lightImpact()
                                }
                            } else {
                                // Swiping Right (AI Coach)
                                let excess = max(0, h - actionButtonWidth)
                                dragOffset = actionButtonWidth + excess * 0.35
                                
                                if h > triggerThreshold && !hasTriggeredThresholdHaptic {
                                    hasTriggeredThresholdHaptic = true
                                    NativeHaptics.lightImpact()
                                }
                            }
                        }
                        .onEnded { value in
                            hasTriggeredThresholdHaptic = false
                            let h = value.translation.width
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            if h < -triggerThreshold || velocity < -120 {
                                // Lock Left open
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    dragOffset = -actionButtonWidth
                                    isSwipedLeft = true
                                    isSwipedRight = false
                                }
                            } else if h > triggerThreshold || velocity > 120 {
                                // Lock Right open
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    dragOffset = actionButtonWidth
                                    isSwipedRight = true
                                    isSwipedLeft = false
                                }
                            } else {
                                // Snap back to center
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
