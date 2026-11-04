import SwiftUI
import UIKit

// MARK: - Standard Minimalist AI Reflection Document Viewer (Apple HIG)
// Presents Risk AI coaching insights as clean, structured section cards with sleek typography and 1-tap Notebook integration
public struct AIReflectionResultView: View {
    public let resultText: String
    public let template: AIReflectionTemplate?
    public let metrics: TradeMetrics?
    public let edgeScore: Double?
    public let language: String
    public let onRegenerate: () -> Void
    
    @ObservedObject private var dataStore = TradeDataStore.shared
    @State private var isSavedToNotebook: Bool = false
    @State private var showCopiedAlert: Bool = false
    @State private var savedNoteTitle: String = ""
    @State private var savedNoteId: String? = nil
    
    public init(
        resultText: String,
        template: AIReflectionTemplate?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        language: String = "vi",
        onRegenerate: @escaping () -> Void
    ) {
        self.resultText = resultText
        self.template = template
        self.metrics = metrics
        self.edgeScore = edgeScore
        self.language = language
        self.onRegenerate = onRegenerate
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Document Header with Risk AI Verification Badge
            AppCard {
                HStack {
                    Text(template?.title ?? "AI Performance Reflection")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    AppBadge("RISK AI", style: .neutral)
                }
                .padding(.vertical, 2)
            }
            
            // Unified Document Content (Parsed into crisp, readable section cards)
            AIDocumentReaderView(text: resultText)
            
            // Bottom Action Bar - Compact, Tidy, Minimalist
            HStack(spacing: 8) {
                // Save to Notebook
                AppSecondaryButton(
                    isSavedToNotebook ? "Saved" : "Save to Notebook",
                    icon: isSavedToNotebook ? "checkmark" : "bookmark",
                    isEnabled: !isSavedToNotebook,
                    fullWidth: true,
                    height: 36,
                    action: saveToNotebook
                )
                
                // Copy Button
                AppSecondaryButton(
                    showCopiedAlert ? "Copied" : "Copy",
                    icon: showCopiedAlert ? "checkmark" : "doc.on.doc",
                    height: 36,
                    action: copyToClipboard
                )
                
                // Regenerate
                AppIconPodButton(icon: "arrow.clockwise", size: 36, label: "Regenerate") {
                    isSavedToNotebook = false
                    onRegenerate()
                }
            }
            
            if isSavedToNotebook && !savedNoteTitle.isEmpty {
                Text("Saved to Notebook under 'AI Reflections'")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
    }
    
    // MARK: - Actions
    private func saveToNotebook() {
        let activeTemplate = template ?? AIReflectionTemplates.defaultTemplate
        let title = AIReflectionTemplates.generateNoteTitle(
            template: activeTemplate,
            metrics: metrics
        )
        var tags = ["#ai-reflections", activeTemplate.tag]
        if activeTemplate.category == .cadence {
            tags.append("#recap")
        }
        if let note = dataStore.upsertNotebookNoteInFolder(
            folderName: "AI Reflections",
            existingNoteId: savedNoteId,
            title: title,
            content: resultText,
            tags: tags
        ) {
            savedNoteId = note.id
            savedNoteTitle = title
            isSavedToNotebook = true
        }
    }
    
    private func copyToClipboard() {
        TradeDataStore.copyToClipboard(resultText) { showCopiedAlert = $0 }
    }
}
