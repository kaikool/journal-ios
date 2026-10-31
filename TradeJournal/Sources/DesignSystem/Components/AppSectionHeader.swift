import SwiftUI

/// Standardized Section / Card Header with uppercase tracking, optional leading icon, badge, trailing badge, and trailing action button.
public struct AppSectionHeader: View {
    public let title: String
    public let icon: String?
    public let badge: String?
    public let badgeColor: Color
    public let trailingBadge: String?
    public let trailingBadgeColor: Color
    public let actionTitle: String?
    public let actionIcon: String?
    public let actionColor: Color
    public let onAction: (() -> Void)?
    
    public init(
        _ title: String,
        icon: String? = nil,
        badge: String? = nil,
        badgeColor: Color = AppColors.brand,
        trailingBadge: String? = nil,
        trailingBadgeColor: Color = AppColors.brand,
        actionTitle: String? = nil,
        actionIcon: String? = nil,
        actionColor: Color = AppColors.brand,
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.badgeColor = badgeColor
        self.trailingBadge = trailingBadge
        self.trailingBadgeColor = trailingBadgeColor
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.actionColor = actionColor
        self.onAction = onAction
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Text(title.uppercased())
                .font(AppTypography.cardHeader)
                .tracking(0.5)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            
            if let badge = badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Spacer(minLength: 8)
            
            if let trailingBadge = trailingBadge, !trailingBadge.isEmpty {
                Text(trailingBadge)
                    .font(AppTypography.badgeMicro)
                    .foregroundColor(trailingBadgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(trailingBadgeColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            if let onAction = onAction {
                Button {
                    NativeHaptics.lightImpact()
                    onAction()
                } label: {
                    HStack(spacing: 4) {
                        if let actionIcon = actionIcon {
                            Image(systemName: actionIcon)
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        if let actionTitle = actionTitle {
                            Text(actionTitle)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(actionColor)
                    .padding(.horizontal, actionTitle != nil ? 9 : 6)
                    .padding(.vertical, 3.5)
                    .background(actionColor.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(actionColor.opacity(0.25), lineWidth: 0.7)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
