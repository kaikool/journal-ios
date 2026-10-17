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

/// Status badge matching Tailwind `badge.tsx`:
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
            .font(AppTypography.badge)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(borderColor, lineWidth: variant == .outline ? 1 : 0)
            )
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .profit: return AppColors.profit.opacity(0.15)
        case .loss: return AppColors.loss.opacity(0.15)
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

/// Standardized Trading Terminal button
public struct AppButton: View {
    public enum Style {
        case primary, secondary, outline, destructive
    }
    
    private let title: String
    private let iconName: String?
    private let style: Style
    private let isLoading: Bool
    private let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = icon
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                } else if let icon = iconName {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.bodyBold)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColors.border, lineWidth: style == .outline ? 1 : 0)
            )
        }
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
