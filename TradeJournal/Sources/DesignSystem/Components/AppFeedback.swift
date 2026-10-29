import SwiftUI

/// Monetary text with privacy mode masking
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

/// Standardized empty state view with title, message, and action
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

/// Standardized error banner view
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
