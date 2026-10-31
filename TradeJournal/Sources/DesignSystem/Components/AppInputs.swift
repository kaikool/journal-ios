import SwiftUI

/// Backwards compatibility alias for AppSegmentedBar
public typealias AppleSlidingSegmentedBar<T: Hashable> = AppSegmentedBar<T>

/// Custom Apple HIG Styled Dropdown Field matching app rounded rectangle card aesthetic.
/// Replaces generic system picker grey button with a crisp, theme-aware selector.
public struct AppDropdownField<T: Hashable>: View {
    public let label: String?
    @Binding public var selection: T
    public let options: [T]
    public let titleFor: (T) -> String
    public let iconFor: ((T) -> String?)?
    
    public init(
        label: String? = nil,
        selection: Binding<T>,
        options: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.titleFor = titleFor
        self.iconFor = iconFor
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = label, !label.isEmpty {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button {
                        selection = opt
                    } label: {
                        HStack {
                            if let icon = iconFor?(opt) {
                                Image(systemName: icon)
                            }
                            Text(titleFor(opt))
                            if selection == opt {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let icon = iconFor?(selection) {
                        Image(systemName: icon)
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.brand)
                    }
                    
                    Text(titleFor(selection))
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTypography.captionMicro)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppColors.secondaryBackground.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
}

/// Compact Apple HIG Dropdown pill for filters, toolbars, and replay controls
public struct AppCompactDropdown<T: Hashable>: View {
    public let icon: String?
    @Binding public var selection: T
    public let options: [T]
    public let titleFor: (T) -> String
    public let iconFor: ((T) -> String?)?
    public let height: CGFloat
    
    public init(
        icon: String? = nil,
        selection: Binding<T>,
        options: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil,
        height: CGFloat = 32
    ) {
        self.icon = icon
        self._selection = selection
        self.options = options
        self.titleFor = titleFor
        self.iconFor = iconFor
        self.height = height
    }
    
    public var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    NativeHaptics.lightImpact()
                    selection = opt
                } label: {
                    HStack {
                        if let optIcon = iconFor?(opt) {
                            Image(systemName: optIcon)
                        }
                        Text(titleFor(opt))
                        if selection == opt {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppTypography.actionButtonCompact)
                        .foregroundColor(AppColors.secondaryText)
                } else if let selIcon = iconFor?(selection) {
                    Image(systemName: selIcon)
                        .font(AppTypography.actionButtonCompact)
                        .foregroundColor(AppColors.brand)
                }
                
                Text(titleFor(selection))
                    .font(AppTypography.actionButtonCompact)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(AppColors.secondaryBackground.opacity(0.65))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}
