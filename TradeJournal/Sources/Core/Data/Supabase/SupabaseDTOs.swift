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
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.key = trade.key
        self.accountId = trade.accountId
        self.symbol = trade.symbol
        self.assetClass = trade.assetClass
        self.direction = trade.direction.rawValue
        self.status = trade.status.rawValue
        self.openedAt = fmt.string(from: trade.openedAt)
        self.closedAt = trade.closedAt.map { fmt.string(from: $0) }
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
        self.reviewedAt = trade.reviewedAt.map { fmt.string(from: $0) }
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
        let fmt = ISO8601DateFormatter()
        self.id = execution.id
        self.accountId = execution.accountId
        self.symbol = execution.symbol
        self.side = execution.side.rawValue
        self.quantity = execution.quantity
        self.price = execution.price
        self.fee = execution.fee
        self.swap = execution.swap ?? 0
        self.executedAt = fmt.string(from: execution.executedAt)
        self.assetClass = execution.assetClass
        self.source = execution.source
        self.importMetadataJson = execution.importMetadataJson
        self.contentHash = execution.contentHash
        self.createdAt = fmt.string(from: execution.executedAt)
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

// MARK: - Supabase Missed Trade Record
public struct SupabaseMissedTradeRecord: Codable {
    public let id: String
    public let symbol: String
    public let direction: String
    public let observedAt: String
    public let playbookId: String?
    public let entry: Decimal?
    public let stop: Decimal?
    public let target: Decimal?
    public let notes: String
    public let createdAt: String
    public let archivedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, symbol, direction, notes
        case observedAt = "observed_at"
        case playbookId = "playbook_id"
        case entry, stop, target
        case createdAt = "created_at"
        case archivedAt = "archived_at"
    }
    
    public init(trade: MissedTrade) {
        self.id = trade.id
        self.symbol = trade.symbol
        self.direction = trade.direction
        self.observedAt = trade.observedAt
        self.playbookId = trade.playbookId
        self.entry = trade.entry
        self.stop = trade.stop
        self.target = trade.target
        self.notes = trade.notes
        self.createdAt = trade.createdAt
        self.archivedAt = trade.archivedAt
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(direction, forKey: .direction)
        try c.encode(observedAt, forKey: .observedAt)
        try c.encode(playbookId, forKey: .playbookId)
        try c.encode(entry.map { supabaseDecimalString($0) }, forKey: .entry)
        try c.encode(stop.map { supabaseDecimalString($0) }, forKey: .stop)
        try c.encode(target.map { supabaseDecimalString($0) }, forKey: .target)
        try c.encode(notes, forKey: .notes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(archivedAt, forKey: .archivedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? "UNKNOWN"
        self.direction = c.decodeString(forKeys: ["direction", "side"]) ?? "long"
        self.observedAt = c.decodeString(forKeys: ["observed_at", "observedAt"]) ?? JournalIds.nowIso()
        self.playbookId = c.decodeString(forKeys: ["playbook_id", "playbookId"])
        self.entry = c.decodeDecimal(forKeys: ["entry"])
        self.stop = c.decodeDecimal(forKeys: ["stop", "stop_loss", "stopLoss"])
        self.target = c.decodeDecimal(forKeys: ["target", "take_profit", "takeProfit"])
        self.notes = c.decodeString(forKeys: ["notes"]) ?? ""
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.archivedAt = c.decodeString(forKeys: ["archived_at", "archivedAt"])
    }
    
    public func toTrade() -> MissedTrade {
        MissedTrade(
            id: id,
            symbol: symbol,
            direction: direction,
            observedAt: observedAt,
            playbookId: playbookId,
            entry: entry,
            stop: stop,
            target: target,
            notes: notes,
            createdAt: createdAt,
            archivedAt: archivedAt
        )
    }
}

// MARK: - PostgREST Trade Excursion Record DTO
public struct SupabaseTradeExcursionRecord: Codable {
    public let tradeKey: String
    public let fingerprint: String
    public let provider: String
    public let symbol: String
    public let resolution: String
    public let maeDollar: Decimal?
    public let mfeDollar: Decimal?
    public let maePoints: Decimal?
    public let mfePoints: Decimal?
    public let estimateJson: String
    public let fetchedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case fingerprint, provider, symbol, resolution
        case tradeKey = "trade_key"
        case maeDollar = "mae_dollar"
        case mfeDollar = "mfe_dollar"
        case maePoints = "mae_points"
        case mfePoints = "mfe_points"
        case estimateJson = "estimate_json"
        case fetchedAt = "fetched_at"
    }
    
    public init(excursion: TradeExcursion) {
        self.tradeKey = excursion.tradeKey
        self.fingerprint = excursion.fingerprint
        self.provider = excursion.provider
        self.symbol = excursion.symbol
        self.resolution = excursion.resolution
        self.maeDollar = excursion.maeDollar
        self.mfeDollar = excursion.mfeDollar
        self.maePoints = excursion.estimate?.maePoints
        self.mfePoints = excursion.estimate?.mfePoints
        self.estimateJson = excursion.estimateJson
        self.fetchedAt = excursion.fetchedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.tradeKey = c.decodeString(forKeys: ["trade_key", "tradeKey"]) ?? ""
        self.fingerprint = c.decodeString(forKeys: ["fingerprint"]) ?? ""
        self.provider = c.decodeString(forKeys: ["provider"]) ?? "oanda"
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? ""
        self.resolution = c.decodeString(forKeys: ["resolution"]) ?? "15m"
        self.maeDollar = c.decodeDecimal(forKeys: ["mae_dollar", "maeDollar"])
        self.mfeDollar = c.decodeDecimal(forKeys: ["mfe_dollar", "mfeDollar"])
        self.maePoints = c.decodeDecimal(forKeys: ["mae_points", "maePoints"])
        self.mfePoints = c.decodeDecimal(forKeys: ["mfe_points", "mfePoints"])
        self.estimateJson = c.decodeString(forKeys: ["estimate_json", "estimateJson"]) ?? "{}"
        self.fetchedAt = c.decodeString(forKeys: ["fetched_at", "fetchedAt"]) ?? JournalIds.nowIso()
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tradeKey, forKey: .tradeKey)
        try c.encode(fingerprint, forKey: .fingerprint)
        try c.encode(provider, forKey: .provider)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(resolution, forKey: .resolution)
        try c.encodeIfPresent(maeDollar.map { supabaseDecimalString($0) }, forKey: .maeDollar)
        try c.encodeIfPresent(mfeDollar.map { supabaseDecimalString($0) }, forKey: .mfeDollar)
        try c.encodeIfPresent(maePoints.map { supabaseDecimalString($0) }, forKey: .maePoints)
        try c.encodeIfPresent(mfePoints.map { supabaseDecimalString($0) }, forKey: .mfePoints)
        try c.encode(estimateJson, forKey: .estimateJson)
        try c.encode(fetchedAt, forKey: .fetchedAt)
    }
    
    public func toExcursion() -> TradeExcursion {
        TradeExcursion(
            tradeKey: tradeKey,
            fingerprint: fingerprint,
            provider: provider,
            symbol: symbol,
            resolution: resolution,
            fetchedAt: fetchedAt,
            datasetId: nil,
            estimateJson: estimateJson
        )
    }
}

// MARK: - PostgREST Session Footprint Profile DTO
public struct SupabaseSessionProfileRecord: Codable, Sendable {
    public let id: String
    public let userId: String?
    public let symbol: String
    public let sessionType: String
    public let sessionDate: String
    public let startTime: String
    public let endTime: String
    public let pocPrice: String
    public let vahPrice: String
    public let valPrice: String
    public let profileHigh: String
    public let profileLow: String
    public let totalVolume: String
    public let isNaked: Bool
    public let mitigatedAt: String?
    public let createdAt: String

    public init(snapshot: SessionProfileSnapshot, userId: String? = nil) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        self.id = snapshot.id
        self.userId = userId
        self.symbol = snapshot.symbol
        self.sessionType = snapshot.sessionType.rawValue
        self.sessionDate = snapshot.sessionDate
        self.startTime = isoFormatter.string(from: snapshot.startTime)
        self.endTime = isoFormatter.string(from: snapshot.endTime)
        self.pocPrice = supabaseDecimalString(snapshot.pocPrice)
        self.vahPrice = supabaseDecimalString(snapshot.vahPrice)
        self.valPrice = supabaseDecimalString(snapshot.valPrice)
        self.profileHigh = supabaseDecimalString(snapshot.profileHigh)
        self.profileLow = supabaseDecimalString(snapshot.profileLow)
        self.totalVolume = supabaseDecimalString(snapshot.totalVolume)
        self.isNaked = snapshot.isNaked
        self.mitigatedAt = snapshot.mitigatedAt.map { isoFormatter.string(from: $0) }
        self.createdAt = isoFormatter.string(from: snapshot.createdAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? JournalIds.newId()
        self.userId = c.decodeString(forKeys: ["user_id", "userId"])
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? ""
        self.sessionType = c.decodeString(forKeys: ["session_type", "sessionType"]) ?? "daily"
        self.sessionDate = c.decodeString(forKeys: ["session_date", "sessionDate"]) ?? ""
        self.startTime = c.decodeString(forKeys: ["start_time", "startTime"]) ?? JournalIds.nowIso()
        self.endTime = c.decodeString(forKeys: ["end_time", "endTime"]) ?? JournalIds.nowIso()
        self.pocPrice = c.decodeString(forKeys: ["poc_price", "pocPrice"]) ?? "0"
        self.vahPrice = c.decodeString(forKeys: ["vah_price", "vahPrice"]) ?? "0"
        self.valPrice = c.decodeString(forKeys: ["val_price", "valPrice"]) ?? "0"
        self.profileHigh = c.decodeString(forKeys: ["profile_high", "profileHigh"]) ?? "0"
        self.profileLow = c.decodeString(forKeys: ["profile_low", "profileLow"]) ?? "0"
        self.totalVolume = c.decodeString(forKeys: ["total_volume", "totalVolume"]) ?? "0"
        self.isNaked = c.decodeBool(forKeys: ["is_naked", "isNaked"]) ?? true
        self.mitigatedAt = c.decodeString(forKeys: ["mitigated_at", "mitigatedAt"])
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(id, forKey: AnyCodingKey(stringValue: "id")!)
        if let uid = userId {
            try c.encode(uid, forKey: AnyCodingKey(stringValue: "user_id")!)
        }
        try c.encode(symbol, forKey: AnyCodingKey(stringValue: "symbol")!)
        try c.encode(sessionType, forKey: AnyCodingKey(stringValue: "session_type")!)
        try c.encode(sessionDate, forKey: AnyCodingKey(stringValue: "session_date")!)
        try c.encode(startTime, forKey: AnyCodingKey(stringValue: "start_time")!)
        try c.encode(endTime, forKey: AnyCodingKey(stringValue: "end_time")!)
        try c.encode(pocPrice, forKey: AnyCodingKey(stringValue: "poc_price")!)
        try c.encode(vahPrice, forKey: AnyCodingKey(stringValue: "vah_price")!)
        try c.encode(valPrice, forKey: AnyCodingKey(stringValue: "val_price")!)
        try c.encode(profileHigh, forKey: AnyCodingKey(stringValue: "profile_high")!)
        try c.encode(profileLow, forKey: AnyCodingKey(stringValue: "profile_low")!)
        try c.encode(totalVolume, forKey: AnyCodingKey(stringValue: "total_volume")!)
        try c.encode(isNaked, forKey: AnyCodingKey(stringValue: "is_naked")!)
        if let m = mitigatedAt {
            try c.encode(m, forKey: AnyCodingKey(stringValue: "mitigated_at")!)
        }
        try c.encode(createdAt, forKey: AnyCodingKey(stringValue: "created_at")!)
    }

    public func toSnapshot() -> SessionProfileSnapshot {
        let sTime = FlexibleDateParser.parse(startTime) ?? Date()
        let eTime = FlexibleDateParser.parse(endTime) ?? Date()
        let cTime = FlexibleDateParser.parse(createdAt) ?? Date()
        let mTime = FlexibleDateParser.parse(mitigatedAt)
        
        let pocDec = Decimal(string: pocPrice) ?? .zero
        let vahDec = Decimal(string: vahPrice) ?? .zero
        let valDec = Decimal(string: valPrice) ?? .zero
        let hiDec = Decimal(string: profileHigh) ?? .zero
        let loDec = Decimal(string: profileLow) ?? .zero
        let volDec = Decimal(string: totalVolume) ?? .zero
        let sType = FootprintSessionType(rawValue: sessionType) ?? .daily
        
        return SessionProfileSnapshot(
            id: id,
            symbol: symbol,
            sessionType: sType,
            sessionDate: sessionDate,
            startTime: sTime,
            endTime: eTime,
            pocPrice: pocDec,
            vahPrice: vahDec,
            valPrice: valDec,
            profileHigh: hiDec,
            profileLow: loDec,
            totalVolume: volDec,
            isNaked: isNaked,
            mitigatedAt: mTime,
            createdAt: cTime
        )
    }
}

