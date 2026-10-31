import SwiftUI

// MARK: - Trade AI Coach Loading Card
public struct TradeAICoachLoadingCard: View {
    public let isOpen: Bool
    
    public init(isOpen: Bool) {
        self.isOpen = isOpen
    }
    
    public var body: some View {
        AppCard {
            LoadingView(
                isOpen
                ? "Risk AI is evaluating market structure, liquidity & position rationality..."
                : "Risk AI is auditing execution quality, plan compliance & discipline...",
                size: 48
            )
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Trade AI Coach Error Card
public struct TradeAICoachErrorCard: View {
    public let message: String
    public let onRetry: () -> Void
    
    public init(message: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }
    
    public var body: some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(AppTypography.displayHero)
                    .foregroundColor(AppColors.warning)
                
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                
                AppSecondaryButton("Retry Analysis", icon: "arrow.clockwise", height: 32, action: onRetry)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}
