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
            AppSecondaryButton(
                isSavedToNotes ? "Appended" : "Append to Notes",
                icon: isSavedToNotes ? "checkmark" : "note.text.badge.plus",
                isEnabled: !isSavedToNotes,
                fullWidth: true,
                height: 36,
                action: onAppendNotes
            )
            
            // Save to Notebook
            AppSecondaryButton(
                isSavedToNotebook ? "Saved" : "Notebook",
                icon: isSavedToNotebook ? "checkmark" : "bookmark",
                isEnabled: !isSavedToNotebook,
                fullWidth: true,
                height: 36,
                action: onSaveNotebook
            )
            
            // Copy Button
            AppSecondaryButton(
                showCopiedAlert ? "Copied" : "Copy",
                icon: showCopiedAlert ? "checkmark" : "doc.on.doc",
                height: 36,
                action: onCopy
            )
            
            // Regenerate
            AppIconPodButton(icon: "arrow.clockwise", size: 36, label: "Regenerate", action: onRegenerate)
        }
    }
}
