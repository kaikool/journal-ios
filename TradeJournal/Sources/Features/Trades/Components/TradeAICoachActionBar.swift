import SwiftUI

// MARK: - Trade AI Coach Bottom Action Bar
// Minimalist toolbar providing Append to Notes, Notebook persistence, Copy, and Regenerate
public struct TradeAICoachActionBar: View {
    public let isSavedToNotes: Bool
    public let isSavedToNotebook: Bool
    public let showCopiedAlert: Bool
    public let onAppendNotes: () -> Void
    public let onSaveNotebook: () -> Void
    public let onCopy: () -> Void
    public let onRegenerate: () -> Void
    
    public init(
        isSavedToNotes: Bool,
        isSavedToNotebook: Bool,
        showCopiedAlert: Bool,
        onAppendNotes: @escaping () -> Void,
        onSaveNotebook: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onRegenerate: @escaping () -> Void
    ) {
        self.isSavedToNotes = isSavedToNotes
        self.isSavedToNotebook = isSavedToNotebook
        self.showCopiedAlert = showCopiedAlert
        self.onAppendNotes = onAppendNotes
        self.onSaveNotebook = onSaveNotebook
        self.onCopy = onCopy
        self.onRegenerate = onRegenerate
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Append to Trade Notes
            Button(action: onAppendNotes) {
                HStack(spacing: 5) {
                    Image(systemName: isSavedToNotes ? "checkmark" : "note.text.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isSavedToNotes ? "Appended" : "Append to Notes")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(isSavedToNotes ? AppColors.profit : AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .disabled(isSavedToNotes)
            
            // Save to Notebook
            Button(action: onSaveNotebook) {
                HStack(spacing: 5) {
                    Image(systemName: isSavedToNotebook ? "checkmark" : "bookmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isSavedToNotebook ? "Saved" : "Notebook")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(isSavedToNotebook ? AppColors.profit : AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .disabled(isSavedToNotebook)
            
            // Copy Button
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(showCopiedAlert ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            // Regenerate
            AppIconPodButton(icon: "arrow.clockwise", size: 36, label: "Regenerate", action: onRegenerate)
        }
    }
}
