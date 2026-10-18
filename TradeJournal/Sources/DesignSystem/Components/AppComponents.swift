import SwiftUI

/// Trading Terminal card container matching Apple HIG
public struct AppCard<Content: View>: View {
    private let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

public typealias AppleCard = AppCard

/// Stat card header component
public struct AppCardHeader: View {
    private let title: String
    private let icon: String?
    
    public init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
    
    public var body: some View {
        HStack {
            Text(title.uppercased())
                .font(AppTypography.cardTitle)
                .tracking(0.88)
                .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
            }
        }
    }
}

/// Win / Loss ratio bar visualization matching web journal-progress-visual
public struct AppRatioBar: View {
    private let greenRatio: Double
    
    public init(greenRatio: Double) {
        self.greenRatio = min(max(greenRatio, 0.05), 0.95)
    }
    
    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule()
                    .fill(AppColors.profit)
                    .frame(width: max(6, proxy.size.width * CGFloat(greenRatio) - 1))
                
                Capsule()
                    .fill(AppColors.loss)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 6)
    }
}

public struct ApplePressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Status badge matching Apple HIG and Tailwind `badge.tsx`:
/// - profit: green with translucent background
/// - loss: red with translucent background
/// - secondary: dark gray secondary background
public struct AppBadge: View {
    public enum Variant {
        case profit
        case loss
        case secondary
        case outline
    }
    
    private let text: String
    private let variant: Variant
    
    public init(_ text: String, variant: Variant = .secondary) {
        self.text = text
        self.variant = variant
    }
    
    public init(_ text: String, color: Color) {
        self.text = text
        if color == AppColors.profit {
            self.variant = .profit
        } else if color == AppColors.loss {
            self.variant = .loss
        } else {
            self.variant = .secondary
        }
    }
    
    public init(text: String, color: Color) {
        self.init(text, color: color)
    }
    
    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: variant == .outline ? 1 : 0)
            )
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .profit: return AppColors.profit.opacity(0.14)
        case .loss: return AppColors.loss.opacity(0.14)
        case .secondary: return AppColors.secondaryBackground
        case .outline: return Color.clear
        }
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .profit: return AppColors.profit
        case .loss: return AppColors.loss
        case .secondary: return AppColors.primaryText
        case .outline: return AppColors.secondaryText
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .outline: return AppColors.border
        default: return Color.clear
        }
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
                        .font(.system(size: size == .compact ? 11 : 13, weight: .semibold))
                }
                Text(title)
                    .font(size == .compact ? AppTypography.captionBold : AppTypography.bodyBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, size == .compact ? 6 : 9)
            .padding(.horizontal, size == .compact ? 8 : 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: size == .compact ? 30 : 38)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: size == .compact ? 8 : 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size == .compact ? 8 : 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: style == .outline ? 1 : 0)
            )
            .shadow(color: style == .primary ? AppColors.brand.opacity(0.25) : Color.clear, radius: 4, x: 0, y: 2)
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .buttonStyle(ApplePressableButtonStyle())
        .disabled(isLoading)
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary: return AppColors.brand
        case .secondary: return AppColors.secondaryBackground
        case .outline: return Color.clear
        case .destructive: return AppColors.loss
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary: return AppColors.primaryText
        case .outline: return AppColors.primaryText
        }
    }
}

/// Domain specification matching core web repository
public struct AppMonetaryText: View {
    private let valueText: String
    private let isPrivate: Bool
    private let font: Font
    private let color: Color
    
    public init(
        _ valueText: String,
        isPrivate: Bool,
        font: Font = AppTypography.financialNumber(),
        color: Color = AppColors.primaryText
    ) {
        self.valueText = valueText
        self.isPrivate = isPrivate
        self.font = font
        self.color = color
    }
    
    public var body: some View {
        Text(isPrivate ? "••••" : valueText)
            .font(font)
            .monospacedDigit()
            .foregroundColor(color)
    }
}

/// Domain specification matching core web repository
public struct EmptyStateView: View {
    private let title: String
    private let description: String
    private let iconName: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    
    public init(
        title: String,
        description: String = "",
        icon: String = "tray",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.description = description
        self.iconName = icon
        self.actionTitle = actionTitle
        self.action = action
    }
    
    public init(
        icon: String = "tray",
        title: String,
        message: String = "",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.description = message
        self.iconName = icon
        self.actionTitle = actionTitle
        self.action = action
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 36))
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
            
            Text(title)
                .font(AppTypography.pageTitle)
                .foregroundColor(AppColors.primaryText)
            
            if !description.isEmpty {
                Text(description)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTypography.bodyBold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.brand)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Standardized loading spinner view
public struct LoadingView: View {
    private let message: String
    
    public init(_ message: String = "Loading...") {
        self.message = message
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(AppColors.brand)
            Text(message)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Domain specification matching core web repository
public struct ErrorBannerView: View {
    private let message: String
    private let onRetry: (() -> Void)?
    
    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.loss)
                .font(.system(size: 14))
            
            Text(message)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(2)
            
            Spacer()
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.brand)
                }
            }
        }
        .padding(10)
        .background(AppColors.loss.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Apple HIG iOS 27 Harmonized Navigation & Control Components

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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 30)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                if let title = title, !title.isEmpty {
                    Text(title)
                        .font(AppTypography.actionPill)
                }
            }
            .foregroundColor(AppColors.primaryText)
            .padding(.horizontal, title != nil ? 9 : 8)
            .padding(.vertical, 6)
            .frame(height: 30)
            .background(AppColors.cardBackground.opacity(0.85))
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
        }
        .buttonStyle(ApplePressableButtonStyle())
        .fixedSize()
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 30)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 30)
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

/// Standardized Apple HIG Menu Picker Chip with chevron and subtle background.
public struct AppleMenuChip<Content: View>: View {
    private let title: String
    private let selectionText: String
    private let icon: String?
    private let menuContent: Content
    
    public init(
        title: String? = nil,
        selectionText: String,
        icon: String? = nil,
        @ViewBuilder menuContent: () -> Content
    ) {
        self.title = title ?? ""
        self.selectionText = selectionText
        self.icon = icon
        self.menuContent = menuContent()
    }
    
    public var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                if !title.isEmpty {
                    Text("\(title):")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                }
                Text(selectionText)
                    .font(AppTypography.menuChip)
                    .foregroundColor(AppColors.primaryText)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.secondaryBackground.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}

/// Universal Apple HIG Sliding Segmented Bar with matched geometry, spring physics, and haptics.
public struct AppleSlidingSegmentedBar<T: Hashable & Identifiable>: View {
    @Binding private var selection: T
    private let items: [T]
    private let titleFor: (T) -> String
    private let iconFor: ((T) -> String?)?
    private let badgeCountFor: ((T) -> Int?)?
    @Namespace private var segmentNamespace
    
    public init(
        selection: Binding<T>,
        items: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil,
        badgeCountFor: ((T) -> Int?)? = nil
    ) {
        self._selection = selection
        self.items = items
        self.titleFor = titleFor
        self.iconFor = iconFor
        self.badgeCountFor = badgeCountFor
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = iconFor?(item) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(titleFor(item))
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        
                        if let count = badgeCountFor?(item), count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(isSelected ? AppColors.brand : AppColors.cardBackground)
                                .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColors.cardBackground)
                                .matchedGeometryEffect(id: "ACTIVE_SEGMENT", in: segmentNamespace)
                                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ApplePressableButtonStyle())
            }
        }
        .padding(3)
        .background(AppColors.secondaryBackground.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.brand)
                    }
                    
                    Text(titleFor(selection))
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.border.opacity(0.8), lineWidth: 1)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
}

