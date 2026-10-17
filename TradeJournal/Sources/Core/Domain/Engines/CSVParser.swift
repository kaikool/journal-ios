import Foundation

/// Internal domain documentation
/// Internal domain documentation
public enum CSVParser {
    
    public static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        let chars = Array(text)
        var i = 0
        let count = chars.count
        
        while i < count {
            let char = chars[i]
            
            if char == "\"" {
                if insideQuotes && i + 1 < count && chars[i + 1] == "\"" {
                    // Internal implementation note
                    currentField.append("\"")
                    i += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if char == delimiter && !insideQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if (char == "\r" || char == "\n") && !insideQuotes {
                // Internal implementation note
                if char == "\r" && i + 1 < count && chars[i + 1] == "\n" {
                    i += 1
                }
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
                
                // Internal implementation note
                if !currentRow.allSatisfy({ $0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
            } else {
                currentField.append(char)
            }
            i += 1
        }
        
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }
        
        return rows
    }
}
