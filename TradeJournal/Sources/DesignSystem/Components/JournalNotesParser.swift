import Foundation

// MARK: - Journal Note Block Model for Rich Markdown Rendering
public enum JournalNoteBlock: Identifiable, Sendable {
    case heading(level: Int, text: String)
    case divider
    case quote(String)
    case bullet(String)
    case numbered(Int, String)
    case table(headers: [String], rows: [[String]])
    case paragraph(String)
    
    public var id: String {
        switch self {
        case .heading(let lvl, let txt): return "h_\(lvl)_\(txt)"
        case .divider: return "divider_\(UUID().uuidString)"
        case .quote(let txt): return "q_\(txt.prefix(20))_\(txt.count)"
        case .bullet(let txt): return "b_\(txt.prefix(20))_\(txt.count)"
        case .numbered(let num, let txt): return "n_\(num)_\(txt.prefix(20))"
        case .table(let headers, let rows): return "t_\(headers.joined())_\(rows.count)"
        case .paragraph(let txt): return "p_\(txt.prefix(20))_\(txt.count)"
        }
    }
}

// MARK: - Journal Notes Markdown Parser
public enum JournalNotesParser {
    public static func parse(_ text: String) -> [JournalNoteBlock] {
        let rawLines = text.components(separatedBy: .newlines)
        var blocks: [JournalNoteBlock] = []
        var paragraphBuffer: [String] = []
        
        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let joined = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    blocks.append(.paragraph(joined))
                }
                paragraphBuffer = []
            }
        }
        
        var i = 0
        while i < rawLines.count {
            let line = rawLines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                i += 1
                continue
            }
            
            // 0. Markdown Table Detection: line has '|' and next line is table separator
            if line.contains("|") && (i + 1 < rawLines.count) && isTableSeparator(rawLines[i + 1]) {
                flushParagraph()
                let headers = parseTableCells(line)
                i += 2 // skip header line and separator line
                
                var rows: [[String]] = []
                while i < rawLines.count {
                    let rowLine = rawLines[i].trimmingCharacters(in: .whitespaces)
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
                    blocks.append(.table(headers: headers, rows: rows))
                }
                continue
            }
            
            // 1. Horizontal Divider (---, ***, ___)
            if line == "---" || line == "***" || line == "___" || line == "- - -" {
                flushParagraph()
                blocks.append(.divider)
                i += 1
                continue
            }
            
            // 2. Heading (#, ##, ###)
            if line.hasPrefix("### ") {
                flushParagraph()
                let clean = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: 3, text: clean))
                i += 1
                continue
            } else if line.hasPrefix("## ") {
                flushParagraph()
                let clean = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: 2, text: clean))
                i += 1
                continue
            } else if line.hasPrefix("# ") {
                flushParagraph()
                let clean = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: 1, text: clean))
                i += 1
                continue
            }
            
            // 3. Blockquotes (> ...)
            if line.hasPrefix("> ") || line.hasPrefix(">") {
                flushParagraph()
                let clean = line.dropFirst(line.hasPrefix("> ") ? 2 : 1).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(clean))
                i += 1
                continue
            }
            
            // 4. Bullets (•, -, *)
            if line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                var clean = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                while clean.hasPrefix("* ") || clean.hasPrefix("• ") || clean.hasPrefix("- ") {
                    clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                blocks.append(.bullet(clean))
                i += 1
                continue
            }
            
            // 5. Numbered List (1. , 2. )
            if let match = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(line[match])
                let digits = prefix.filter { $0.isNumber }
                let num = Int(digits) ?? 1
                let clean = String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                blocks.append(.numbered(num, clean))
                i += 1
                continue
            }
            
            // 6. Normal paragraph text accumulator
            paragraphBuffer.append(line)
            i += 1
        }
        
        flushParagraph()
        return blocks
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
}
