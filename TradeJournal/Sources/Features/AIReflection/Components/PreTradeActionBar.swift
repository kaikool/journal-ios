import SwiftUI

// MARK: - Pre-Trade Action Bar
public struct PreTradeActionBar: View {
    public let isSavedToNotebook: Bool
    public let showCopiedAlert: Bool
    public let onSaveNotebook: () -> Void
    public let onLinkTicket: (() -> Void)?
    public let onCopy: () -> Void
    public let onRegenerate: () -> Void
    
    public init(
        isSavedToNotebook: Bool,
        showCopiedAlert: Bool,
        onSaveNotebook: @escaping () -> Void,
        onLinkTicket: (() -> Void)? = nil,
        onCopy: @escaping () -> Void,
        onRegenerate: @escaping () -> Void
    ) {
        self.isSavedToNotebook = isSavedToNotebook
        self.showCopiedAlert = showCopiedAlert
        self.onSaveNotebook = onSaveNotebook
        self.onLinkTicket = onLinkTicket
        self.onCopy = onCopy
        self.onRegenerate = onRegenerate
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Save to Notebook
            AppSecondaryButton(
                isSavedToNotebook ? "Saved" : "Save Note",
                icon: isSavedToNotebook ? "checkmark" : "bookmark",
                isEnabled: !isSavedToNotebook,
                fullWidth: true,
                height: 36,
                action: onSaveNotebook
            )
            
            // Link to Trade (available when note is saved)
            if isSavedToNotebook, let linkAction = onLinkTicket {
                AppSecondaryButton(
                    "Link Trade",
                    icon: "link",
                    height: 36,
                    action: linkAction
                )
            }
            
            // Copy
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
