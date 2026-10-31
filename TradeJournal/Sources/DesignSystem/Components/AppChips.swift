import SwiftUI

/// Unified Apple HIG Filter Chip with active selection states, optional icon, and count badge.
public struct AppFilterChip: View {
    public let title: String
    public let isSelected: Bool
    public let icon: String?
    public let count: Int?
    public let height: CGFloat
    public let activeColor: Color
    public let action: () -> Void
    
    public init(
        _ title: String,
        isSelected: Bool,
        icon: String? = nil,
        count: Int? = nil,
        height: CGFloat = 30,
        activeColor: Color = AppColors.brand,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.icon = icon
        self.count = count
        self.height = height
        self.activeColor = activeColor
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            HStack(spacing: 4.5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(isSelected ? AppTypography.captionBold : AppTypography.captionMicro)
                }
                
                Text(title)
                    .font(isSelected ? AppTypography.captionBold : AppTypography.captionMicro)
                    .lineLimit(1)
                
                if let count = count {
                    Text("\(count)")
                        .font(AppTypography.badgeMicro)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(isSelected ? activeColor.opacity(0.25) : AppColors.secondaryBackground)
                        .foregroundColor(isSelected ? activeColor : AppColors.secondaryText)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(isSelected ? activeColor.opacity(0.14) : AppColors.secondaryBackground.opacity(0.85))
            .foregroundColor(isSelected ? activeColor : AppColors.secondaryText)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? activeColor.opacity(0.40) : AppColors.border.opacity(0.55), lineWidth: 0.8)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

/// Unified Apple HIG Trade Tag / Badge with optional remove action.
public struct AppTag: View {
    public let title: String
    public let color: Color
    public let prefix: String?
    public let onRemove: (() -> Void)?
    
    public init(
        _ title: String,
        color: Color = AppColors.brand,
        prefix: String? = "#",
        onRemove: (() -> Void)? = nil
    ) {
        self.title = title
        self.color = color
        self.prefix = prefix
        self.onRemove = onRemove
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Text("\(prefix ?? "")\(title)")
                .font(AppTypography.badgeStandard)
                .foregroundColor(color)
                .lineLimit(1)
            
            if let onRemove = onRemove {
                Button {
                    NativeHaptics.lightImpact()
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.captionMicro)
                        .foregroundColor(color.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .padding(.horizontal, onRemove != nil ? 8 : 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(color.opacity(0.30), lineWidth: 0.8)
        )
    }
}
