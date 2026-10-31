import SwiftUI

// MARK: - Dual-Mode Journal Notes Card for Trade Detail View
// Supports rendered Markdown presentation (default) and editing via TextEditor
public struct TradeDetailNotesCard: View {
    @Binding public var noteContent: String
    public var onSave: () -> Void
    
    @State private var isEditing: Bool = false
    
    public init(noteContent: Binding<String>, onSave: @escaping () -> Void) {
        self._noteContent = noteContent
        self.onSave = onSave
    }
    
    private var isNoteEmpty: Bool {
        noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                // Header Bar with Mode Toggle
                AppSectionHeader(
                    "Journal notes",
                    actionTitle: isEditing ? "Done" : (isNoteEmpty ? "Add Note" : "Edit"),
                    actionIcon: isEditing ? "checkmark" : (isNoteEmpty ? "plus" : "pencil"),
                    actionColor: isEditing ? AppColors.profit : AppColors.brand,
                    onAction: {
                        if isEditing {
                            onSave()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = false
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = true
                            }
                        }
                    }
                )
                
                // Content: Rendered Markdown or TextEditor
                if isEditing {
                    RichNoteEditor(
                        text: $noteContent,
                        placeholder: "Document setup thesis, entry triggers, emotion state, or lessons learned...",
                        minHeight: 110,
                        allowPreviewToggle: false,
                        onSave: onSave
                    )
                } else {
                    if isNoteEmpty {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = true
                            }
                        }) {
                            HStack {
                                Text("Document setup thesis, entry triggers, emotion state, or lessons learned...")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
                            .background(AppColors.secondaryBackground.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.3), style: StrokeStyle(lineWidth: 0.8, dash: [4]))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        JournalNotesMarkdownView(text: noteContent)
                            .padding(10)
                            .background(AppColors.secondaryBackground.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppColors.border.opacity(0.35), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
    }
}
