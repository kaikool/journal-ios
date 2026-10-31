import SwiftUI

/// Win / Loss ratio bar visualization matching web journal-progress-visual
public struct AppRatioBar: View {
    private let greenRatio: Double
    @State private var animatedRatio: Double = 0.5
    
    public init(greenRatio: Double) {
        self.greenRatio = min(max(greenRatio, 0.05), 0.95)
    }
    
    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule()
                    .fill(AppColors.profit)
                    .frame(width: max(6, proxy.size.width * CGFloat(animatedRatio) - 1))
                
                Capsule()
                    .fill(AppColors.loss)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 6)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
                animatedRatio = greenRatio
            }
        }
        .onChange(of: greenRatio) { newRatio in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                animatedRatio = newRatio
            }
        }
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
        case brand
        case warning
        case secondary
        case outline
        case custom(color: Color)
    }
    
    private let text: String
    private let icon: String?
    private let variant: Variant
    
    public init(_ text: String, icon: String? = nil, variant: Variant = .secondary) {
        self.text = text
        self.icon = icon
        self.variant = variant
    }
    
    public init(_ text: String, icon: String? = nil, color: Color) {
        self.text = text
        self.icon = icon
        if color == AppColors.profit {
            self.variant = .profit
        } else if color == AppColors.loss {
            self.variant = .loss
        } else if color == AppColors.brand {
            self.variant = .brand
        } else if color == AppColors.warning {
            self.variant = .warning
        } else {
            self.variant = .custom(color: color)
        }
    }
    
    public init(text: String, icon: String? = nil, color: Color) {
        self.init(text, icon: icon, color: color)
    }
    
    public var body: some View {
        HStack(spacing: 3.5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: isOutline ? 0.8 : 0.5)
        )
    }
    
    private var isOutline: Bool {
        if case .outline = variant { return true }
        return false
    }
    
    private var backgroundColor: Color {
        switch variant {
        case .profit: return AppColors.profit.opacity(0.14)
        case .loss: return AppColors.loss.opacity(0.14)
        case .brand: return AppColors.brand.opacity(0.12)
        case .warning: return AppColors.warning.opacity(0.12)
        case .secondary: return AppColors.secondaryBackground
        case .outline: return Color.clear
        case .custom(let color): return color.opacity(0.12)
        }
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .profit: return AppColors.profit
        case .loss: return AppColors.loss
        case .brand: return AppColors.brand
        case .warning: return AppColors.warning
        case .secondary: return AppColors.primaryText
        case .outline: return AppColors.secondaryText
        case .custom(let color): return color
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .outline: return AppColors.border
        case .brand: return AppColors.brand.opacity(0.3)
        case .profit: return AppColors.profit.opacity(0.3)
        case .loss: return AppColors.loss.opacity(0.3)
        case .warning: return AppColors.warning.opacity(0.3)
        case .secondary: return AppColors.border.opacity(0.4)
        case .custom(let color): return color.opacity(0.3)
        }
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(AppColors.secondaryBackground.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}
