import SwiftUI

/// Bottom Action Buttons Card for Trade Detail View
public struct TradeDetailActionsCard: View {
    public let isTradeOpen: Bool
    public var onAICoach: () -> Void
    public var onReplay: () -> Void
    public var onEdit: () -> Void
    public var onDelete: () -> Void
    
    public init(
        isTradeOpen: Bool,
        onAICoach: @escaping () -> Void,
        onReplay: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.isTradeOpen = isTradeOpen
        self.onAICoach = onAICoach
        self.onReplay = onReplay
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Row 1: AI Trade Coach
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                onAICoach()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isTradeOpen ? "AI Trade Coach • Live Advisory" : "AI Trade Coach • Post-Mortem")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            // Row 2: Side-by-side Replay & Edit
            HStack(spacing: 8) {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onReplay()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Replay")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onEdit()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                        Text("Edit Trade")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
            }
            
            // Row 3: Delete Trade
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                onDelete()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Delete Trade")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AppColors.loss.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(AppColors.loss.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
}
