import SwiftUI

/// Unified Apple HIG Toggle Row
/// Replaces inconsistent toggle rows in forms, cards, and settings with a standard row layout.
public struct AppToggleRow: View {
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let iconColor: Color
    @Binding public var isOn: Bool
    public let onChange: ((Bool) -> Void)?
    
    public init(
        _ title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color = AppColors.brand,
        isOn: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self._isOn = isOn
        self.onChange = onChange
    }
    
    public var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { val in
                NativeHaptics.lightImpact()
                isOn = val
                onChange?(val)
            }
        )) {
            HStack(spacing: 10) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                        .frame(width: 24, height: 24)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                    
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
        }
        .tint(AppColors.brand)
        .padding(.vertical, 3)
    }
}

/// Unified Apple HIG Checkbox / Checklist Row
/// Interactive selectable item with checkmark circle/square pod, title, subtitle, and strike-through styling.
public struct AppCheckboxRow: View {
    public let title: String
    public let subtitle: String?
    public let isChecked: Bool
    public let index: Int?
    public let isStrikethroughWhenChecked: Bool
    public let action: () -> Void
    
    public init(
        _ title: String,
        subtitle: String? = nil,
        isChecked: Bool,
        index: Int? = nil,
        isStrikethroughWhenChecked: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isChecked = isChecked
        self.index = index
        self.isStrikethroughWhenChecked = isStrikethroughWhenChecked
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            NativeHaptics.lightImpact()
            action()
        }) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isChecked ? AppColors.brand : AppColors.secondaryBackground.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isChecked ? AppColors.brand : AppColors.border.opacity(0.6), lineWidth: 1)
                        )
                    
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                    } else if let index = index {
                        Text("\(index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isChecked && isStrikethroughWhenChecked ? AppColors.secondaryText : AppColors.primaryText)
                        .strikethrough(isChecked && isStrikethroughWhenChecked, color: AppColors.secondaryText)
                        .lineLimit(2)
                    
                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .padding(.vertical, 4)
    }
}
