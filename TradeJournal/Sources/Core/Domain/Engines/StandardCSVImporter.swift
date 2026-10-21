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

/// Universal CSV trade importer supporting standard broker formats and column auto-mapping
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
        "yyyy.MM.dd HH:mm:ss",
        "yyyy.MM.dd HH:mm",
        "dd.MM.yyyy HH:mm:ss",
        "dd.MM.yyyy HH:mm",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "dd/MM/yyyy HH:mm:ss",
        "dd/MM/yyyy HH:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd"
    ]
    
    // MARK: - Column Aliases (ordered by priority: the first alias wins)
    
    private static let symbolAliases = ["symbol", "ticker", "instrument", "contract", "pair", "market", "product"]
    private static let sideAliases = ["side", "action", "type", "direction", "b/s", "buy/sell", "deal type", "order type"]
    private static let quantityAliases = ["quantity", "qty", "size", "volume", "lots", "shares", "contracts", "units", "amount"]
    private static let priceAliases = ["price", "fill price", "exec price", "execution price", "rate", "open price", "entry price"]
    private static let feeAliases = ["commission", "fee", "fees", "comm", "order fee", "brokerage"]
    private static let rebateAliases = ["rebate", "cashback", "commission rebate"]
    private static let swapAliases = ["swap", "interest", "financing", "overnight interest", "swap charge"]
    /// The open timestamp is preferred; a close timestamp is only used as a last resort.
    private static let dateAliases = [
        "open time", "open_time", "opentime", "entry time", "entrytime",
        "executed date", "executeddate", "execution date", "executiondate",
        "trade time", "tradetime", "deal time", "dealtime", "filled at", "filledat",
        "datetime", "timestamp", "executed_at", "executedat", "fill time", "filltime",
        "date", "time",
        "close time", "close_time", "closetime"
    ]
    private static let timeOnlyAliases = ["time_only", "clock"]
    private static let reportedProfitAliases = ["profit", "s/l", "p/l", "pnl", "realized profit", "realised profit"]
    
    /// Multi-format date parser supporting ISO-8601, US, European, and standard timestamps
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
    
    /// Parses localized numbers, currency symbols, and accounting negative formats (e.g. ($100))
    private static func parseDecimal(_ string: String) -> Decimal? {
        var clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "$", with: "")
        clean = clean.replacingOccurrences(of: "€", with: "")
        clean = clean.replacingOccurrences(of: "£", with: "")
        clean = clean.replacingOccurrences(of: ",", with: "")
        
        // Financial accounting negative numbers wrapped in parentheses: (100) -> -100
        if clean.hasPrefix("(") && clean.hasSuffix(")") {
            clean = "-" + clean.dropFirst().dropLast()
        }
        
        return Decimal(string: clean)
    }
    
    /// Returns the column index of the alias with the highest priority.
    private static func bestIndex(_ headers: [String], aliases: [String]) -> Int? {
        var bestIndex: Int?
        var bestRank = Int.max
        for (index, header) in headers.enumerated() {
            guard let rank = aliases.firstIndex(of: header) else { continue }
            if rank < bestRank {
                bestRank = rank
                bestIndex = index
            }
        }
        return bestIndex
    }
    
    /// Parses CSV content and builds an import preview with conflict detection.
    ///
    /// - Parameters:
    ///   - timeZone: Timezone used to interpret timestamps that do not carry an explicit offset.
    ///     Using a fixed timezone (the configured import timezone) keeps the content hash stable
    ///     across devices, so re-importing the same statement can no longer duplicate fills.
    ///   - legacyTimeZone: Timezone used to build the legacy content hash so that statements
    ///     imported with an older build are still recognised as duplicates.
    public static func preview(
        csvText: String,
        accountId: String,
        existingHashes: Set<String> = [],
        timeZone: TimeZone = .current,
        legacyTimeZone: TimeZone? = nil
    ) -> ImportPreview {
        let rows = CSVParser.parse(csvText)
        guard rows.count > 1 else {
            return ImportPreview(totalRows: 0, usableExecutions: [], problems: [
                ImportRowProblem(lineNumber: 1, symbol: "-", reason: "CSV file is empty or contains only the header row.")
            ], duplicateCount: 0)
        }
        
        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        
// Find column header indices
        let symbolIdx = bestIndex(headers, aliases: symbolAliases)
        let sideIdx = bestIndex(headers, aliases: sideAliases)
        let qtyIdx = bestIndex(headers, aliases: quantityAliases)
        let priceIdx = bestIndex(headers, aliases: priceAliases)
        let feeIdx = bestIndex(headers, aliases: feeAliases)
        let rebateIdx = bestIndex(headers, aliases: rebateAliases)
        let swapIdx = bestIndex(headers, aliases: swapAliases)
        let dateIdx = bestIndex(headers, aliases: dateAliases)
        let timeIdx = bestIndex(headers, aliases: timeOnlyAliases)
        let reportedProfitIdx = bestIndex(headers, aliases: reportedProfitAliases)
        
        guard let sIdx = symbolIdx, let sdIdx = sideIdx, let qIdx = qtyIdx, let pIdx = priceIdx else {
            return ImportPreview(
                totalRows: rows.count - 1,
                usableExecutions: [],
                problems: [
                    ImportRowProblem(lineNumber: 1, symbol: "-", reason: "Required columns not found: Symbol, Side (Buy/Sell), Quantity, Price.")
                ],
                duplicateCount: 0
            )
        }
        
        var usable: [Execution] = []
        var problems: [ImportRowProblem] = []
        var duplicateCount = 0
        var batchHashes = Set<String>()
        
        let legacyTz = legacyTimeZone ?? timeZone
        let legacyDiffers = legacyTz != timeZone
        
        for lineNum in 2...rows.count {
            let row = rows[lineNum - 1]
            if row.allSatisfy({ $0.isEmpty }) { continue }
            
            let symbol = sIdx < row.count ? row[sIdx].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() : ""
            if symbol.isEmpty {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: "N/A", reason: "Asset symbol is missing."))
                continue
            }
            
            let rawSide = sdIdx < row.count ? row[sdIdx].lowercased().trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let side: ExecutionSide
            if ["buy", "b", "bot", "long"].contains(rawSide) {
                side = .buy
            } else if ["sell", "s", "sld", "short"].contains(rawSide) {
                side = .sell
            } else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Side must be Buy or Sell (parsed: '\(rawSide)')."))
                continue
            }
            
            let rawQty = qIdx < row.count ? row[qIdx] : ""
            guard let quantity = parseDecimal(rawQty), quantity > 0 else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Quantity must be a valid positive number."))
                continue
            }
            
            let rawPrice = pIdx < row.count ? row[pIdx] : ""
            guard let price = parseDecimal(rawPrice), price >= 0 else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Price must be a valid non-negative number."))
                continue
            }
            
            // Commission is a cost: broker statements list it as a positive or negative amount.
            var fee: Decimal = 0
            if let fIdx = feeIdx, fIdx < row.count {
                fee = abs(parseDecimal(row[fIdx]) ?? 0)
            }
            // A rebate is a credit and therefore reduces the total cost.
            if let rIdx = rebateIdx, rIdx < row.count {
                fee -= abs(parseDecimal(row[rIdx]) ?? 0)
            }
            
            // Swap / overnight interest: negative = cost charged, positive = credit received.
            let swap: Decimal?
            if let swIdx = swapIdx, swIdx < row.count, let parsedSwap = parseDecimal(row[swIdx]), parsedSwap != 0 {
                swap = parsedSwap
            } else {
                swap = nil
            }
            
            var executedAt: Date?
            var dateStr = ""
            if let dIdx = dateIdx, dIdx < row.count {
                dateStr = row[dIdx]
                if let tIdx = timeIdx, tIdx < row.count {
                    dateStr += " " + row[tIdx]
                }
                executedAt = parseDateTime(dateStr, timeZone: timeZone)
            }
            
            guard let validDate = executedAt else {
                problems.append(ImportRowProblem(lineNumber: lineNum, symbol: symbol, reason: "Execution timestamp is invalid or missing."))
                continue
            }
            
            // Unique signature deduplicating identical fills across batches.
            // The canonical symbol keeps "EURUSD" and "EURUSDm" pointing at the same fill and the
            // timestamp text keeps the hash independent of the device timezone, so re-importing the
            // same statement can no longer duplicate fills.
            let canonical = AssetContractEngine.canonicalSymbol(symbol)
            let rawTimeKey = dateStr.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let hash = "\(accountId)|\(canonical)|\(side.rawValue)|\(quantity)|\(price)|\(rawTimeKey)"
            
            // Legacy hash (raw symbol + legacy timezone) so statements imported by older builds are
            // still detected as duplicates instead of being imported twice.
            var legacyHashes: [String] = []
            if legacyDiffers, let legacyDate = parseDateTime(dateStr, timeZone: legacyTz) {
                let legacyIso = ISO8601DateFormatter().string(from: legacyDate)
                legacyHashes.append("\(accountId)|\(symbol)|\(side.rawValue)|\(quantity)|\(price)|\(legacyIso)")
                legacyHashes.append("\(accountId)|\(canonical)|\(side.rawValue)|\(quantity)|\(price)|\(legacyIso)")
            }
            
            let isDuplicate = existingHashes.contains(hash)
                || batchHashes.contains(hash)
                || legacyHashes.contains(where: { existingHashes.contains($0) || batchHashes.contains($0) })
            if isDuplicate {
                duplicateCount += 1
                continue
            }
            batchHashes.insert(hash)
            batchHashes.formUnion(legacyHashes)
            
            // Keep the broker reported P&L for auditing purposes; the app recomputes it from prices.
            var importMetadata: String? = nil
            if let rpIdx = reportedProfitIdx, rpIdx < row.count, let reported = parseDecimal(row[rpIdx]) {
                importMetadata = "{\"reportedProfit\":\"\(reported)\"}"
            }
            
            let execution = Execution(
                id: UUID().uuidString,
                accountId: accountId,
                symbol: symbol,
                side: side,
                quantity: quantity,
                price: price,
                fee: fee,
                swap: swap,
                executedAt: validDate,
                source: "import",
                contentHash: hash,
                importMetadataJson: importMetadata
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
