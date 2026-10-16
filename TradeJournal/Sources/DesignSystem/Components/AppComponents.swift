import SwiftUI

/// Thẻ chứa nội dung với viền nhẹ và bo góc tinh tế
public struct AppCard<Content: View>: View {
    private let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.border.opacity(0.4), lineWidth: 1)
        )
    }
}

/// Nút bấm chuẩn hóa với nhiều kiểu dáng (Primary, Secondary, Destructive)
public struct AppButton: View {
    public enum Style {
        case primary, secondary, destructive
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
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
                } else if let icon = iconName {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(AppTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(isLoading)
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary: return AppColors.accent
        case .secondary: return AppColors.secondaryBackground
        case .destructive: return AppColors.loss
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary: return .primary
        }
    }
}

/// Huy hiệu trạng thái (Win, Loss, Breakeven, Open, Direction Long/Short)
public struct AppBadge: View {
    private let text: String
    private let color: Color
    
    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }
    
    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }
    
    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

/// Màn hình rỗng (Empty State)
public struct EmptyStateView: View {
    private let title: String
    private let description: String
    private let iconName: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    
    public init(
        title: String,
        description: String,
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
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(AppTypography.title)
                .foregroundColor(.primary)
            
            Text(description)
                .font(AppTypography.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTypography.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AppColors.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Màn hình Loading
public struct LoadingView: View {
    private let message: String
    
    public init(_ message: String = "Đang tải dữ liệu...") {
        self.message = message
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Banner thông báo lỗi kèm nút Retry
public struct ErrorBannerView: View {
    private let message: String
    private let onRetry: (() -> Void)?
    
    public init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.loss)
            
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text("Thử lại")
                        .font(AppTypography.caption.bold())
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .padding(12)
        .background(AppColors.loss.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal)
    }
}
