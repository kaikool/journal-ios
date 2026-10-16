import Foundation

/// Bộ phân tích cú pháp CSV tuân thủ chuẩn RFC 4180
/// Hỗ trợ dấu ngoặc kép, dấu phẩy bên trong chuỗi, xuống dòng bên trong trường, và khoảng trắng.
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
                    // Thoát dấu ngoặc kép đôi ""
                    currentField.append("\"")
                    i += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if char == delimiter && !insideQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if (char == "\r" || char == "\n") && !insideQuotes {
                // Xuống dòng
                if char == "\r" && i + 1 < count && chars[i + 1] == "\n" {
                    i += 1
                }
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
                
                // Chỉ thêm dòng nếu có ít nhất 1 trường không rỗng
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
