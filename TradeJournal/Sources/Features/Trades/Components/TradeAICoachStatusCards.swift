import SwiftUI

// MARK: - Trade AI Coach Loading Card
public struct TradeAICoachLoadingCard: View {
    public let isOpen: Bool
    
    public init(isOpen: Bool) {
        self.isOpen = isOpen
    }
    
    public var body: some View {
        AppCard {
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.brand))
                    .scaleEffect(1.1)
                
                Text(isOpen
                     ? "Risk AI is evaluating market structure, liquidity & position rationality..."
                     : "Risk AI is auditing execution quality, plan compliance & discipline...")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
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
                    .font(.system(size: 26))
                    .foregroundColor(AppColors.warning)
                
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                
                Button(action: onRetry) {
                    Text("Retry Analysis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}
