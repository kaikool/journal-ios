import SwiftUI

public struct ApplePressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Standardized Apple HIG Trading Terminal button with spring physics and haptics
public struct AppButton: View {
    public enum Style {
        case primary, secondary, outline, destructive
    }
    public enum Size {
        case regular, compact
    }
    
    private let title: String
    private let iconName: String?
    private let style: Style
    private let size: Size
    private let fullWidth: Bool
    private let isLoading: Bool
    private let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        size: Size = .regular,
        fullWidth: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = icon
        self.style = style
        self.size = size
        self.fullWidth = fullWidth
        self.isLoading = isLoading
        self.action = action
    }
    
    public var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: style == .primary ? .medium : .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: size == .compact ? 4 : 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                } else if let icon = iconName {
                    Image(systemName: icon)
                        .font(.system(size: size == .compact ? 11 : 12.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: size == .compact ? 12.5 : 13.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, size == .compact ? 6 : 8)
            .padding(.horizontal, size == .compact ? 12 : 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: size == .compact ? 32 : 38)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(style == .outline ? AppColors.border.opacity(0.6) : (style == .secondary ? AppColors.border.opacity(0.4) : Color.clear), lineWidth: 0.8)
            )
            .shadow(color: style == .primary ? AppColors.brand.opacity(0.3) : Color.clear, radius: 3, x: 0, y: 1)
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .buttonStyle(ApplePressableButtonStyle())
        .disabled(isLoading)
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary: return AppColors.brand
        case .secondary: return AppColors.secondaryBackground.opacity(0.85)
        case .outline: return Color.clear
        case .destructive: return AppColors.loss.opacity(0.12)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .destructive: return AppColors.loss
        case .secondary, .outline: return AppColors.primaryText
        }
    }
}

// MARK: - Specialized Single Source of Truth Buttons

public struct AppPrimaryButton: View {
    let title: String
    let icon: String?
    let isEnabled: Bool
    let fullWidth: Bool
    let height: CGFloat
    let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        fullWidth: Bool = false,
        height: CGFloat = 38,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.fullWidth = fullWidth
        self.height = height
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.mediumImpact()
            action()
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: height <= 32 ? 12.5 : 13.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isEnabled ? .white : AppColors.secondaryText.opacity(0.6))
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(isEnabled ? AppColors.brand : AppColors.secondaryBackground)
            .clipShape(Capsule())
            .shadow(color: isEnabled ? AppColors.brand.opacity(0.3) : .clear, radius: 3, x: 0, y: 1)
        }
        .buttonStyle(ApplePressableButtonStyle())
        .disabled(!isEnabled)
    }
}

public struct AppSecondaryButton: View {
    let title: String
    let icon: String?
    let fullWidth: Bool
    let height: CGFloat
    let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = nil,
        fullWidth: Bool = false,
        height: CGFloat = 38,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.fullWidth = fullWidth
        self.height = height
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: height <= 32 ? 12.5 : 13.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(AppColors.primaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(AppColors.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

public struct AppDestructiveButton: View {
    let title: String
    let icon: String?
    let fullWidth: Bool
    let height: CGFloat
    let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = "trash",
        fullWidth: Bool = false,
        height: CGFloat = 38,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.fullWidth = fullWidth
        self.height = height
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: height <= 32 ? 12.5 : 13.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(AppColors.loss)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(AppColors.loss.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppColors.loss.opacity(0.3), lineWidth: 0.8)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

public struct AppIconPodButton: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let label: String
    let action: () -> Void
    
    public init(
        icon: String,
        color: Color = AppColors.secondaryText,
        size: CGFloat = 32,
        label: String = "",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.color = color
        self.size = size
        self.label = label
        self.action = action
    }
    
    public var body: some View {
        Button {
            NativeHaptics.lightImpact()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryBackground.opacity(0.85))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                Image(systemName: icon)
                    .font(.system(size: size <= 32 ? 12 : 14, weight: .semibold))
                    .foregroundColor(color)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel(label.isEmpty ? icon : label)
    }
}

/// Standardized Apple HIG Action Pill for navigation and filter bars (e.g. Add Trade, View my day, Ask AI).
public struct AppActionPill: View {
    private let title: String
    private let icon: String?
    private let isPrimary: Bool
    private let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = nil,
        isPrimary: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isPrimary = isPrimary
        self.action = action
    }
    
    public var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: isPrimary ? .medium : .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.actionPill)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isPrimary ? AppColors.brand : AppColors.cardBackground.opacity(0.85))
            .foregroundColor(isPrimary ? AppColors.brandTextOnDark : AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPrimary ? 0.35 : 0.2),
                                Color.white.opacity(isPrimary ? 0.08 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
            .shadow(color: isPrimary ? AppColors.brand.opacity(0.28) : Color.black.opacity(0.04), radius: 6, x: 0, y: 1.5)
        }
        .buttonStyle(ApplePressableButtonStyle())
        .fixedSize()
    }
}

/// Standardized Apple HIG Back Button for sub-pages and pushed navigation.
public struct AppBackButton: View {
    private let title: String?
    private let action: () -> Void
    
    public init(_ title: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                if let title = title, !title.isEmpty {
                    Text(title)
                        .font(AppTypography.actionPill)
                }
            }
            .foregroundColor(AppColors.primaryText)
            .padding(.horizontal, title != nil ? 10 : 9)
            .padding(.vertical, 7)
            .frame(minWidth: 36, minHeight: 32)
            .background(AppColors.cardBackground.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 44)
        .zIndex(999)
    }
}

/// Standardized Apple HIG Action Pill Navigation Link (e.g. View my day).
public struct AppActionPillLink<Destination: View>: View {
    private let title: String
    private let icon: String?
    private let isPrimary: Bool
    private let destination: Destination
    
    public init(
        _ title: String,
        icon: String? = nil,
        isPrimary: Bool = true,
        destination: Destination
    ) {
        self.title = title
        self.icon = icon
        self.isPrimary = isPrimary
        self.destination = destination
    }
    
    public var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.actionPill)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isPrimary ? AppColors.brand : AppColors.cardBackground.opacity(0.85))
            .foregroundColor(isPrimary ? AppColors.brandTextOnDark : AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPrimary ? 0.35 : 0.2),
                                Color.white.opacity(isPrimary ? 0.08 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
            .shadow(color: isPrimary ? AppColors.brand.opacity(0.28) : Color.black.opacity(0.04), radius: 6, x: 0, y: 1.5)
        }
        .buttonStyle(ApplePressableButtonStyle())
        .fixedSize()
    }
}

/// Standardized Apple HIG Action Menu Pill for top action slot with a dropdown menu (e.g. Prop Firm "New").
public struct AppActionMenu<MenuContent: View>: View {
    private let title: String
    private let icon: String?
    private let isPrimary: Bool
    private let menuContent: MenuContent
    
    public init(
        _ title: String,
        icon: String? = nil,
        isPrimary: Bool = true,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self.icon = icon
        self.isPrimary = isPrimary
        self.menuContent = menuContent()
    }
    
    public var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(AppTypography.actionPill)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isPrimary ? AppColors.brand : AppColors.cardBackground.opacity(0.85))
            .foregroundColor(isPrimary ? AppColors.brandTextOnDark : AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPrimary ? 0.35 : 0.2),
                                Color.white.opacity(isPrimary ? 0.08 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
            .shadow(color: isPrimary ? AppColors.brand.opacity(0.28) : Color.black.opacity(0.04), radius: 6, x: 0, y: 1.5)
        }
        .buttonStyle(ApplePressableButtonStyle())
        .fixedSize()
    }
}
