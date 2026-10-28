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
                ProgressView()
                    .scaleEffect(0.9)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(isLoadingData ? "Streaming Multi-Timeframe Bars..." : "Auditing Liquidity & Formulating Bias...")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Risk AI is cross-referencing D1 macro regime, H4 order blocks, and M15 liquidity triggers.")
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.loss)
                
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(2)
                
                Button(action: onRetry) {
                    Text("Retry Stream")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.brand)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }
}
