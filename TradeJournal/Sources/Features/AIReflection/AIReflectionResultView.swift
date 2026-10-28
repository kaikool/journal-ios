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
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(AppColors.profit)
                            .frame(width: 6, height: 6)
                        Text("RISK AI")
                            .font(AppTypography.badgeMicro)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(6)
                }
                .padding(.vertical, 2)
            }
            
            // Unified Document Content (Parsed into crisp, readable section cards)
            AIDocumentReaderView(text: resultText)
            
            // Bottom Action Bar - Compact, Tidy, Minimalist
            HStack(spacing: 8) {
                // Save to Notebook
                Button(action: saveToNotebook) {
                    HStack(spacing: 6) {
                        Image(systemName: isSavedToNotebook ? "checkmark" : "bookmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isSavedToNotebook ? "Saved" : "Save to Notebook")
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
                Button(action: copyToClipboard) {
                    HStack(spacing: 5) {
                        Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(showCopiedAlert ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border.opacity(0.7), lineWidth: 0.8)
                    )
                }
                
                // Regenerate
                Button(action: {
                    isSavedToNotebook = false
                    onRegenerate()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
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
            
            if isSavedToNotebook && !savedNoteTitle.isEmpty {
                Text("Saved to Notebook under 'AI Reflections'")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
    }
    
    // MARK: - Actions
    private func saveToNotebook() {
        guard !resultText.isEmpty else { return }
        
        let targetFolderName = "AI Reflections"
        let folder: NotebookFolder
        if let existing = dataStore.folders.first(where: { $0.name.lowercased() == targetFolderName.lowercased() }) {
            folder = existing
        } else {
            do {
                folder = try dataStore.createFolder(name: targetFolderName)
            } catch {
                AppLogger.warning("Failed to create AI Reflections folder: \(error.localizedDescription)")
                return
            }
        }
        
        let activeTemplate = template ?? AIReflectionTemplates.all[0]
        let title = AIReflectionTemplates.generateNoteTitle(
            template: activeTemplate,
            metrics: metrics
        )
        
        var tags = ["#ai-reflections", activeTemplate.tag]
        if activeTemplate.category == .cadence {
            tags.append("#recap")
        }
        
        do {
            if let existingId = savedNoteId {
                _ = try dataStore.patchNote(
                    id: existingId,
                    title: title,
                    content: resultText,
                    tags: tags,
                    folderId: folder.id
                )
            } else {
                let note = try dataStore.createNote(
                    folderId: folder.id,
                    title: title,
                    content: resultText,
                    tags: tags,
                    tradeKey: nil,
                    dayDate: JournalIds.todayDateString()
                )
                savedNoteId = note.id
            }
            savedNoteTitle = title
            isSavedToNotebook = true
            
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
        } catch {
            AppLogger.warning("Failed to save AI reflection note: \(error.localizedDescription)")
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = resultText
        showCopiedAlert = true
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedAlert = false
        }
    }
}
