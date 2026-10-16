import Foundation

public struct ImportRowProblem: Identifiable, Equatable {
    public var id: String { "\(lineNumber)-\(reason)" }
    public let lineNumber: Int
    public let symbol: String
    public let reason: String
}

public struct ImportPreview: Equatable {
    public let totalRows: Int
    public let usableExecutions: [Execution]
    public let problems: [ImportRowProblem]
    public var duplicateCount: Int
    
    public var isValid: Bool {
        !usableExecutions.isEmpty
    }
}

/// Trình nhập khẩu dữ liệu giao dịch từ CSV tiêu chuẩn
/// Nhận diện linh hoạt các cột header phổ biến và chuẩn hóa dữ liệu sang `Execution`.
public enum StandardCSVImporter {
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let supportedDateFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "dd/MM/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd"
    ]
    
    /// Parse chuỗi ngày tháng từ nhiều format thông dụng
    private static func parseDateTime(_ string: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = isoFormatter.date(from: trimmed) { return d }
        
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        
        for format in supportedDateFormats {
            df.dateFormat = format
            if let date = df.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
    
    /// Làm sạch chuỗi số tiền/khối lượng (loại bỏ ký tự $, dấu phẩy ngăn cách hàng nghìn)
    private static func parseDecimal(_ string: String) -> Decimal? {
        var clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "$", with: "")
        clean = clean.replacingOccurrences(of: "€", with: "")
        clean = clean.replacingOccurrences(of: "£", with: "")
        clean = clean.replacingOccurrences(of: ",", with: "")
        
        // Hỗ trợ số âm trong ngoặc đơn: (10.50) -> -10.50
        if clean.hasPrefix("(") && clean.hasSuffix(")") {
            clean = "-" + clean.dropFirst().dropLast()
        }
        
        return Decimal(string: clean)
    }
    
    /// Phân tích nội dung CSV và sinh bản xem trước (Preview)
    public static func preview(
        csvText: String,
        accountId: String,
        existingHashes: Set<String> = [],
        timeZone: TimeZone = .current
    ) -> ImportPreview {
        let rows = CSVParser.parse(csvText)
        guard rows.count > 1 else {
            return ImportPreview(totalRows: 0, usableExecutions: [], problems: [
                ImportRowProblem(lineNumber: 1, symbol: "-", reason: "Tệp CSV rỗng hoặc chỉ có dòng tiêu đề.")
            ], duplicateCount: 0)
        }
        
        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Tìm vị trí các cột
        var symbolIdx: Int?
        var sideIdx: Int?
        var qtyIdx: Int?
        var priceIdx: Int?
        var feeIdx: Int?
        var dateIdx: Int?
        var timeIdx: Int?
        
        for (i, h) in headers.enumerated() {
            if ["symbol", "ticker", "instrument", "contract", "pair"].contains(h) { symbolIdx = i }
            else if ["side", "action", "type", "direction", "b/s"].contains(h) { sideIdx = i }
            else if ["quantity", "qty", "size", "shares", "contracts", "amount", "volume"].contains(h) { qtyIdx = i }
            else if ["price", "fill price", "exec price", "execution price", "rate"].contains(h) { priceIdx = i }
            else if ["fee", "commission", "comm", "fees", "order fee"].contains(h) { feeIdx = i }
            else if ["date", "datetime", "timestamp", "executed_at", "fill time", "time"].contains(h) { dateIdx = i }
            else if ["time_only", "clock"].contains(h) { timeIdx = i }
        }
        
        guard let sIdx = symbolIdx, let sdIdx = sideIdx, let qIdx = qtyIdx, let pIdx = priceIdx else {
            return ImportPreview(
                totalRows: rows.count - 1,
                usableExecutions: [],
                problems: [
                    ImportRowProblem(lineNumber: 1, symbol: "-", reason: "Không tìm thấy các cột bắt buộc: Symbol, Side (Buy/Sell), Quantity, Price.")
                ],
                duplicateCount: 0
            )
        }
        
        var usable: [Execution] = []
        var problems: [ImportRowProblem] = []
        var duplicateCount = 0
        var batchHashes = Set<String>()
        
        for lineNum in 2...rows.count {
            let row = rows[lineNum - 1]
            if row.allSatisfy({ $0.isEmpty }) { continue }
            
            let symbol = sIdx < row.count ? row[sIdx].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() : ""
            if symbol.isEmpty {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: "N/A", reason: "Mã tài sản (Symbol) bị trống."))
                continue
            }
            
            let rawSide = sdIdx < row.count ? row[sdIdx].lowercased().trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let side: ExecutionSide
            if ["buy", "b", "bot", "long"].contains(rawSide) {
                side = .buy
            } else if ["sell", "s", "sld", "short"].contains(rawSide) {
                side = .sell
            } else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Cột Side phải là Buy hoặc Sell (nhận diện được: '\(rawSide)')."))
                continue
            }
            
            let rawQty = qIdx < row.count ? row[qIdx] : ""
            guard let quantity = parseDecimal(rawQty), quantity > 0 else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Khối lượng phải là số dương hợp lệ."))
                continue
            }
            
            let rawPrice = pIdx < row.count ? row[pIdx] : ""
            guard let price = parseDecimal(rawPrice), price >= 0 else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Giá phải là số dương hợp lệ."))
                continue
            }
            
            var fee: Decimal = 0
            if let fIdx = feeIdx, fIdx < row.count {
                fee = abs(parseDecimal(row[fIdx]) ?? 0)
            }
            
            var executedAt: Date?
            if let dIdx = dateIdx, dIdx < row.count {
                var dateStr = row[dIdx]
                if let tIdx = timeIdx, tIdx < row.count {
                    dateStr += " " + row[tIdx]
                }
                executedAt = parseDateTime(dateStr, timeZone: timeZone)
            }
            
            guard let validDate = executedAt else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Thời gian khớp lệnh không hợp lệ hoặc thiếu."))
                continue
            }
            
            // Tính toán Content Hash
            let isoTime = ISO8601DateFormatter().string(from: validDate)
            let hash = "\(accountId)|\(symbol)|\(side.rawValue)|\(quantity)|\(price)|\(isoTime)"
            
            if existingHashes.contains(hash) || batchHashes.contains(hash) {
                duplicateCount += 1
                continue
            }
            batchHashes.insert(hash)
            
            let execution = Execution(
                id: UUID().uuidString,
                accountId: accountId,
                symbol: symbol,
                side: side,
                quantity: quantity,
                price: price,
                fee: fee,
                executedAt: validDate,
                source: "import",
                contentHash: hash
            )
            usable.append(execution)
        }
        
        return ImportPreview(
            totalRows: rows.count - 1,
            usableExecutions: usable,
            problems: problems,
            duplicateCount: duplicateCount
        )
    }
}
