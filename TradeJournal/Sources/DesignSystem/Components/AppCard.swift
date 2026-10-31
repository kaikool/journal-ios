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

public struct AppCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    
    public init(cornerRadius: CGFloat = 16, padding: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

extension View {
    public func appCardStyle(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
    
    public func appSubCardStyle(cornerRadius: CGFloat = 8, padding: CGFloat = 10) -> some View {
        modifier(AppSubCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

/// Standardized Sub-Card / Inset Pod modifier using secondaryBackground
public struct AppSubCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    
    public init(cornerRadius: CGFloat = 8, padding: CGFloat = 10) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Standardized Chat Message Bubble container for AI Coaching & Reflection threads
public struct AppChatBubble<Content: View>: View {
    public enum Role {
        case user
        case assistant
    }
    
    public let role: Role
    public let content: Content
    
    public init(role: Role = .user, @ViewBuilder content: () -> Content) {
        self.role = role
        self.content = content()
    }
    
    public var body: some View {
        HStack {
            if role == .user {
                Spacer(minLength: 32)
                content
                    .font(AppTypography.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                content
                Spacer(minLength: 32)
            }
        }
    }
}

/// Standardized Floating HUD bar container for landscape charts and floating controls
public struct AppFloatingBar<Content: View>: View {
    private let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(AppColors.cardBackground.opacity(0.94))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
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
                .font(AppTypography.cardHeader)
                .tracking(0.5)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            Spacer()
            
            if let icon = icon {
                Image(systemName: icon)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
            }
        }
    }
}
