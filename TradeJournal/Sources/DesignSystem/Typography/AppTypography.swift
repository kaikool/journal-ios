import SwiftUI

/// Hệ typography chuẩn xác 100% đối chiếu với hệ thống Tailwind trong `source-repo/apps/web`:
/// - Tiêu đề thẻ (CardTitle): 11px, weight: .medium, uppercase, tracking +0.88
/// - Chỉ số chính (Hero Metric): 26px, weight: .semibold, số monospaced
/// - Tiêu đề trang (PageTitle): 16px, weight: .semibold
/// - Văn bản thông thường (Body): 13px
/// - Nhãn phụ (Caption/Subtitle): 11px
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
    public static let badge = Font.system(size: 10, weight: .semibold)
    public static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    
    // Backwards-compatible iOS definitions
    public static let largeTitle = Font.system(size: 28, weight: .bold)
    public static let title = Font.system(size: 20, weight: .semibold)
    public static let title2 = Font.system(size: 18, weight: .semibold)
    public static let title3 = Font.system(size: 16, weight: .semibold)
    public static let headline = Font.system(size: 14, weight: .semibold)
    public static let subheadline = Font.system(size: 12, weight: .regular)
    public static let subheadlineBold = Font.system(size: 12, weight: .semibold)
    
    /// Font chuyên biệt cho số tiền và giá tài chính: cố định bề ngang chữ số (monospaced digits)
    /// để các cột số không bị rung lắc khi cập nhật.
    public static func financialNumber(size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}
