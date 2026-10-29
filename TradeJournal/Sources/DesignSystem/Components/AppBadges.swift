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
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
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
