import Foundation

// MARK: - PostgREST 1:1 Schema DTOs (Mapped to schema.pg.ts)

/// Encodes a decimal as an exact string so that no floating point rounding happens on the way to Postgres.
public func supabaseDecimalString(_ value: Decimal) -> String {
    let text = NSDecimalNumber(decimal: value).stringValue
    return text.isEmpty ? "0" : text
}

public struct AnyCodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

extension KeyedDecodingContainer where K == AnyCodingKey {
    func decodeString(forKeys keys: [String]) -> String? {
        for key in keys {
            if let k = AnyCodingKey(stringValue: key), let val = try? decode(String.self, forKey: k) {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
    
    func decodeArray<T: Decodable>(type: T.Type, forKeys keys: [String]) -> [T]? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let arr = try? decode([T].self, forKey: k) {
                return arr
            }
        }
        return nil
    }
    
    func decodeDouble(forKeys keys: [String]) -> Double? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Double.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k), let val = Double(str.trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
        return nil
    }
    
    /// Decodes a monetary value without losing precision (accepts JSON numbers and numeric strings).
    func decodeDecimal(forKeys keys: [String]) -> Decimal? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Decimal.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k) {
                let trimmed = str.trimmingCharacters(in: .whitespaces)
                if let val = Decimal(string: trimmed) { return val }
            }
        }
        return nil
    }
    
    func decodeInt(forKeys keys: [String]) -> Int? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Int.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k), let val = Int(str.trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
        return nil
    }
    
    func decodeInt64(forKeys keys: [String]) -> Int64? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Int64.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k), let val = Int64(str.trimmingCharacters(in: .whitespaces)) {
                return val
            }
        }
        return nil
    }
    
    func decodeBool(forKeys keys: [String]) -> Bool? {
        for key in keys {
            guard let k = AnyCodingKey(stringValue: key) else { continue }
            if let val = try? decode(Bool.self, forKey: k) {
                return val
            }
            if let str = try? decode(String.self, forKey: k) {
                let s = str.trimmingCharacters(in: .whitespaces).lowercased()
                if s == "true" || s == "1" || s == "yes" { return true }
                if s == "false" || s == "0" || s == "no" { return false }
            }
        }
        return nil
    }
}

public struct SupabaseTradeRecord: Codable {
    public let key: String
    public let accountId: String
    public let symbol: String
    public let assetClass: String?
    public let direction: String
    public let status: String
    public let openedAt: String
    public let closedAt: String?
    public let quantity: Decimal
    public let openQuantity: Decimal
    public let avgEntry: Decimal
    public let avgExit: Decimal?
    public let grossPnl: Decimal
    public let fees: Decimal
    public let swap: Decimal
    public let netPnl: Decimal
    public let executionCount: Int
    public let executionIdsJson: String
    public let exitsJson: String
    public let durationMs: Int64?
    public let notes: String?
    public let tagsJson: String?
    public let mistakesJson: String?
    public let playbookId: String?
    public let rating: Int?
    public let stopLoss: Decimal?
    public let profitTarget: Decimal?
    public let reviewedAt: String?
    public let mae: Decimal?
    public let mfe: Decimal?
    public let maePoints: Decimal?
    public let mfePoints: Decimal?
    
    private enum CodingKeys: String, CodingKey {
        case key, symbol, direction, status, quantity, fees, notes, rating, mae, mfe
        case accountId = "account_id"
        case assetClass = "asset_class"
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case openQuantity = "open_quantity"
        case avgEntry = "avg_entry"
        case avgExit = "avg_exit"
        case grossPnl = "gross_pnl"
        case swap = "swap"
        case netPnl = "net_pnl"
        case executionCount = "execution_count"
        case executionIdsJson = "execution_ids_json"
        case exitsJson = "exits_json"
        case durationMs = "duration_ms"
        case tagsJson = "tags_json"
        case mistakesJson = "mistakes_json"
        case playbookId = "playbook_id"
        case stopLoss = "stop_loss"
        case profitTarget = "profit_target"
        case reviewedAt = "reviewed_at"
        case maePoints = "mae_points"
        case mfePoints = "mfe_points"
    }
    
    public init(trade: Trade) {
        self.key = trade.key
        self.accountId = trade.accountId
        self.symbol = trade.symbol
        self.assetClass = trade.assetClass
        self.direction = trade.direction.rawValue
        self.status = trade.status.rawValue
        self.openedAt = Formatters.iso8601String(from: trade.openedAt)
        self.closedAt = trade.closedAt.map { Formatters.iso8601String(from: $0) }
        self.quantity = trade.quantity
        self.openQuantity = trade.openQuantity
        self.avgEntry = trade.avgEntry
        self.avgExit = trade.avgExit
        self.grossPnl = trade.grossPnl
        self.fees = trade.fees
        self.swap = trade.swapAmount
        self.netPnl = trade.netPnl
        self.executionCount = trade.executionCount
        
        let enc = JSONEncoder()
        self.executionIdsJson = (try? String(data: enc.encode(trade.executionIds), encoding: .utf8)) ?? "[]"
        self.exitsJson = (try? String(data: enc.encode(trade.exits), encoding: .utf8)) ?? "[]"
        self.durationMs = trade.durationMs
        self.notes = trade.notes
        self.tagsJson = (try? String(data: enc.encode(trade.tags), encoding: .utf8)) ?? "[]"
        self.mistakesJson = (try? String(data: enc.encode(trade.mistakes), encoding: .utf8)) ?? "[]"
        self.playbookId = trade.playbookId
        self.rating = trade.rating
        self.stopLoss = trade.stopLoss
        self.profitTarget = trade.profitTarget
        self.reviewedAt = trade.reviewedAt.map { Formatters.iso8601String(from: $0) }
        self.mae = trade.mae
        self.mfe = trade.mfe
        self.maePoints = trade.maePoints
        self.mfePoints = trade.mfePoints
    }
    
    /// Monetary values are encoded as exact decimal strings so that Postgres stores them in `numeric`
    /// columns without any binary floating point rounding.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(assetClass, forKey: .assetClass)
        try c.encode(direction, forKey: .direction)
        try c.encode(status, forKey: .status)
        try c.encode(openedAt, forKey: .openedAt)
        try c.encode(closedAt, forKey: .closedAt)
        try c.encode(supabaseDecimalString(quantity), forKey: .quantity)
        try c.encode(supabaseDecimalString(openQuantity), forKey: .openQuantity)
        try c.encode(supabaseDecimalString(avgEntry), forKey: .avgEntry)
        try c.encode(avgExit.map { supabaseDecimalString($0) }, forKey: .avgExit)
        try c.encode(supabaseDecimalString(grossPnl), forKey: .grossPnl)
        try c.encode(supabaseDecimalString(fees), forKey: .fees)
        try c.encode(supabaseDecimalString(swap), forKey: .swap)
        try c.encode(supabaseDecimalString(netPnl), forKey: .netPnl)
        try c.encode(executionCount, forKey: .executionCount)
        try c.encode(executionIdsJson, forKey: .executionIdsJson)
        try c.encode(exitsJson, forKey: .exitsJson)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(notes, forKey: .notes)
        try c.encode(tagsJson, forKey: .tagsJson)
        try c.encode(mistakesJson, forKey: .mistakesJson)
        try c.encode(playbookId, forKey: .playbookId)
        try c.encode(rating, forKey: .rating)
        try c.encode(stopLoss.map { supabaseDecimalString($0) }, forKey: .stopLoss)
        try c.encode(profitTarget.map { supabaseDecimalString($0) }, forKey: .profitTarget)
        try c.encode(reviewedAt, forKey: .reviewedAt)
        try c.encode(mae.map { supabaseDecimalString($0) }, forKey: .mae)
        try c.encode(mfe.map { supabaseDecimalString($0) }, forKey: .mfe)
        try c.encode(maePoints.map { supabaseDecimalString($0) }, forKey: .maePoints)
        try c.encode(mfePoints.map { supabaseDecimalString($0) }, forKey: .mfePoints)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.key = c.decodeString(forKeys: ["key", "id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId", "account"]) ?? ""
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? "UNKNOWN"
        self.assetClass = c.decodeString(forKeys: ["asset_class", "assetClass"])
        self.direction = c.decodeString(forKeys: ["direction", "side"]) ?? "long"
        self.status = c.decodeString(forKeys: ["status"]) ?? "open"
        self.openedAt = c.decodeString(forKeys: ["opened_at", "openedAt", "open_date", "opendate", "open_time", "opentime"]) ?? JournalIds.nowIso()
        self.closedAt = c.decodeString(forKeys: ["closed_at", "closedAt", "close_date", "closedate", "close_time", "closetime"])
        self.quantity = c.decodeDecimal(forKeys: ["quantity", "open_quantity", "size", "lots", "volume"]) ?? 0
        self.openQuantity = c.decodeDecimal(forKeys: ["open_quantity", "openQuantity"]) ?? 0
        self.avgEntry = c.decodeDecimal(forKeys: ["avg_entry", "avgEntry", "open_price", "entry_price", "entry"]) ?? 0
        self.avgExit = c.decodeDecimal(forKeys: ["avg_exit", "avgExit", "close_price", "exit_price", "exit"])
        self.grossPnl = c.decodeDecimal(forKeys: ["gross_pnl", "grossPnl", "gross"]) ?? 0
        self.fees = c.decodeDecimal(forKeys: ["fees", "fee", "commission"]) ?? 0
        self.swap = c.decodeDecimal(forKeys: ["swap"]) ?? 0
        self.netPnl = c.decodeDecimal(forKeys: ["net_pnl", "netPnl", "profit", "pnl"]) ?? 0
        self.executionCount = c.decodeInt(forKeys: ["execution_count", "executionCount"]) ?? 0
        
        // JSON string or native array of execution IDs
        if let str = c.decodeString(forKeys: ["execution_ids_json", "executionIdsJson", "execution_ids"]) {
            self.executionIdsJson = str
        } else if let arr = c.decodeArray(type: String.self, forKeys: ["execution_ids_json", "executionIdsJson", "execution_ids"]) {
            self.executionIdsJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.executionIdsJson = "[]"
        }
        
        // JSON string or native array of exit attributions
        if let str = c.decodeString(forKeys: ["exits_json", "exitsJson", "exits"]) {
            self.exitsJson = str
        } else if let arr = c.decodeArray(type: ExitAttribution.self, forKeys: ["exits_json", "exitsJson", "exits"]) {
            self.exitsJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.exitsJson = "[]"
        }
        
        self.durationMs = c.decodeInt64(forKeys: ["duration_ms", "durationMs"])
        self.notes = c.decodeString(forKeys: ["notes", "note"])
        
        if let str = c.decodeString(forKeys: ["tags_json", "tagsJson", "tags"]) {
            self.tagsJson = str
        } else if let arr = c.decodeArray(type: String.self, forKeys: ["tags_json", "tagsJson", "tags"]) {
            self.tagsJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.tagsJson = nil
        }
        
        if let str = c.decodeString(forKeys: ["mistakes_json", "mistakesJson", "mistakes"]) {
            self.mistakesJson = str
        } else if let arr = c.decodeArray(type: String.self, forKeys: ["mistakes_json", "mistakesJson", "mistakes"]) {
            self.mistakesJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.mistakesJson = nil
        }
        
        self.playbookId = c.decodeString(forKeys: ["playbook_id", "playbookId"])
        self.rating = c.decodeInt(forKeys: ["rating"])
        self.stopLoss = c.decodeDecimal(forKeys: ["stop_loss", "stopLoss"])
        self.profitTarget = c.decodeDecimal(forKeys: ["profit_target", "profitTarget"])
        self.reviewedAt = c.decodeString(forKeys: ["reviewed_at", "reviewedAt"])
        self.mae = c.decodeDecimal(forKeys: ["mae"])
        self.mfe = c.decodeDecimal(forKeys: ["mfe"])
        self.maePoints = c.decodeDecimal(forKeys: ["mae_points", "maePoints"])
        self.mfePoints = c.decodeDecimal(forKeys: ["mfe_points", "mfePoints"])
    }
    
    public func toTrade() -> Trade {
        let dec = JSONDecoder()
        let parsedOpenedAt = FlexibleDateParser.parse(openedAt) ?? Date()
        let parsedClosedAt = FlexibleDateParser.parse(closedAt)
        let parsedReviewedAt = FlexibleDateParser.parse(reviewedAt)
        let parsedExecIds = (try? dec.decode([String].self, from: Data(executionIdsJson.utf8))) ?? []
        let parsedExits = (try? dec.decode([ExitAttribution].self, from: Data(exitsJson.utf8))) ?? []
        let parsedTags = tagsJson.flatMap { (try? dec.decode([String].self, from: Data($0.utf8))) } ?? []
        let parsedMistakes = mistakesJson.flatMap { (try? dec.decode([String].self, from: Data($0.utf8))) } ?? []
        
        return Trade(
            key: key,
            accountId: accountId,
            symbol: symbol,
            assetClass: assetClass,
            direction: TradeDirection(rawValue: direction) ?? .long,
            status: TradeStatus(rawValue: status) ?? .open,
            openedAt: parsedOpenedAt,
            closedAt: parsedClosedAt,
            quantity: quantity,
            openQuantity: openQuantity,
            avgEntry: avgEntry,
            avgExit: avgExit,
            grossPnl: grossPnl,
            fees: fees,
            swap: swap,
            netPnl: netPnl,
            executionCount: executionCount,
            executionIds: parsedExecIds,
            exits: parsedExits,
            durationMs: durationMs,
            notes: notes,
            tags: parsedTags,
            mistakes: parsedMistakes,
            playbookId: playbookId,
            rating: rating,
            stopLoss: stopLoss,
            profitTarget: profitTarget,
            reviewedAt: parsedReviewedAt,
            mae: mae,
            mfe: mfe,
            maePoints: maePoints,
            mfePoints: mfePoints
        )
    }
}

public struct SupabaseExecutionRecord: Codable {
    public let id: String
    public let accountId: String
    public let symbol: String
    public let side: String
    public let quantity: Decimal
    public let price: Decimal
    public let fee: Decimal
    public let swap: Decimal
    public let executedAt: String
    public let assetClass: String?
    public let source: String
    public let importMetadataJson: String?
    public let contentHash: String
    public let createdAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, symbol, side, quantity, price, fee, source
        case accountId = "account_id"
        case swap = "swap"
        case executedAt = "executed_at"
        case assetClass = "asset_class"
        case importMetadataJson = "import_metadata_json"
        case contentHash = "content_hash"
        case createdAt = "created_at"
    }
    
    public init(execution: Execution) {
        self.id = execution.id
        self.accountId = execution.accountId
        self.symbol = execution.symbol
        self.side = execution.side.rawValue
        self.quantity = execution.quantity
        self.price = execution.price
        self.fee = execution.fee
        self.swap = execution.swap ?? 0
        self.executedAt = Formatters.iso8601String(from: execution.executedAt, fractionalSeconds: false)
        self.assetClass = execution.assetClass
        self.source = execution.source
        self.importMetadataJson = execution.importMetadataJson
        self.contentHash = execution.contentHash
        self.createdAt = Formatters.iso8601String(from: execution.executedAt, fractionalSeconds: false)
    }
    
    /// Monetary values are encoded as exact decimal strings (see `SupabaseTradeRecord.encode`).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(accountId, forKey: .accountId)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(side, forKey: .side)
        try c.encode(supabaseDecimalString(quantity), forKey: .quantity)
        try c.encode(supabaseDecimalString(price), forKey: .price)
        try c.encode(supabaseDecimalString(fee), forKey: .fee)
        try c.encode(supabaseDecimalString(swap), forKey: .swap)
        try c.encode(executedAt, forKey: .executedAt)
        try c.encode(assetClass, forKey: .assetClass)
        try c.encode(source, forKey: .source)
        try c.encode(importMetadataJson, forKey: .importMetadataJson)
        try c.encode(contentHash, forKey: .contentHash)
        try c.encode(createdAt, forKey: .createdAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId", "account"]) ?? ""
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? "UNKNOWN"
        self.side = c.decodeString(forKeys: ["side", "direction"]) ?? "buy"
        self.quantity = c.decodeDecimal(forKeys: ["quantity", "size", "lots", "volume"]) ?? 0
        self.price = c.decodeDecimal(forKeys: ["price", "entry"]) ?? 0
        self.fee = c.decodeDecimal(forKeys: ["fee", "commission", "fees"]) ?? 0
        self.swap = c.decodeDecimal(forKeys: ["swap"]) ?? 0
        self.executedAt = c.decodeString(forKeys: ["executed_at", "executedAt", "timestamp", "date"]) ?? JournalIds.nowIso()
        self.assetClass = c.decodeString(forKeys: ["asset_class", "assetClass"])
        self.source = c.decodeString(forKeys: ["source"]) ?? "manual"
        self.importMetadataJson = c.decodeString(forKeys: ["import_metadata_json", "importMetadataJson"])
        self.contentHash = c.decodeString(forKeys: ["content_hash", "contentHash"]) ?? UUID().uuidString
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toExecution() -> Execution {
        let parsedDate = FlexibleDateParser.parse(executedAt) ?? Date()
        return Execution(
            id: id,
            accountId: accountId,
            symbol: symbol,
            side: ExecutionSide(rawValue: side) ?? .buy,
            quantity: quantity,
            price: price,
            fee: fee,
            swap: swap,
            executedAt: parsedDate,
            assetClass: assetClass,
            source: source,
            contentHash: contentHash,
            importMetadataJson: importMetadataJson
        )
    }
}


