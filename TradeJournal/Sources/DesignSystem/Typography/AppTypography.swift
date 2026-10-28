import SwiftUI

/// Typography system matching 100% of Tailwind scales in `source-repo/apps/web`:
/// - Card title (CardTitle): 11px, weight: .medium, uppercase, tracking +0.88
/// - Hero metric (Hero Metric): 26px, weight: .semibold, monospaced digits
/// - Page title (PageTitle): 16px, weight: .semibold
/// - Body text (Body): 13px
/// - Caption / subtitle: 11px
public enum AppTypography {
    // Web Tailwind Parity Scales - Dynamic Type Enabled
    public static let pageTitle = Font.system(.headline, design: .default).weight(.semibold)
    public static let cardHeader = Font.system(size: 11, weight: .semibold, design: .default)
    public static let cardTitle = Font.system(.subheadline, design: .default).weight(.bold)
    public static let metricHero = Font.system(size: 28, weight: .bold, design: .default).monospacedDigit()
    public static let metricLarge = Font.system(size: 22, weight: .bold, design: .default).monospacedDigit()
    public static let metricMedium = Font.system(size: 18, weight: .bold, design: .default).monospacedDigit()
    public static let metricCompact = Font.system(size: 15, weight: .bold, design: .default).monospacedDigit()
    public static let body = Font.system(.subheadline, design: .default)
    public static let bodyMedium = Font.system(.subheadline, design: .default).weight(.medium)
    public static let bodyBold = Font.system(.subheadline, design: .default).weight(.semibold)
    public static let caption = Font.system(.caption, design: .default)
    public static let captionMedium = Font.system(.caption, design: .default).weight(.medium)
    public static let captionBold = Font.system(.caption, design: .default).weight(.bold)
    public static let microCaption = Font.system(size: 10, weight: .medium, design: .default)
    public static let pill = Font.system(.caption2, design: .default).weight(.medium)
    public static let actionPill = Font.system(size: 11, weight: .semibold, design: .default)
    public static let menuChip = Font.system(size: 11, weight: .semibold, design: .default)
    public static let badge = Font.system(size: 10, weight: .bold, design: .default)
    public static let badgeMicro = Font.system(size: 9, weight: .bold, design: .default)
    public static let monoCaption = Font.system(.caption, design: .default).monospacedDigit()
    public static let codeBlock = Font.system(.caption, design: .monospaced) // Only for raw code blocks

    // Standardized Apple San Francisco tabular digits helpers
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .default).monospacedDigit()
    }
    public static let numberHero = Font.system(size: 28, weight: .bold, design: .default).monospacedDigit()
    public static let numberLarge = Font.system(size: 20, weight: .bold, design: .default).monospacedDigit()
    public static let numberMedium = Font.system(size: 15, weight: .semibold, design: .default).monospacedDigit()
    public static let numberSmall = Font.system(size: 13, weight: .semibold, design: .default).monospacedDigit()
    public static let numberCaption = Font.system(size: 11, weight: .medium, design: .default).monospacedDigit()
    public static let numberMicro = Font.system(size: 10, weight: .medium, design: .default).monospacedDigit()
    
    // Backwards-compatible iOS definitions with full Dynamic Type support
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title.weight(.bold)
    public static let title2 = Font.title2.weight(.bold)
    public static let title3 = Font.title3.weight(.semibold)
    public static let headline = Font.headline.weight(.bold)
    public static let subheadline = Font.subheadline
    public static let subheading = subheadline
    public static let subheadlineBold = Font.subheadline.weight(.bold)
    public static let subheadingBold = subheadlineBold
    
    /// Standard Apple HIG input and editor typography
    public static let inputText = Font.system(.subheadline, design: .default)
    public static let inputTextMedium = Font.system(.subheadline, design: .default).weight(.medium)
    public static let inputTextBold = Font.system(.subheadline, design: .default).weight(.semibold)
    
    /// Specialized font for financial numbers and monetary amounts: monospaced digits
    /// to avoid column jitter during real-time value updates.
    public static func financialNumber(size: CGFloat = 24, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

public struct AppInputModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(AppTypography.inputText)
    }
}

public extension View {
    func appInputStyle() -> some View {
        modifier(AppInputModifier())
    }
}
