import SwiftUI

// MARK: - Dedicated AI Document Section & Element Models
public struct AIAnalysisSection: Identifiable {
    public let id = UUID()
    public let number: String?
    public let title: String
    public let blocks: [AIAnalysisBlock]
    
    public init(number: String?, title: String, blocks: [AIAnalysisBlock]) {
        self.number = number
        self.title = title
        self.blocks = blocks
    }
}

public struct AIAnalysisBlock: Identifiable {
    public let id = UUID()
    public enum Kind {
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case quote(String)
        case table(headers: [String], rows: [[String]])
    }
    public let kind: Kind
    
    public init(kind: Kind) {
        self.kind = kind
    }
}

// MARK: - Robust Markdown Parser for AI Responses
public enum AIDocumentParser {
    public static func parse(_ text: String) -> [AIAnalysisSection] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [AIAnalysisSection] = []
        
        var currentNumber: String? = nil
        var currentTitle: String = "Executive Analysis"
        var currentBlocks: [AIAnalysisBlock] = []
        var paragraphLines: [String] = []
        
        func flushParagraph() {
            if !paragraphLines.isEmpty {
                let joined = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    currentBlocks.append(AIAnalysisBlock(kind: .paragraph(sanitize(joined))))
                }
                paragraphLines = []
            }
        }
        
        func flushSection() {
            flushParagraph()
            if !currentBlocks.isEmpty {
                let hasSubstantialContent = currentBlocks.contains { block in
                    switch block.kind {
                    case .paragraph(let p):
                        let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.count > 30 && !trimmed.lowercased().contains("chào bạn, tôi là risk ai")
                    case .bullet, .numbered, .quote, .table:
                        return true
                    }
                }
                if currentNumber != nil || hasSubstantialContent {
                    sections.append(AIAnalysisSection(number: currentNumber, title: currentTitle, blocks: currentBlocks))
                }
                currentBlocks = []
            }
        }
        
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                i += 1
                continue
            }
            
            // Filter out safety classification or moderation output lines
            let lower = line.lowercased()
            if lower.hasPrefix("user safety:") || lower.hasPrefix("response safety:") || lower == "safe" || lower == "unsafe" {
                i += 1
                continue
            }
            
            // 0. Check for Markdown Table
            if line.contains("|") && (i + 1 < lines.count) && isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let headers = parseTableCells(line)
                i += 2
                
                var rows: [[String]] = []
                while i < lines.count {
                    let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if rowLine.isEmpty || !rowLine.contains("|") {
                        break
                    }
                    if isTableSeparator(rowLine) {
                        i += 1
                        continue
                    }
                    let cells = parseTableCells(rowLine)
                    if !cells.isEmpty {
                        rows.append(cells)
                    }
                    i += 1
                }
                
                if !headers.isEmpty {
                    currentBlocks.append(AIAnalysisBlock(kind: .table(headers: headers, rows: rows)))
                }
                continue
            }
            
            // 1. Check for Section Header (###, ##, #)
            if line.hasPrefix("### ") || line.hasPrefix("## ") || line.hasPrefix("# ") {
                flushSection()
                let clean = line
                    .replacingOccurrences(of: "### ", with: "")
                    .replacingOccurrences(of: "## ", with: "")
                    .replacingOccurrences(of: "# ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                // Extract section number if present (e.g. "1. Thẩm định...")
                if let match = clean.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    let numStr = String(clean[match]).filter { $0.isNumber }
                    currentNumber = numStr
                    currentTitle = String(clean[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    currentNumber = nil
                    currentTitle = clean
                }
                i += 1
                continue
            }
            
            // 2. Check for Quotes (> ...)
            if line.hasPrefix("> ") || line.hasPrefix(">") {
                flushParagraph()
                let clean = line.dropFirst(line.hasPrefix("> ") ? 2 : 1).trimmingCharacters(in: .whitespaces)
                currentBlocks.append(AIAnalysisBlock(kind: .quote(sanitize(clean))))
                i += 1
                continue
            }
            
            // 3. Check for Bullet points (•, -, *)
            if line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                var clean = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                while clean.hasPrefix("* ") || clean.hasPrefix("• ") || clean.hasPrefix("- ") {
                    clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                currentBlocks.append(AIAnalysisBlock(kind: .bullet(sanitize(clean))))
                i += 1
                continue
            }
            
            // 4. Check for Numbered items (1., 2., 3.)
            if let match = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(line[match])
                let digits = prefix.filter { $0.isNumber }
                let num = Int(digits) ?? 1
                let clean = String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                currentBlocks.append(AIAnalysisBlock(kind: .numbered(num, sanitize(clean))))
                i += 1
                continue
            }
            
            // 5. Normal paragraph line
            paragraphLines.append(line)
            i += 1
        }
        
        flushSection()
        
        if sections.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [AIAnalysisSection(
                number: nil,
                title: "Detailed Analysis",
                blocks: [AIAnalysisBlock(kind: .paragraph(text.trimmingCharacters(in: .whitespacesAndNewlines)))]
            )]
        }
        
        return sections
    }
    
    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") || trimmed.contains("-") else { return false }
        let clean = trimmed
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return clean.isEmpty && trimmed.contains("-")
    }
    
    private static func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    private static func sanitize(_ str: String) -> String {
        var s = str.replacingOccurrences(of: "* *", with: "*")
        s = s.replacingOccurrences(of: "• •", with: "•")
        s = s.replacingOccurrences(of: "- -", with: "-")
        return s
    }
}

// MARK: - Unified Apple HIG AI Document Reader View
public struct AIDocumentReaderView: View {
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        let sections = AIDocumentParser.parse(text)
        VStack(spacing: 12) {
            ForEach(sections) { section in
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        // Section Header
                        HStack(spacing: 8) {
                            if let num = section.number {
                                Text(num)
                                    .font(AppTypography.number(11, weight: .bold))
                                    .foregroundColor(AppColors.brand)
                                    .frame(width: 22, height: 22)
                                    .background(AppColors.brand.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            
                            Text(section.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                            
                            Spacer()
                        }
                        
                        Divider()
                            .background(AppColors.border.opacity(0.5))
                        
                        // Blocks inside Section
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.blocks) { block in
                                renderBlock(block)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .textSelection(.enabled)
    }
    
    @ViewBuilder
    private func renderBlock(_ block: AIAnalysisBlock) -> some View {
        switch block.kind {
        case .paragraph(let content):
            JustifiedText(
                content,
                font: AppTypography.body,
                fontSize: 14,
                fontWeight: .regular,
                textColor: AppColors.primaryText,
                lineSpacing: 4
            )
            
        case .bullet(let content):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(AppColors.brand.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .padding(.top, 6)
                
                JustifiedText(
                    content,
                    font: AppTypography.body,
                    fontSize: 14,
                    fontWeight: .regular,
                    textColor: AppColors.primaryText,
                    lineSpacing: 3.5
                )
            }
            .padding(.leading, 2)
            
        case .numbered(let num, let content):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .font(AppTypography.number(12, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 20, alignment: .leading)
                
                JustifiedText(
                    content,
                    font: AppTypography.body,
                    fontSize: 14,
                    fontWeight: .regular,
                    textColor: AppColors.primaryText,
                    lineSpacing: 3.5
                )
            }
            
        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColors.brand)
                    .frame(width: 3)
                
                JustifiedText(
                    content,
                    font: .system(size: 13, weight: .medium),
                    fontSize: 13,
                    fontWeight: .medium,
                    textColor: AppColors.primaryText,
                    lineSpacing: 3
                )
                .padding(.vertical, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground.opacity(0.65))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.5), lineWidth: 0.6))
            
        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    // Table Header Row
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { colIdx, header in
                            Text(LocalizedStringKey(header))
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 85, maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .trailing) {
                                    if colIdx < headers.count - 1 {
                                        Rectangle()
                                            .fill(AppColors.border.opacity(0.35))
                                            .frame(width: 0.5)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(AppColors.border.opacity(0.5))
                                        .frame(height: 0.5)
                                }
                        }
                    }
                    .background(AppColors.secondaryBackground.opacity(0.85))
                    
                    // Table Data Rows
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                        GridRow {
                            ForEach(Array(headers.indices), id: \.self) { colIdx in
                                let cellText = colIdx < row.count ? row[colIdx] : ""
                                Text(LocalizedStringKey(cellText))
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundColor(AppColors.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .frame(minWidth: 85, maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .trailing) {
                                        if colIdx < headers.count - 1 {
                                            Rectangle()
                                                .fill(AppColors.border.opacity(0.25))
                                                .frame(width: 0.5)
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if rowIdx < rows.count - 1 {
                                            Rectangle()
                                                .fill(AppColors.border.opacity(0.2))
                                                .frame(height: 0.5)
                                        }
                                    }
                            }
                        }
                        .background(rowIdx % 2 == 0 ? Color.clear : AppColors.secondaryBackground.opacity(0.3))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
            }
            .padding(.vertical, 4)
        }
    }
}
