import SwiftUI

/// Typography system matching 100% of Tailwind scales in `source-repo/apps/web`:
/// - Card title (CardTitle): 11px, weight: .medium, uppercase, tracking +0.88
/// - Hero metric (Hero Metric): 26px, weight: .semibold, monospaced digits
/// - Page title (PageTitle): 16px, weight: .semibold
/// - Body text (Body): 13px
/// - Caption / subtitle: 11px
public enum AppTypography {
    // Web Tailwind Parity Scales
    public static let pageTitle = Font.system(size: 16, weight: .semibold)
    public static let cardTitle = Font.system(size: 11, weight: .medium)
    public static let metricHero = Font.system(size: 26, weight: .semibold)
    public static let metricLarge = Font.system(size: 20, weight: .semibold)
    public static let metricMedium = Font.system(size: 16, weight: .semibold)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let bodyMedium = Font.system(size: 13, weight: .medium)
    public static let bodyBold = Font.system(size: 13, weight: .semibold)
    public static let caption = Font.system(size: 11, weight: .regular)
    public static let captionMedium = Font.system(size: 11, weight: .medium)
    public static let captionBold = Font.system(size: 11, weight: .bold)
    public static let pill = Font.system(size: 11, weight: .medium)
    public static let actionPill = Font.system(size: 12, weight: .bold)
    public static let menuChip = Font.system(size: 12, weight: .semibold)
    public static let badge = Font.system(size: 10, weight: .semibold)
    public static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    
    // Backwards-compatible iOS definitions
    public static let largeTitle = Font.system(size: 28, weight: .bold)
    public static let title = Font.system(size: 20, weight: .semibold)
    public static let title2 = Font.system(size: 18, weight: .semibold)
    public static let title3 = Font.system(size: 16, weight: .semibold)
    public static let headline = Font.system(size: 14, weight: .semibold)
    public static let subheadline = Font.system(size: 12, weight: .regular)
    public static let subheading = subheadline
    public static let subheadlineBold = Font.system(size: 12, weight: .semibold)
    public static let subheadingBold = subheadlineBold
    
    /// Specialized font for financial numbers and monetary amounts: monospaced digits
    /// to avoid column jitter during real-time value updates.
    public static func financialNumber(size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}
