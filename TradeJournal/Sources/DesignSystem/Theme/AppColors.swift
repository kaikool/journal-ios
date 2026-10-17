import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

#if canImport(UIKit)
extension UIColor {
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}

private func adaptiveColor(dark: String, light: String) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hexString: dark) : UIColor(hexString: light)
    })
}
#else
private func adaptiveColor(dark: String, light: String) -> Color {
    Color(hex: dark)
}
#endif

/// Trading Terminal dark/light mode color palette matching 100% of `source-repo/apps/web/src/app/globals.css`
public enum AppColors {
    // Canvas & Surfaces
    public static let background = adaptiveColor(dark: "#08080a", light: "#f9f9f7")
    public static let cardBackground = adaptiveColor(dark: "#101013", light: "#fcfcfb")
    public static let popoverBackground = adaptiveColor(dark: "#131317", light: "#fcfcfb")
    public static let secondaryBackground = adaptiveColor(dark: "#1b1b20", light: "#f0efec")
    public static let surface = adaptiveColor(dark: "#101013", light: "#fcfcfb")
    public static let input = adaptiveColor(dark: "#26262c", light: "#e1e0d9")
    public static let border = adaptiveColor(dark: "#222228", light: "#e1e0d9")
    
    // Brand & Interactive Accents (LuxAlgo cyan blue)
    public static let brand = adaptiveColor(dark: "#1197e2", light: "#0b7cbd")
    public static let accent = adaptiveColor(dark: "#1197e2", light: "#0b7cbd")
    public static let ring = adaptiveColor(dark: "#1197e2", light: "#0b7cbd")
    
    // Financial P&L convention (Traders Emerald / Crimson)
    public static let profit = adaptiveColor(dark: "#0ca30c", light: "#006300")
    public static let profitFill = adaptiveColor(dark: "#0ca30c", light: "#0ca30c").opacity(0.15)
    public static let loss = Color(hex: "#d03b3b")
    public static let lossFill = Color(hex: "#d03b3b").opacity(0.15)
    public static let breakeven = adaptiveColor(dark: "#8b8b95", light: "#686760")
    public static let warning = adaptiveColor(dark: "#c98500", light: "#eda100")
    
    // Typography & Accents
    public static let primaryText = adaptiveColor(dark: "#f4f4f4", light: "#0b0b0b")
    public static let secondaryText = adaptiveColor(dark: "#9c9ca6", light: "#52514e")
    public static let muted = adaptiveColor(dark: "#17171b", light: "#f0efec")
    public static let mutedForeground = adaptiveColor(dark: "#9c9ca6", light: "#52514e")
    public static let mutedText = adaptiveColor(dark: "#9c9ca6", light: "#52514e")
    public static let brandTextOnDark = Color(hex: "#ffffff")
}
