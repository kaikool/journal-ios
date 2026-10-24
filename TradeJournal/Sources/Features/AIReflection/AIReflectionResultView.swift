import SwiftUI
import UIKit

// MARK: - Standard Minimalist AI Reflection Document Viewer (Apple HIG)
// Presents AI coaching insights as a clean, unified document with sleek typography and 1-tap Notebook integration
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
            // Unified Clean Document Card
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    // Document Header with Live AI Verification Badge
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: template?.icon ?? "sparkles")
                                .foregroundColor(AppColors.primaryText)
                                .font(.system(size: 14, weight: .semibold))
                            Text(template?.title ?? "AI Performance Reflection")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppColors.profit)
                                .frame(width: 6, height: 6)
                            Text("LIVE AI")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.6))
                    
                    // Unified Document Content (Parsed for beautiful typography)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(parseDocumentBlocks(resultText), id: \.id) { block in
                            renderBlock(block)
                        }
                    }
                    .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            
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
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text("Saved to Notebook under 'AI Reflections'")
                        .font(AppTypography.caption)
                }
                .foregroundColor(AppColors.secondaryText)
            }
        }
    }
    
    // MARK: - Block Renderer
    @ViewBuilder
    private func renderBlock(_ block: DocumentBlock) -> some View {
        switch block.kind {
        case .header:
            Text(LocalizedStringKey(block.content))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)
                .padding(.top, 4)
            
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(AppColors.brand)
                    .frame(width: 3)
                    .cornerRadius(1.5)
                
                Text(LocalizedStringKey(block.content))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
                    .padding(.vertical, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground.opacity(0.6))
            .cornerRadius(8)
            
        case .numbered(let num):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 20, alignment: .leading)
                
                Text(LocalizedStringKey(block.content))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
            }
            .padding(.leading, 2)
            
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.top, 1)
                
                Text(LocalizedStringKey(block.content))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
            }
            .padding(.leading, 4)
            
        case .paragraph:
            Text(LocalizedStringKey(block.content))
                .font(AppTypography.body)
                .foregroundColor(AppColors.primaryText)
                .lineSpacing(4)
        }
    }
    
    // MARK: - Document Block Structure & Parser
    private struct DocumentBlock: Identifiable {
        let id = UUID()
        enum Kind { case header, quote, numbered(Int), bullet, paragraph }
        let kind: Kind
        let content: String
    }
    
    private func sanitizeMarkdown(_ str: String) -> String {
        var s = str.replacingOccurrences(of: "* *", with: "*")
        s = s.replacingOccurrences(of: "• •", with: "•")
        s = s.replacingOccurrences(of: "- -", with: "-")
        return s
    }
    
    private func parseDocumentBlocks(_ text: String) -> [DocumentBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [DocumentBlock] = []
        var paragraphBuffer: [String] = []
        
        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let joined = paragraphBuffer.joined(separator: " ")
                blocks.append(DocumentBlock(kind: .paragraph, content: sanitizeMarkdown(joined)))
                paragraphBuffer = []
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            
            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                flushParagraph()
                let clean = trimmed.replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
                    .replacingOccurrences(of: "# ", with: "")
                blocks.append(DocumentBlock(kind: .header, content: sanitizeMarkdown(clean)))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                let clean = trimmed.replacingOccurrences(of: "> ", with: "")
                blocks.append(DocumentBlock(kind: .quote, content: sanitizeMarkdown(clean)))
            } else if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(trimmed[match])
                let digits = prefix.filter { $0.isNumber }
                let num = Int(digits) ?? 1
                var clean = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                clean = sanitizeMarkdown(clean)
                blocks.append(DocumentBlock(kind: .numbered(num), content: clean))
            } else if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                var clean = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                while clean.hasPrefix("* ") || clean.hasPrefix("• ") || clean.hasPrefix("- ") {
                    clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                clean = sanitizeMarkdown(clean)
                blocks.append(DocumentBlock(kind: .bullet, content: clean))
            } else {
                paragraphBuffer.append(trimmed)
            }
        }
        flushParagraph()
        
        return blocks.isEmpty ? [DocumentBlock(kind: .paragraph, content: sanitizeMarkdown(text))] : blocks
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
            _ = try dataStore.createNote(
                folderId: folder.id,
                title: title,
                content: resultText,
                tags: tags,
                tradeKey: nil,
                dayDate: JournalIds.todayDateString()
            )
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
