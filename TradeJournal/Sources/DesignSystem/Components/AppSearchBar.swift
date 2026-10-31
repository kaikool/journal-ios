import SwiftUI

/// Unified Apple HIG Search Bar
/// 34pt Capsule search bar with magnifying glass icon, clear button, and subtle border stroke.
public struct AppSearchBar: View {
    @Binding public var text: String
    public let placeholder: String
    public let height: CGFloat
    public let onCommit: (() -> Void)?
    
    public init(
        _ placeholder: String = "Search...",
        text: Binding<String>,
        height: CGFloat = 34,
        onCommit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.height = height
        self.onCommit = onCommit
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
            
            TextField(placeholder, text: $text, onCommit: {
                onCommit?()
            })
            .font(AppTypography.caption)
            .foregroundColor(AppColors.primaryText)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            
            if !text.isEmpty {
                Button(action: {
                    NativeHaptics.lightImpact()
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(AppColors.secondaryBackground.opacity(0.65))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
        )
    }
}
