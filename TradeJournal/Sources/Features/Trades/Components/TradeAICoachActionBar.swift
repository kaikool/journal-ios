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
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(isSavedToNotes ? AppColors.profit : AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                )
            }
            .disabled(isSavedToNotes)
            
            // Save to Notebook
            Button(action: onSaveNotebook) {
                HStack(spacing: 5) {
                    Image(systemName: isSavedToNotebook ? "checkmark" : "bookmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isSavedToNotebook ? "Saved" : "Notebook")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(isSavedToNotebook ? AppColors.profit : AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                )
            }
            .disabled(isSavedToNotebook)
            
            // Copy Button
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(showCopiedAlert ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                )
            }
            
            // Regenerate
            Button(action: onRegenerate) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                    )
            }
        }
    }
}
