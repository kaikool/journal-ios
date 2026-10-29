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
    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(16)
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
    public func appCardStyle(cornerRadius: CGFloat = 16) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius))
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
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText.opacity(0.7))
            }
        }
    }
}
