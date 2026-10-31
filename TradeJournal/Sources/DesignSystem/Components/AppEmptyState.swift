import SwiftUI

/// Unified Apple HIG Trading Terminal Empty State component
/// Displays a soft icon pod, clear title, descriptive message, and an optional primary action CTA button.
public struct AppEmptyState: View {
    public let icon: String
    public let title: String
    public let message: String
    public let iconColor: Color
    public let actionTitle: String?
    public let actionIcon: String?
    public let secondaryActionTitle: String?
    public let isInCard: Bool
    public let action: (() -> Void)?
    public let secondaryAction: (() -> Void)?
    
    public init(
        icon: String,
        title: String,
        message: String,
        iconColor: Color = AppColors.brand,
        actionTitle: String? = nil,
        actionIcon: String? = "plus",
        secondaryActionTitle: String? = nil,
        isInCard: Bool = false,
        action: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconColor = iconColor
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.secondaryActionTitle = secondaryActionTitle
        self.isInCard = isInCard
        self.action = action
        self.secondaryAction = secondaryAction
    }
    
    public var body: some View {
        VStack(spacing: isInCard ? 10 : 14) {
            if !isInCard {
                Spacer()
            }
            
            // Icon Pod
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.10))
                    .frame(width: isInCard ? 46 : 56, height: isInCard ? 46 : 56)
                    .overlay(
                        Circle().stroke(iconColor.opacity(0.20), lineWidth: 0.8)
                    )
                Image(systemName: icon)
                    .font(.system(size: isInCard ? 20 : 25, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .padding(.top, isInCard ? 6 : 0)
            
            // Text Content
            VStack(spacing: 5) {
                Text(title)
                    .font(isInCard ? AppTypography.subheadlineBold : AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                    .multilineTextAlignment(.center)
                
                if !message.isEmpty {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, isInCard ? 16 : 32)
                }
            }
            
            // Actions
            if let actionTitle = actionTitle, let action = action {
                HStack(spacing: 10) {
                    AppPrimaryButton(actionTitle, icon: actionIcon, height: 38, action: action)
                    
                    if let secTitle = secondaryActionTitle, let secAction = secondaryAction {
                        AppSecondaryButton(secTitle, height: 38, action: secAction)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, isInCard ? 4 : 0)
            } else if let secTitle = secondaryActionTitle, let secAction = secondaryAction {
                AppSecondaryButton(secTitle, height: 38, action: secAction)
                    .padding(.top, 4)
            }
            
            if !isInCard {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isInCard ? 16 : 32)
    }
}
