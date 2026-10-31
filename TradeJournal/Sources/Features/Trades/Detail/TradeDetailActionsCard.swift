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
            AppSecondaryButton(
                isTradeOpen ? "AI Trade Coach • Live Advisory" : "AI Trade Coach • Post-Mortem",
                icon: "sparkles",
                fullWidth: true,
                height: 38,
                action: onAICoach
            )
            
            // Row 2: Side-by-side Replay & Edit
            HStack(spacing: 8) {
                AppSecondaryButton("Replay", icon: "play.fill", fullWidth: true, height: 36, action: onReplay)
                AppSecondaryButton("Edit Trade", icon: "pencil", fullWidth: true, height: 36, action: onEdit)
            }
            
            // Row 3: Delete Trade
            AppDestructiveButton("Delete Trade", icon: "trash", fullWidth: true, height: 34, action: onDelete)
        }
    }
}
