import SwiftUI

// MARK: - Pre-Trade Analysis Loading & Status Cards
public struct PreTradeLoadingCard: View {
    public let isLoadingData: Bool
    
    public init(isLoadingData: Bool) {
        self.isLoadingData = isLoadingData
    }
    
    public var body: some View {
        AppCard {
            HStack(spacing: 12) {
                TradeJournalProLoader(size: 28)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(isLoadingData ? "Streaming Multi-Timeframe Bars..." : "Evaluating EMA Trend & Formulating Setups...")
                        .font(AppTypography.rowTitle)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Risk AI is cross-referencing D1/H4 EMA trends, key price levels, and M15 execution triggers.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

public struct PreTradeErrorCard: View {
    public let message: String
    public let onRetry: () -> Void
    
    public init(message: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Market Stream Notice")
                    .font(AppTypography.cardHeader)
                    .foregroundColor(AppColors.loss)
                
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(2)
                
                AppPrimaryButton("Retry Stream", icon: "arrow.counterclockwise", action: onRetry)
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }
}
