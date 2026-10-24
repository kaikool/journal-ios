import SwiftUI
import UIKit

// MARK: - Rich Formatted AI Reflection Viewer
// Renders structured Markdown with visual cards, stat badges, quote callouts, and 1-tap Notebook saving
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
    
    private var isVi: Bool { language == "vi" }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // 1. Top Stat Highlights Bar
            if let m = metrics {
                metricsPillsBar(m)
            }
            
            // 2. Parsed Content Cards
            let sections = parseMarkdownSections(resultText)
            if !sections.isEmpty {
                ForEach(sections) { section in
                    sectionCard(section)
                }
            } else {
                // Fallback direct formatted markdown
                AppCard {
                    Text(LocalizedStringKey(resultText))
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .textSelection(.enabled)
                }
            }
            
            // 3. Action Toolbar (Save to Notebook & Copy)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Save to Notebook Button
                    Button(action: saveToNotebook) {
                        HStack(spacing: 6) {
                            Image(systemName: isSavedToNotebook ? "checkmark.circle.fill" : "bookmark.fill")
                                .foregroundColor(isSavedToNotebook ? AppColors.profit : AppColors.brand)
                            Text(isSavedToNotebook ? "Saved to Notebook" : "Save to Notebook")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(isSavedToNotebook ? AppColors.profit : AppColors.brand)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSavedToNotebook ? AppColors.profit.opacity(0.12) : AppColors.brand.opacity(0.12))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSavedToNotebook ? AppColors.profit.opacity(0.3) : AppColors.brand.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(isSavedToNotebook)
                    
                    // Copy Button
                    Button(action: copyToClipboard) {
                        HStack(spacing: 6) {
                            Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                            Text(showCopiedAlert ? "Copied" : "Copy")
                                .font(AppTypography.captionBold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppColors.secondaryBackground)
                        .foregroundColor(AppColors.primaryText)
                        .cornerRadius(10)
                    }
                    
                    // Regenerate Button
                    Button(action: {
                        isSavedToNotebook = false
                        onRegenerate()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppTypography.captionBold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .cornerRadius(10)
                    }
                }
                
                if isSavedToNotebook && !savedNoteTitle.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.caption2)
                        Text("Saved into folder 'AI Reflections': \(savedNoteTitle)")
                            .font(AppTypography.caption)
                    }
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Stat Pills Bar
    private func metricsPillsBar(_ m: TradeMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statPill(
                    icon: "chart.line.uptrend.xyaxis",
                    label: "Win Rate",
                    value: String(format: "%.1f%%", (m.winRate ?? 0) * 100),
                    color: (m.winRate ?? 0) >= 0.5 ? AppColors.profit : AppColors.loss
                )
                
                statPill(
                    icon: "dollarsign.circle",
                    label: "Net PnL",
                    value: (m.netPnl >= 0 ? "+" : "") + "\(m.netPnl)",
                    color: m.netPnl >= 0 ? AppColors.profit : AppColors.loss
                )
                
                if let score = edgeScore {
                    statPill(
                        icon: "bolt.fill",
                        label: "Edge Score",
                        value: "\(Int(score))/100",
                        color: score >= 60 ? AppColors.profit : (score >= 40 ? AppColors.brand : AppColors.loss)
                    )
                }
                
                statPill(
                    icon: "number",
                    label: "Trades",
                    value: "\(m.totalTrades)",
                    color: AppColors.secondaryText
                )
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func statPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(label + ":")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(AppTypography.captionBold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppColors.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 0.8)
        )
    }
    
    // MARK: - Section Card
    private func sectionCard(_ section: ReflectionSection) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                // Section Header
                HStack(spacing: 8) {
                    if let icon = section.icon {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundColor(section.accentColor)
                    }
                    Text(section.title)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                // Section Body Blocks
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.blocks, id: \.id) { block in
                        switch block.kind {
                        case .callout:
                            calloutBox(text: block.content, color: section.accentColor)
                        case .bullet:
                            bulletRow(text: block.content)
                        case .paragraph:
                            Text(LocalizedStringKey(block.content))
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.primaryText)
                                .lineSpacing(4)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Callout Quote Box
    private func calloutBox(text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(color)
                .frame(width: 3.5)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(text))
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(3)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 6)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }
    
    // MARK: - Bullet Row
    private func bulletRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AppColors.brand)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            
            Text(LocalizedStringKey(text))
                .font(AppTypography.body)
                .foregroundColor(AppColors.primaryText)
                .lineSpacing(3)
        }
    }
    
    // MARK: - Save to Notebook Action
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
        
        let dayDate = activeTemplate.category == .cadence ? JournalIds.todayDateString() : nil
        
        do {
            _ = try dataStore.createNote(
                folderId: folder.id,
                title: title,
                content: resultText,
                tags: tags,
                tradeKey: nil,
                dayDate: dayDate
            )
            savedNoteTitle = title
            isSavedToNotebook = true
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            AppLogger.warning("Failed to save AI reflection note: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Clipboard Copy
    private func copyToClipboard() {
        UIPasteboard.general.string = resultText
        showCopiedAlert = true
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedAlert = false
        }
    }
    
    // MARK: - Markdown Parser Heuristics
    private func parseMarkdownSections(_ markdown: String) -> [ReflectionSection] {
        let lines = markdown.components(separatedBy: .newlines)
        var sections: [ReflectionSection] = []
        var currentTitle: String = "Detailed Assessment"
        var currentBlocks: [SectionBlock] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Check for level 3 header: ###
            if trimmed.hasPrefix("### ") || trimmed.hasPrefix("## ") {
                if !currentBlocks.isEmpty {
                    sections.append(makeSection(title: currentTitle, blocks: currentBlocks))
                    currentBlocks = []
                }
                let rawHeader = trimmed.replacingOccurrences(of: "### ", with: "").replacingOccurrences(of: "## ", with: "")
                currentTitle = rawHeader.trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("> ") {
                let calloutContent = trimmed.replacingOccurrences(of: "> ", with: "")
                currentBlocks.append(SectionBlock(kind: .callout, content: calloutContent))
            } else if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let bulletContent = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                currentBlocks.append(SectionBlock(kind: .bullet, content: bulletContent))
            } else {
                currentBlocks.append(SectionBlock(kind: .paragraph, content: trimmed))
            }
        }
        
        if !currentBlocks.isEmpty {
            sections.append(makeSection(title: currentTitle, blocks: currentBlocks))
        }
        
        return sections
    }
    
    private func makeSection(title: String, blocks: [SectionBlock]) -> ReflectionSection {
        var icon = "quote.bubble.fill"
        var color = AppColors.brand
        let lower = title.lowercased()
        
        if lower.contains("tổng quan") || lower.contains("overview") || lower.contains("recap") {
            icon = "chart.bar.doc.horizontal.fill"
            color = AppColors.brand
        } else if lower.contains("điểm sáng") || lower.contains("strength") || lower.contains("tốt") {
            icon = "lightbulb.fill"
            color = AppColors.profit
        } else if lower.contains("cảnh báo") || lower.contains("rủi ro") || lower.contains("warning") || lower.contains("risk") || lower.contains("lỗ hổng") {
            icon = "exclamationmark.triangle.fill"
            color = AppColors.loss
        } else if lower.contains("quy tắc") || lower.contains("hành động") || lower.contains("action") || lower.contains("kế hoạch") {
            icon = "target"
            color = Color(hex: "#8b5cf6") // Purple accent
        }
        
        return ReflectionSection(title: title, icon: icon, accentColor: color, blocks: blocks)
    }
}

// MARK: - Parsing Data Models
fileprivate struct ReflectionSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let accentColor: Color
    let blocks: [SectionBlock]
}

fileprivate struct SectionBlock: Identifiable {
    enum Kind {
        case paragraph
        case bullet
        case callout
    }
    let id = UUID()
    let kind: Kind
    let content: String
}
