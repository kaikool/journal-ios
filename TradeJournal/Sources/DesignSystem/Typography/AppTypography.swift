import SwiftUI

/// Unified Typography System for TradeJournal iOS
/// Conforms strictly to the 9-Tier Semantic Scale:
/// - Tier 1: Hero Financial Display (26-28pt bold, monospaced digits)
/// - Tier 2: Major Metric Display (20-22pt bold, monospaced digits)
/// - Tier 3: Page & Sheet Titles (17pt bold rounded)
/// - Tier 4: Section & Card Headers (13.5-14pt bold)
/// - Tier 5: Primary Row Title & Form Inputs (14-14.5pt semibold/medium)
/// - Tier 6: Secondary Subtitles & Form Labels (12-12.5pt medium/regular)
/// - Tier 7: Key-Value Metric Pairs (Label 11.5pt medium, Value 13pt bold mono)
/// - Tier 8: Badges, Pills & Action Buttons (Action 12-13.5pt, Badge 10pt bold, Micro 9pt)
/// - Tier 9: Micro Metadata & Footers (10-10.5pt regular/medium)
public enum AppTypography {
    
    // MARK: - Tier 1: Hero Financial Display (Net P&L, Total Balance)
    public static let displayHero = Font.system(size: 26, weight: .bold, design: .default).monospacedDigit()
    public static let displayHeroLarge = Font.system(size: 28, weight: .bold, design: .default).monospacedDigit()
    public static let metricHero = Font.system(size: 28, weight: .bold, design: .default).monospacedDigit()
    public static let numberHero = Font.system(size: 28, weight: .bold, design: .default).monospacedDigit()
    
    // MARK: - Tier 2: Major Financial Metrics (KPI Cards, Equity, Drawdown)
    public static let displayMajor = Font.system(size: 21, weight: .bold, design: .default).monospacedDigit()
    public static let displayMedium = Font.system(size: 18, weight: .bold, design: .default).monospacedDigit()
    public static let metricLarge = Font.system(size: 22, weight: .bold, design: .default).monospacedDigit()
    public static let metricMedium = Font.system(size: 18, weight: .bold, design: .default).monospacedDigit()
    public static let metricCompact = Font.system(size: 15, weight: .bold, design: .default).monospacedDigit()
    public static let numberLarge = Font.system(size: 20, weight: .bold, design: .default).monospacedDigit()
    public static let numberMedium = Font.system(size: 15, weight: .semibold, design: .default).monospacedDigit()
    
    // MARK: - Tier 3: Page & Modal Navigation Titles
    public static let pageTitle = Font.system(size: 17, weight: .bold, design: .rounded)
    public static let pageHeroTitle = Font.system(size: 17, weight: .bold, design: .rounded)
    public static let sheetTitle = Font.system(size: 17, weight: .bold, design: .rounded)
    
    // MARK: - Tier 4: Section & Card Headers
    public static let sectionHeader = Font.system(size: 14, weight: .bold, design: .default)
    public static let cardHeader = Font.system(size: 14, weight: .bold, design: .default)
    public static let cardTitle = Font.system(size: 14, weight: .bold, design: .default)
    public static let cardHeaderUppercase = Font.system(size: 11.5, weight: .semibold, design: .default)
    
    // MARK: - Tier 5: Primary Row Titles & Form Inputs
    public static let rowPrimary = Font.system(size: 14.5, weight: .bold, design: .default)
    public static let rowTitle = Font.system(size: 14, weight: .semibold, design: .default)
    public static let formInput = Font.system(size: 14, weight: .medium, design: .default)
    public static let formInputMono = Font.system(size: 14, weight: .semibold, design: .default).monospacedDigit()
    public static let inputText = Font.system(size: 14, weight: .medium, design: .default)
    public static let inputTextMedium = Font.system(size: 14, weight: .medium, design: .default)
    public static let inputTextBold = Font.system(size: 14, weight: .semibold, design: .default)
    public static let body = Font.system(size: 13.5, weight: .regular, design: .default)
    public static let bodyMedium = Font.system(size: 13.5, weight: .medium, design: .default)
    public static let bodyBold = Font.system(size: 13.5, weight: .semibold, design: .default)
    
    // MARK: - Tier 6: Secondary Subtitles & Form Labels
    public static let rowSecondary = Font.system(size: 12.5, weight: .regular, design: .default)
    public static let rowSubtitle = Font.system(size: 12.5, weight: .regular, design: .default)
    public static let formLabel = Font.system(size: 12.5, weight: .medium, design: .default)
    public static let subheadline = Font.system(size: 13, weight: .regular, design: .default)
    public static let subheading = Font.system(size: 13, weight: .regular, design: .default)
    public static let subheadlineBold = Font.system(size: 13, weight: .semibold, design: .default)
    public static let subheadingBold = Font.system(size: 13, weight: .semibold, design: .default)
    
    // MARK: - Tier 7: Key-Value Metric Pairs
    public static let statLabel = Font.system(size: 11.5, weight: .medium, design: .default)
    public static let statValue = Font.system(size: 13, weight: .bold, design: .default).monospacedDigit()
    public static let statValueMedium = Font.system(size: 13, weight: .semibold, design: .default).monospacedDigit()
    public static let numberSmall = Font.system(size: 13, weight: .semibold, design: .default).monospacedDigit()
    public static let numberCaption = Font.system(size: 11.5, weight: .medium, design: .default).monospacedDigit()
    
    // MARK: - Tier 8: Badges, Pills & Action Buttons
    public static let actionButton = Font.system(size: 13.5, weight: .semibold, design: .rounded)
    public static let actionButtonCompact = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let actionPill = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let filterChip = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let menuChip = Font.system(size: 12, weight: .semibold, design: .rounded)
    public static let pill = Font.system(size: 11, weight: .medium, design: .default)
    public static let badge = Font.system(size: 10, weight: .bold, design: .default)
    public static let badgeStandard = Font.system(size: 10, weight: .bold, design: .default)
    public static let badgeMicro = Font.system(size: 9, weight: .bold, design: .default)
    
    // MARK: - Tier 9: Micro Metadata & Footers
    public static let caption = Font.system(size: 11.5, weight: .regular, design: .default)
    public static let captionMedium = Font.system(size: 11.5, weight: .medium, design: .default)
    public static let captionBold = Font.system(size: 11.5, weight: .bold, design: .default)
    public static let monoCaption = Font.system(size: 11.5, weight: .regular, design: .default).monospacedDigit()
    public static let microCaption = Font.system(size: 10, weight: .medium, design: .default)
    public static let numberMicro = Font.system(size: 10, weight: .medium, design: .default).monospacedDigit()
    public static let footnote = Font.system(size: 11, weight: .regular, design: .default)
    public static let disclaimer = Font.system(size: 10, weight: .regular, design: .default)
    public static let codeBlock = Font.system(size: 11.5, weight: .regular, design: .monospaced)
    
    // MARK: - Helper Functions
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .default).monospacedDigit()
    }
    
    public static func financialNumber(size: CGFloat = 24, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .default).monospacedDigit()
    }
    
    // Standard HIG Headings
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title.weight(.bold)
    public static let title2 = Font.title2.weight(.bold)
    public static let title3 = Font.title3.weight(.semibold)
    public static let headline = Font.headline.weight(.bold)
}

public struct AppInputModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(AppTypography.formInput)
    }
}

public extension View {
    func appInputStyle() -> some View {
        modifier(AppInputModifier())
    }
}
