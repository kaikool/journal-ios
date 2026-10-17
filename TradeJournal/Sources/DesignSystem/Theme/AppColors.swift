import SwiftUI

extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Hệ màu Trading Terminal dark-first chuẩn xác 100% từ `source-repo/apps/web/src/app/globals.css`
public enum AppColors {
    // Canvas & Surfaces
    public static let background = Color(hex: "#08080a")
    public static let cardBackground = Color(hex: "#101013")
    public static let popoverBackground = Color(hex: "#131317")
    public static let secondaryBackground = Color(hex: "#17171b")
    public static let surface = Color(hex: "#101013")
    public static let input = Color(hex: "#26262c")
    public static let border = Color(hex: "#222228")
    
    // Brand & Interactive Accents (LuxAlgo cyan blue)
    public static let brand = Color(hex: "#1197e2")
    public static let accent = Color(hex: "#1197e2")
    public static let ring = Color(hex: "#1197e2")
    
    // Financial P&L convention (Traders Emerald / Crimson)
    public static let profit = Color(hex: "#0ca30c")
    public static let profitFill = Color(hex: "#0ca30c").opacity(0.15)
    public static let loss = Color(hex: "#d03b3b")
    public static let lossFill = Color(hex: "#d03b3b").opacity(0.15)
    public static let breakeven = Color(hex: "#8b8b95")
    public static let warning = Color(hex: "#eda100")
    
    // Typography & Accents
    public static let primaryText = Color(hex: "#f4f4f4")
    public static let secondaryText = Color(hex: "#9c9ca6")
    public static let muted = Color(hex: "#17171b")
    public static let mutedForeground = Color(hex: "#9c9ca6")
    public static let mutedText = Color(hex: "#9c9ca6")
    public static let brandTextOnDark = Color(hex: "#ffffff")
}
