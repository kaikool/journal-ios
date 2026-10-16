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

/// 1:1 port từ `source-repo/apps/web/src/lib/note-formatting.ts`
public enum NoteFormattingEngine {
    
    /// Giữ khoảng trắng bên ngoài dấu nhấn mạnh Markdown (* hoặc **) để đảm bảo tính hợp lệ của Markdown.
    public static func formatInlineSelection(
        value: String,
        start: Int,
        end: Int,
        marker: String // "*" hoặc "**"
    ) -> FormattedSelection {
        let nsString = value as NSString
        let safeStart = max(0, min(start, nsString.length))
        let safeEnd = max(safeStart, min(end, nsString.length))
        let selected = nsString.substring(with: NSRange(location: safeStart, length: safeEnd - safeStart))
        
        // Trích xuất leading whitespace
        var leading = ""
        for char in selected {
            if char.isWhitespace { leading.append(char) }
            else { break }
        }
        
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        let content: String
        let trailing: String
        
        if trimmed.isEmpty {
            content = marker == "**" ? "bold text" : "italic text"
            trailing = ""
        } else {
            content = trimmed
            // Trích xuất trailing whitespace
            var trail = ""
            for char in selected.reversed() {
                if char.isWhitespace { trail.append(char) }
                else { break }
            }
            trailing = String(trail.reversed())
        }
        
        let replacement = leading + marker + content + marker + trailing
        let prefix = nsString.substring(with: NSRange(location: 0, length: safeStart))
        let suffix = nsString.substring(with: NSRange(location: safeEnd, length: nsString.length - safeEnd))
        let nextValue = prefix + replacement + suffix
        
        let newSelectionStart = safeStart + (leading as NSString).length + (marker as NSString).length
        let newSelectionEnd = newSelectionStart + (content as NSString).length
        
        return FormattedSelection(
            value: nextValue,
            selectionStart: newSelectionStart,
            selectionEnd: newSelectionEnd
        )
    }
}
