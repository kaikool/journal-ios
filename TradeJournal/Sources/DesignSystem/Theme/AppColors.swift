import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum AppColors {
    // Semantic Financial Colors
    public static let profit = Color(red: 34/255, green: 197/255, blue: 94/255)   // Emerald green (#22c55e)
    public static let loss = Color(red: 239/255, green: 68/255, blue: 68/255)     // Crimson red (#ef4444)
    public static let breakeven = Color(red: 148/255, green: 163/255, blue: 184/255) // Slate gray (#94a3b8)
    
    // Brand & Accents
    public static let accent = Color(red: 59/255, green: 130/255, blue: 246/255)   // Blue (#3b82f6)
    public static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)  // Amber (#f59e0b)
    
    // Text
    public static let primaryText = Color.primary
    public static let secondaryText = Color.secondary
    
    // Backgrounds & Surfaces
    #if canImport(UIKit)
    public static let background = Color(UIColor.systemBackground)
    public static let secondaryBackground = Color(UIColor.secondarySystemBackground)
    public static let cardBackground = Color(UIColor.tertiarySystemBackground)
    public static let border = Color(UIColor.separator)
    #else
    public static let background = Color(NSColor.windowBackgroundColor)
    public static let secondaryBackground = Color(NSColor.underPageBackgroundColor)
    public static let cardBackground = Color(NSColor.controlBackgroundColor)
    public static let border = Color(NSColor.separatorColor)
    #endif
}
