import SwiftUI

public enum AppTypography {
    public static let largeTitle = Font.system(.largeTitle, design: .default).weight(.bold)
    public static let title = Font.system(.title, design: .default).weight(.semibold)
    public static let title2 = Font.system(.title2, design: .default).weight(.semibold)
    public static let title3 = Font.system(.title3, design: .default).weight(.semibold)
    public static let headline = Font.system(.headline, design: .default).weight(.medium)
    public static let body = Font.system(.body, design: .default)
    public static let bodyBold = Font.system(.body, design: .default).weight(.bold)
    public static let subheadline = Font.system(.subheadline, design: .default)
    public static let subheadlineBold = Font.system(.subheadline, design: .default).weight(.bold)
    public static let caption = Font.system(.caption, design: .default)
    public static let captionBold = Font.system(.caption, design: .default).weight(.bold)
    public static let monoCaption = Font.system(.caption, design: .monospaced)
    
    /// Font chuyên biệt cho số tiền và giá tài chính: cố định bề ngang chữ số (monospaced digits)
    /// để các cột số không bị rung lắc khi cập nhật.
    public static func financialNumber(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}
