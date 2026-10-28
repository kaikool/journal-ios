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
            Button(action: onSaveNotebook) {
                HStack(spacing: 5) {
                    Image(systemName: isSavedToNotebook ? "checkmark" : "bookmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isSavedToNotebook ? "Saved" : "Save Note")
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
            
            // Link to Trade (available when note is saved)
            if isSavedToNotebook, let linkAction = onLinkTicket {
                Button(action: linkAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .medium))
                        Text("Link Trade")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                    )
                }
            }
            
            // Copy
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
