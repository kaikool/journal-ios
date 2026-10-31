import SwiftUI

public enum MetricTrend {
    case up
    case down
    case neutral
    
    public var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .neutral: return "minus"
        }
    }
    
    public var color: Color {
        switch self {
        case .up: return AppColors.profit
        case .down: return AppColors.loss
        case .neutral: return AppColors.secondaryText
        }
    }
}

/// Unified Apple HIG Metric / KPI Tile
/// Displays a financial KPI with title, formatted value, optional trend, subtitle, or icon.
public struct AppMetricTile: View {
    public let title: String
    public let value: String
    public let valueColor: Color
    public let subtitle: String?
    public let icon: String?
    public let trend: MetricTrend?
    public let alignment: HorizontalAlignment
    public let minHeight: CGFloat
    
    public init(
        _ title: String,
        value: String,
        color: Color = AppColors.primaryText,
        subtitle: String? = nil,
        icon: String? = nil,
        trend: MetricTrend? = nil,
        alignment: HorizontalAlignment = .center,
        minHeight: CGFloat = 52
    ) {
        self.title = title
        self.value = value
        self.valueColor = color
        self.subtitle = subtitle
        self.icon = icon
        self.trend = trend
        self.alignment = alignment
        self.minHeight = minHeight
    }
    
    public var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(AppTypography.microCaption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Text(title.uppercased())
                    .font(AppTypography.microCaption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .tracking(0.5)
            }
            
            HStack(spacing: 3) {
                Text(value)
                    .font(AppTypography.statValue)
                    .monospacedDigit()
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                if let trend = trend {
                    Image(systemName: trend.icon)
                        .font(AppTypography.badgeMicro)
                        .foregroundColor(trend.color)
                }
            }
            
            if let sub = subtitle, !sub.isEmpty {
                Text(sub)
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
        .frame(minHeight: minHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppColors.secondaryBackground.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
        )
    }
}
