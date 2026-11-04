import SwiftUI

/// Unified Spacing & Layout Tokens for TradeJournal iOS
/// Adheres strictly to an 8-point geometric grid with 2pt/4pt sub-steps.
public enum AppSpacing {
    /// 2pt: Micro hairline spacing
    public static let xxxSmall: CGFloat = 2
    /// 4pt: Tight element separation (icon to label in badge)
    public static let micro: CGFloat = 4
    public static let xxSmall: CGFloat = 4
    /// 6pt: Standard icon to text horizontal gap
    public static let xSmall: CGFloat = 6
    /// 8pt: Compact spacing between closely related elements
    public static let small: CGFloat = 8
    /// 10pt: Inter-row spacing inside cards
    public static let medium: CGFloat = 10
    /// 12pt: Standard spacing between form inputs and list rows
    public static let standard: CGFloat = 12
    /// 14pt: Card internal vertical gutter
    public static let cardPadding: CGFloat = 14
    /// 16pt: Standard screen margin and major card padding
    public static let pageMargin: CGFloat = 16
    public static let large: CGFloat = 16
    /// 20pt: Spacing between independent card sections
    public static let xLarge: CGFloat = 20
    /// 24pt: Screen header gutter
    public static let sectionGutter: CGFloat = 24
    /// 32pt: Empty state vertical padding
    public static let xxxLarge: CGFloat = 32
}
