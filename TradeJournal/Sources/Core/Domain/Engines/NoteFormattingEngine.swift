import Foundation

public struct FormattedSelection: Equatable, Sendable {
    public let value: String
    public let selectionStart: Int
    public let selectionEnd: Int
    
    public init(value: String, selectionStart: Int, selectionEnd: Int) {
        self.value = value
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
    }
}

/// Markdown formatting engine mimicking Microsoft Office formatting experience:
/// - Bold & Italic state detection and toggle on / off
/// - Bullet and Numbered list toggles with smart newline continuation
/// - Backwards-compatible selection wrapping
public enum NoteFormattingEngine {
    
    // MARK: - State Inspection (End-of-text backwards compatibility)
    
    public static func isBoldActive(in text: String) -> Bool {
        isBoldActive(in: text, at: (text as NSString).length)
    }
    
    public static func isItalicActive(in text: String) -> Bool {
        isItalicActive(in: text, at: (text as NSString).length)
    }
    
    public static func isBulletActive(in text: String) -> Bool {
        isBulletActive(in: text, at: (text as NSString).length)
    }
    
    public static func isNumberedActive(in text: String) -> Bool {
        isNumberedActive(in: text, at: (text as NSString).length)
    }
    
    // MARK: - Cursor-Aware State Inspection
    
    public static func isBoldActive(in text: String, at location: Int) -> Bool {
        let ns = text as NSString
        let loc = max(0, min(location, ns.length))
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        let lengthUpToCursor = loc - lineStart
        guard lengthUpToCursor >= 0 else { return false }
        let textBefore = ns.substring(with: NSRange(location: lineStart, length: lengthUpToCursor))
        let count = textBefore.components(separatedBy: "**").count - 1
        return count % 2 == 1
    }
    
    public static func isItalicActive(in text: String, at location: Int) -> Bool {
        let ns = text as NSString
        let loc = max(0, min(location, ns.length))
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        let lengthUpToCursor = loc - lineStart
        guard lengthUpToCursor >= 0 else { return false }
        let textBefore = ns.substring(with: NSRange(location: lineStart, length: lengthUpToCursor))
        let withoutBold = textBefore.replacingOccurrences(of: "**", with: "")
        let count = withoutBold.components(separatedBy: "*").count - 1
        return count % 2 == 1
    }
    
    public static func isBulletActive(in text: String, at location: Int) -> Bool {
        let ns = text as NSString
        let loc = max(0, min(location, ns.length))
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        var lineEnd = ns.length
        let nextRange = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
        if nextRange.location != NSNotFound {
            lineEnd = nextRange.location
        }
        let line = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart)).trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("• ") || line.hasPrefix("- ") || line == "•" || line == "-"
    }
    
    public static func isNumberedActive(in text: String, at location: Int) -> Bool {
        let ns = text as NSString
        let loc = max(0, min(location, ns.length))
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        var lineEnd = ns.length
        let nextRange = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
        if nextRange.location != NSNotFound {
            lineEnd = nextRange.location
        }
        let line = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart)).trimmingCharacters(in: .whitespaces)
        return line.range(of: #"^\d+[\.\)](\s|$)"#, options: .regularExpression) != nil
    }
    
    // MARK: - Cursor & Selection Toggles (Office Style)
    
    public static func toggleBold(in text: String, range: NSRange) -> (text: String, newRange: NSRange, isActive: Bool) {
        let ns = text as NSString
        let safeLoc = max(0, min(range.location, ns.length))
        let safeLen = max(0, min(range.length, ns.length - safeLoc))
        
        if safeLen > 0 {
            let selected = ns.substring(with: NSRange(location: safeLoc, length: safeLen))
            if selected.hasPrefix("**") && selected.hasSuffix("**") && selected.count >= 4 {
                let unwrapped = String(selected.dropFirst(2).dropLast(2))
                let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: safeLen), with: unwrapped)
                return (newText, NSRange(location: safeLoc, length: (unwrapped as NSString).length), false)
            } else {
                let wrapped = "**\(selected)**"
                let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: safeLen), with: wrapped)
                return (newText, NSRange(location: safeLoc, length: (wrapped as NSString).length), true)
            }
        } else {
            let active = isBoldActive(in: text, at: safeLoc)
            if active {
                let nextTwo = (safeLoc + 2 <= ns.length) ? ns.substring(with: NSRange(location: safeLoc, length: 2)) : ""
                if nextTwo == "**" {
                    return (text, NSRange(location: safeLoc + 2, length: 0), false)
                } else {
                    let insertStr = "** "
                    let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: 0), with: insertStr)
                    return (newText, NSRange(location: safeLoc + insertStr.count, length: 0), false)
                }
            } else {
                let insertStr = "****"
                let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: 0), with: insertStr)
                return (newText, NSRange(location: safeLoc + 2, length: 0), true)
            }
        }
    }
    
    public static func toggleItalic(in text: String, range: NSRange) -> (text: String, newRange: NSRange, isActive: Bool) {
        let ns = text as NSString
        let safeLoc = max(0, min(range.location, ns.length))
        let safeLen = max(0, min(range.length, ns.length - safeLoc))
        
        if safeLen > 0 {
            let selected = ns.substring(with: NSRange(location: safeLoc, length: safeLen))
            if selected.hasPrefix("*") && selected.hasSuffix("*") && selected.count >= 2 && !selected.hasPrefix("**") {
                let unwrapped = String(selected.dropFirst(1).dropLast(1))
                let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: safeLen), with: unwrapped)
                return (newText, NSRange(location: safeLoc, length: (unwrapped as NSString).length), false)
            } else {
                let wrapped = "*\(selected)*"
                let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: safeLen), with: wrapped)
                return (newText, NSRange(location: safeLoc, length: (wrapped as NSString).length), true)
            }
        } else {
            let active = isItalicActive(in: text, at: safeLoc)
            if active {
                let nextOne = (safeLoc + 1 <= ns.length) ? ns.substring(with: NSRange(location: safeLoc, length: 1)) : ""
                if nextOne == "*" {
                    return (text, NSRange(location: safeLoc + 1, length: 0), false)
                } else {
                    let insertStr = "* "
                    let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: 0), with: insertStr)
                    return (newText, NSRange(location: safeLoc + insertStr.count, length: 0), false)
                }
            } else {
                let insertStr = "**"
                let newText = ns.replacingCharacters(in: NSRange(location: safeLoc, length: 0), with: insertStr)
                return (newText, NSRange(location: safeLoc + 1, length: 0), true)
            }
        }
    }
    
    public static func toggleBullet(in text: String, range: NSRange) -> (text: String, newRange: NSRange, isActive: Bool) {
        let ns = text as NSString
        let loc = max(0, min(range.location, ns.length))
        
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        var lineEnd = ns.length
        let nextRange = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
        if nextRange.location != NSNotFound {
            lineEnd = nextRange.location
        }
        
        let line = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed == "•" || trimmed == "-" {
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: line.count), with: "")
            return (newText, NSRange(location: lineStart, length: 0), false)
        } else if line.hasPrefix("• ") {
            let newLine = String(line.dropFirst(2))
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: line.count), with: newLine)
            let newLoc = max(lineStart, loc - 2)
            return (newText, NSRange(location: newLoc, length: 0), false)
        } else if line.hasPrefix("- ") {
            let newLine = String(line.dropFirst(2))
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: line.count), with: newLine)
            let newLoc = max(lineStart, loc - 2)
            return (newText, NSRange(location: newLoc, length: 0), false)
        } else {
            let newLine = "• " + line
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: line.count), with: newLine)
            let newLoc = loc + 2
            return (newText, NSRange(location: newLoc, length: 0), true)
        }
    }
    
    public static func toggleNumbered(in text: String, range: NSRange) -> (text: String, newRange: NSRange, isActive: Bool) {
        let ns = text as NSString
        let loc = max(0, min(range.location, ns.length))
        
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        var lineEnd = ns.length
        let nextRange = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
        if nextRange.location != NSNotFound {
            lineEnd = nextRange.location
        }
        
        let line = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if let match = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            let matchLen = line.distance(from: line.startIndex, to: match.upperBound)
            let newLine = String(line[match.upperBound...])
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: line.count), with: newLine)
            let newLoc = max(lineStart, loc - matchLen)
            return (newText, NSRange(location: newLoc, length: 0), false)
        } else {
            var nextNum = 1
            if lineStart > 1 {
                let textBefore = ns.substring(with: NSRange(location: 0, length: lineStart - 1))
                let prevLines = textBefore.components(separatedBy: .newlines)
                if let prev = prevLines.last?.trimmingCharacters(in: .whitespaces),
                   let match = prev.range(of: #"^(\d+)[\.\)]"#, options: .regularExpression) {
                    let digits = String(prev[match]).filter { $0.isNumber }
                    if let n = Int(digits) { nextNum = n + 1 }
                }
            }
            let prefix = "\(nextNum). "
            let newLine = prefix + line
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: line.count), with: newLine)
            let newLoc = loc + prefix.count
            return (newText, NSRange(location: newLoc, length: 0), true)
        }
    }
    
    // MARK: - Smart Return / Enter Handling
    
    public static func handleReturnKey(in text: String, at location: Int) -> (text: String, newLocation: Int, handled: Bool) {
        let ns = text as NSString
        let loc = max(0, min(location, ns.length))
        
        var lineStart = 0
        if loc > 0 {
            let prevRange = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: loc))
            if prevRange.location != NSNotFound {
                lineStart = prevRange.location + 1
            }
        }
        
        let lineUpToCursor = ns.substring(with: NSRange(location: lineStart, length: loc - lineStart))
        let trimmed = lineUpToCursor.trimmingCharacters(in: .whitespaces)
        
        // Double enter on empty bullet -> clear bullet and exit list
        if trimmed == "•" || trimmed == "-" {
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: loc - lineStart), with: "")
            return (newText, lineStart, true)
        }
        
        // Double enter on empty numbered item -> clear number and exit list
        if trimmed.range(of: #"^\d+[\.\)]$|\d+[\.\)]\s*$"#, options: .regularExpression) != nil {
            let newText = ns.replacingCharacters(in: NSRange(location: lineStart, length: loc - lineStart), with: "")
            return (newText, lineStart, true)
        }
        
        // Bullet continuation
        if lineUpToCursor.hasPrefix("• ") || lineUpToCursor.hasPrefix("- ") {
            let insertStr = "\n• "
            let newText = ns.replacingCharacters(in: NSRange(location: loc, length: 0), with: insertStr)
            return (newText, loc + insertStr.count, true)
        }
        
        // Numbered continuation
        if let match = lineUpToCursor.range(of: #"^(\d+)[\.\)]\s*"#, options: .regularExpression) {
            let digits = String(lineUpToCursor[match]).filter { $0.isNumber }
            let nextNum = (Int(digits) ?? 1) + 1
            let insertStr = "\n\(nextNum). "
            let newText = ns.replacingCharacters(in: NSRange(location: loc, length: 0), with: insertStr)
            return (newText, loc + insertStr.count, true)
        }
        
        return (text, loc, false)
    }
    
    // MARK: - Office-Style Toggles (End-of-text Fallbacks)
    
    public static func toggleBold(in text: String) -> (text: String, isActive: Bool) {
        if isBoldActive(in: text) {
            // Currently bold -> close bold with ** and space
            return (text + "** ", false)
        } else {
            // Currently normal -> open bold with **
            return (text + "**", true)
        }
    }
    
    public static func toggleItalic(in text: String) -> (text: String, isActive: Bool) {
        if isItalicActive(in: text) {
            // Currently italic -> close italic with * and space
            return (text + "* ", false)
        } else {
            // Currently normal -> open italic with *
            return (text + "*", true)
        }
    }
    
    public static func toggleBullet(in text: String) -> (text: String, isActive: Bool) {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return ("• ", true) }
        
        let lastIdx = lines.count - 1
        let lastLine = lines[lastIdx]
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)
        
        if trimmed == "•" || trimmed == "-" {
            // Empty bullet -> remove it
            lines[lastIdx] = ""
            return (lines.joined(separator: "\n"), false)
        } else if trimmed.hasPrefix("• ") {
            lines[lastIdx] = String(trimmed.dropFirst(2))
            return (lines.joined(separator: "\n"), false)
        } else if trimmed.hasPrefix("- ") {
            lines[lastIdx] = String(trimmed.dropFirst(2))
            return (lines.joined(separator: "\n"), false)
        } else {
            // Add bullet to current line or new line
            if trimmed.isEmpty {
                lines[lastIdx] = "• "
            } else {
                lines.append("• ")
            }
            return (lines.joined(separator: "\n"), true)
        }
    }
    
    public static func toggleNumbered(in text: String) -> (text: String, isActive: Bool) {
        var lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return ("1. ", true) }
        
        let lastIdx = lines.count - 1
        let lastLine = lines[lastIdx]
        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)
        
        if let match = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            let content = String(trimmed[match.upperBound...])
            lines[lastIdx] = content
            return (lines.joined(separator: "\n"), false)
        } else {
            var nextNum = 1
            if lines.count >= 2 {
                let prevLine = lines[lines.count - 2].trimmingCharacters(in: .whitespaces)
                if let match = prevLine.range(of: #"^(\d+)[\.\)]"#, options: .regularExpression) {
                    let digits = String(prevLine[match]).filter { $0.isNumber }
                    if let n = Int(digits) {
                        nextNum = n + 1
                    }
                }
            }
            if trimmed.isEmpty {
                lines[lastIdx] = "\(nextNum). "
            } else {
                lines.append("\(nextNum). ")
            }
            return (lines.joined(separator: "\n"), true)
        }
    }
    
    // MARK: - Smart Return / Enter Handling
    
    public static func handleNewline(text: String, oldValue: String) -> String {
        guard text.hasSuffix("\n") && !oldValue.hasSuffix("\n") else {
            return text
        }
        
        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return text }
        
        let prevLine = lines[lines.count - 2]
        let trimmed = prevLine.trimmingCharacters(in: .whitespaces)
        
        // 1. Double enter on empty bullet -> clear bullet and exit list
        if trimmed == "•" || trimmed == "-" {
            lines.remove(at: lines.count - 2)
            return lines.joined(separator: "\n")
        }
        
        // 2. Double enter on empty numbered item -> clear number and exit list
        if trimmed.range(of: #"^\d+[\.\)]$|\d+[\.\)]\s*$"#, options: .regularExpression) != nil {
            lines.remove(at: lines.count - 2)
            return lines.joined(separator: "\n")
        }
        
        // 3. Bullet continuation
        if prevLine.hasPrefix("• ") || prevLine.hasPrefix("- ") {
            let marker = prevLine.hasPrefix("• ") ? "• " : "- "
            return text + marker
        }
        
        // 4. Numbered list continuation
        if let match = prevLine.range(of: #"^(\d+)[\.\)]\s"#, options: .regularExpression) {
            let digits = String(prevLine[match]).filter { $0.isNumber }
            if let n = Int(digits) {
                return text + "\(n + 1). "
            }
        }
        
        return text
    }
    
    // MARK: - Selection Support (Backwards Compatibility)
    
    public static func formatInlineSelection(
        value: String,
        start: Int,
        end: Int,
        marker: String
    ) -> FormattedSelection {
        let nsString = value as NSString
        let safeStart = max(0, min(start, nsString.length))
        let safeEnd = max(safeStart, min(end, nsString.length))
        let selected = nsString.substring(with: NSRange(location: safeStart, length: safeEnd - safeStart))
        
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if marker == "**" {
                let res = toggleBold(in: value)
                return FormattedSelection(value: res.text, selectionStart: res.text.count, selectionEnd: res.text.count)
            } else if marker == "*" {
                let res = toggleItalic(in: value)
                return FormattedSelection(value: res.text, selectionStart: res.text.count, selectionEnd: res.text.count)
            }
        }
        
        let replacement = marker + trimmed + marker
        let prefix = nsString.substring(with: NSRange(location: 0, length: safeStart))
        let suffix = nsString.substring(with: NSRange(location: safeEnd, length: nsString.length - safeEnd))
        let nextValue = prefix + replacement + suffix
        
        let newSelectionStart = safeStart + marker.count
        let newSelectionEnd = newSelectionStart + trimmed.count
        
        return FormattedSelection(
            value: nextValue,
            selectionStart: newSelectionStart,
            selectionEnd: newSelectionEnd
        )
    }
}
