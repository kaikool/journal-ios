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

public struct SupabasePlaybookRecord: Codable {
    public let id: String
    public let name: String
    public let description: String
    public let rulesJson: String
    public let createdAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, name, description
        case rulesJson = "rules_json"
        case createdAt = "created_at"
    }
    
    public init(playbook: Playbook) {
        let fmt = ISO8601DateFormatter()
        self.id = playbook.id
        self.name = playbook.name
        self.description = playbook.description
        self.rulesJson = (try? String(data: JSONEncoder().encode(playbook.rules), encoding: .utf8)) ?? "[]"
        self.createdAt = fmt.string(from: playbook.createdAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Playbook"
        self.description = c.decodeString(forKeys: ["description"]) ?? ""
        if let str = c.decodeString(forKeys: ["rules_json", "rulesJson", "rules"]) {
            self.rulesJson = str
        } else if let arr = c.decodeArray(type: String.self, forKeys: ["rules_json", "rulesJson", "rules"]) {
            self.rulesJson = (try? String(data: JSONEncoder().encode(arr), encoding: .utf8)) ?? "[]"
        } else {
            self.rulesJson = "[]"
        }
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toPlaybook() -> Playbook {
        let parsedRules = (try? JSONDecoder().decode([String].self, from: Data(rulesJson.utf8))) ?? []
        let parsedCreated = FlexibleDateParser.parse(createdAt) ?? Date()
        return Playbook(
            id: id,
            name: name,
            description: description,
            rules: parsedRules,
            createdAt: parsedCreated,
            updatedAt: parsedCreated
        )
    }
}

public struct SupabaseJournalDayRecord: Codable {
    public let date: String
    public let note: String
    public let updatedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case date
        case note
        case updatedAt = "updated_at"
    }
    
    public init(journalNote: JournalNote) {
        let fmt = ISO8601DateFormatter()
        self.date = journalNote.date
        self.note = journalNote.content
        self.updatedAt = fmt.string(from: journalNote.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.date = c.decodeString(forKeys: ["date"]) ?? ""
        self.note = c.decodeString(forKeys: ["note", "content"]) ?? ""
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"]) ?? JournalIds.nowIso()
    }
    
    public func toJournalNote() -> JournalNote {
        let parsedDate = FlexibleDateParser.parse(updatedAt) ?? Date()
        return JournalNote(
            date: date,
            content: note,
            createdAt: parsedDate,
            updatedAt: parsedDate
        )
    }
}

public struct SupabaseAccountRecord: Codable {
    public let id: String
    public let name: String
    public let broker: String
    public let kind: String
    public let currency: String
    public let initialBalance: Decimal
    public let profitCalcMethod: String
    public let autoSync: Bool
    public let lastSyncAt: String?
    public let archivedAt: String?
    public let createdAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, name, broker, kind, currency
        case initialBalance = "initial_balance"
        case profitCalcMethod = "profit_calc_method"
        case autoSync = "auto_sync"
        case lastSyncAt = "last_sync_at"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
    }
    
    public init(account: Account) {
        let fmt = ISO8601DateFormatter()
        self.id = account.id
        self.name = account.name
        self.broker = account.broker
        self.kind = account.kind.rawValue
        self.currency = account.currency
        self.initialBalance = account.initialBalance
        self.profitCalcMethod = account.profitCalcMethod.rawValue
        self.autoSync = account.autoSync
        self.lastSyncAt = account.lastSyncAt.map { fmt.string(from: $0) }
        self.archivedAt = account.archivedAt.map { fmt.string(from: $0) }
        self.createdAt = fmt.string(from: account.createdAt)
    }
    
    /// Balances are encoded as exact decimal strings (see `SupabaseTradeRecord.encode`).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(broker, forKey: .broker)
        try c.encode(kind, forKey: .kind)
        try c.encode(currency, forKey: .currency)
        try c.encode(supabaseDecimalString(initialBalance), forKey: .initialBalance)
        try c.encode(profitCalcMethod, forKey: .profitCalcMethod)
        try c.encode(autoSync, forKey: .autoSync)
        try c.encode(lastSyncAt, forKey: .lastSyncAt)
        try c.encode(archivedAt, forKey: .archivedAt)
        try c.encode(createdAt, forKey: .createdAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Account"
        self.broker = c.decodeString(forKeys: ["broker"]) ?? ""
        self.kind = c.decodeString(forKeys: ["kind", "type"]) ?? "trading"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.initialBalance = c.decodeDecimal(forKeys: ["initial_balance", "initialBalance", "balance", "starting_balance", "startingBalance"]) ?? 0
        self.profitCalcMethod = c.decodeString(forKeys: ["profit_calc_method", "profitCalcMethod"]) ?? "fifo"
        self.autoSync = c.decodeBool(forKeys: ["auto_sync", "autoSync"]) ?? false
        self.lastSyncAt = c.decodeString(forKeys: ["last_sync_at", "lastSyncAt"])
        self.archivedAt = c.decodeString(forKeys: ["archived_at", "archivedAt"])
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toAccount() -> Account {
        let parsedLastSync = FlexibleDateParser.parse(lastSyncAt)
        let parsedArchived = FlexibleDateParser.parse(archivedAt)
        let parsedCreated = FlexibleDateParser.parse(createdAt) ?? Date()
        
        return Account(
            id: id,
            name: name,
            broker: broker,
            kind: AccountKind(rawValue: kind) ?? .manual,
            currency: currency,
            initialBalance: initialBalance,
            profitCalcMethod: ProfitCalcMethod(rawValue: profitCalcMethod) ?? .fifo,
            autoSync: autoSync,
            lastSyncAt: parsedLastSync,
            archivedAt: parsedArchived,
            createdAt: parsedCreated
        )
    }
}

public struct SupabasePropAccountRecord: Codable {
    public let id: String
    public let firm: String
    public let name: String
    public let program: String
    public let status: String
    public let currency: String
    public let sizeMinor: Int64?
    public let parentId: String?
    public let journalAccountId: String?
    public let openedOn: String
    public let closedOn: String?
    public let renewalOn: String?
    public let renewalMinor: Int64?
    public let notes: String
    public let archived: Bool
    public let revision: Int
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firm, name, program, status, currency, notes, archived, revision
        case sizeMinor = "size_minor"
        case parentId = "parent_id"
        case journalAccountId = "journal_account_id"
        case openedOn = "opened_on"
        case closedOn = "closed_on"
        case renewalOn = "renewal_on"
        case renewalMinor = "renewal_minor"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(item: PropAccountItem) {
        self.id = item.id
        self.firm = item.firm
        self.name = item.name
        self.program = item.program.rawValue
        self.status = item.status.rawValue
        self.currency = item.currency
        self.sizeMinor = item.sizeMinor
        self.parentId = item.parentId
        self.journalAccountId = item.journalAccountId
        self.openedOn = item.openedOn
        self.closedOn = item.closedOn
        self.renewalOn = item.renewalOn
        self.renewalMinor = item.renewalMinor
        self.notes = item.notes
        self.archived = item.archived
        self.revision = item.revision
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.firm = c.decodeString(forKeys: ["firm"]) ?? "The5ers"
        self.name = c.decodeString(forKeys: ["name"]) ?? "Prop Account"
        self.program = c.decodeString(forKeys: ["program"]) ?? "evaluation"
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.sizeMinor = c.decodeInt64(forKeys: ["size_minor", "sizeMinor"])
        self.parentId = c.decodeString(forKeys: ["parent_id", "parentId"])
        self.journalAccountId = c.decodeString(forKeys: ["journal_account_id", "journalAccountId"])
        self.openedOn = c.decodeString(forKeys: ["opened_on", "openedOn", "created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.closedOn = c.decodeString(forKeys: ["closed_on", "closedOn"])
        self.renewalOn = c.decodeString(forKeys: ["renewal_on", "renewalOn"])
        self.renewalMinor = c.decodeInt64(forKeys: ["renewal_minor", "renewalMinor"])
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.archived = c.decodeBool(forKeys: ["archived"]) ?? false
        self.revision = c.decodeInt(forKeys: ["revision"]) ?? 1
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func toItem() -> PropAccountItem {
        return PropAccountItem(
            id: id,
            firm: firm,
            name: name,
            program: PropProgram(rawValue: program) ?? .evaluation,
            status: PropStatus(rawValue: status) ?? .active,
            currency: currency,
            sizeMinor: sizeMinor,
            parentId: parentId,
            journalAccountId: journalAccountId,
            openedOn: openedOn,
            closedOn: closedOn,
            renewalOn: renewalOn,
            renewalMinor: renewalMinor,
            notes: notes,
            archived: archived,
            revision: revision,
            createdAt: createdAt ?? JournalIds.nowIso(),
            updatedAt: updatedAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropEntryRecord: Codable {
    public let id: String
    public let accountId: String?
    public let firm: String
    public let kind: String
    public let category: String
    public let currency: String
    public let amountMinor: Int64
    public let splitBps: Int
    public let feeMinor: Int64
    public let occurredOn: String
    public let dueOn: String?
    public let status: String
    public let parentId: String?
    public let reference: String
    public let notes: String
    public let voided: Bool
    public let revision: Int
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firm, kind, category, currency, reference, notes, voided, revision
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case splitBps = "split_bps"
        case feeMinor = "fee_minor"
        case occurredOn = "occurred_on"
        case incurredOn = "incurred_on"
        case dueOn = "due_on"
        case status
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(item: PropEntryItem) {
        self.id = item.id
        self.accountId = item.accountId
        self.firm = item.firm
        self.kind = item.kind
        self.category = item.category
        self.currency = item.currency
        self.amountMinor = item.amountMinor
        self.splitBps = item.splitBps
        self.feeMinor = item.feeMinor
        self.occurredOn = item.occurredOn
        self.dueOn = item.dueOn
        self.status = item.status.rawValue
        self.parentId = item.parentId
        self.reference = item.reference
        self.notes = item.notes
        self.voided = item.voided
        self.revision = item.revision
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId"])
        self.firm = c.decodeString(forKeys: ["firm"]) ?? "The5ers"
        let rawKind = (c.decodeString(forKeys: ["kind", "type"]) ?? "expense").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if rawKind == "withdrawal" || rawKind == "withdraw" || rawKind == "payout" {
            self.kind = "payout"
        } else if rawKind == "refund" {
            self.kind = "refund"
        } else {
            self.kind = "expense"
        }
        self.category = c.decodeString(forKeys: ["category"]) ?? (self.kind == "payout" ? "payout" : "challenge_fee")
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.amountMinor = c.decodeInt64(forKeys: ["amount_minor", "amountMinor"]) ?? 0
        self.splitBps = c.decodeInt(forKeys: ["split_bps", "splitBps"]) ?? 8000
        self.feeMinor = c.decodeInt64(forKeys: ["fee_minor", "feeMinor"]) ?? 0
        let occ = c.decodeString(forKeys: ["occurred_on", "occurredOn", "incurred_on", "incurredOn"])
        self.occurredOn = occ ?? JournalIds.nowIso()
        self.dueOn = c.decodeString(forKeys: ["due_on", "dueOn"])
        self.status = c.decodeString(forKeys: ["status"]) ?? "completed"
        self.parentId = c.decodeString(forKeys: ["parent_id", "parentId"])
        self.reference = c.decodeString(forKeys: ["reference"]) ?? ""
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.voided = c.decodeBool(forKeys: ["voided"]) ?? false
        self.revision = c.decodeInt(forKeys: ["revision"]) ?? 1
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(accountId, forKey: .accountId)
        try c.encode(firm, forKey: .firm)
        try c.encode(kind, forKey: .kind)
        try c.encode(category, forKey: .category)
        try c.encode(currency, forKey: .currency)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(splitBps, forKey: .splitBps)
        try c.encode(feeMinor, forKey: .feeMinor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encodeIfPresent(dueOn, forKey: .dueOn)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encode(reference, forKey: .reference)
        try c.encode(notes, forKey: .notes)
        try c.encode(voided, forKey: .voided)
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toItem() -> PropEntryItem {
        return PropEntryItem(
            id: id,
            accountId: accountId,
            firm: firm,
            kind: kind,
            category: category,
            currency: currency,
            amountMinor: amountMinor,
            splitBps: splitBps,
            feeMinor: feeMinor,
            occurredOn: occurredOn,
            dueOn: dueOn,
            status: PayoutStatus(rawValue: status) ?? .completed,
            parentId: parentId,
            reference: reference,
            notes: notes,
            voided: voided,
            revision: revision,
            createdAt: createdAt ?? JournalIds.nowIso(),
            updatedAt: updatedAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropReceiptRecord: Codable {
    public let id: String
    public let payoutId: String
    public let kind: String
    public let amountMinor: Int64
    public let occurredOn: String
    public let reference: String
    public let notes: String
    public let voided: Bool
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, kind, reference, notes, voided
        case payoutId = "payout_id"
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case netAmountMinor = "net_amount_minor"
        case occurredOn = "occurred_on"
        case receivedOn = "received_on"
        case createdAt = "created_at"
    }
    
    public init(item: PropReceiptItem) {
        self.id = item.id
        self.payoutId = item.payoutId
        self.kind = item.kind
        self.amountMinor = item.amountMinor
        self.occurredOn = item.occurredOn
        self.reference = item.reference
        self.notes = item.notes
        self.voided = item.voided
        self.createdAt = item.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.payoutId = c.decodeString(forKeys: ["payout_id", "payoutId", "account_id", "accountId"]) ?? ""
        let rawKind = (c.decodeString(forKeys: ["kind", "type"]) ?? "receipt").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = (rawKind == "reversal") ? "reversal" : "receipt"
        self.amountMinor = c.decodeInt64(forKeys: ["amount_minor", "amountMinor", "net_amount_minor", "netAmountMinor"]) ?? 0
        let occ = c.decodeString(forKeys: ["occurred_on", "occurredOn", "received_on", "receivedOn"])
        self.occurredOn = occ ?? JournalIds.nowIso()
        self.reference = c.decodeString(forKeys: ["reference"]) ?? ""
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.voided = c.decodeBool(forKeys: ["voided"]) ?? false
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(payoutId, forKey: .payoutId)
        try c.encode(kind, forKey: .kind)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encode(reference, forKey: .reference)
        try c.encode(notes, forKey: .notes)
        try c.encode(voided, forKey: .voided)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
    
    public func toItem() -> PropReceiptItem {
        return PropReceiptItem(
            id: id,
            payoutId: payoutId,
            kind: kind,
            amountMinor: amountMinor,
            occurredOn: occurredOn,
            reference: reference,
            notes: notes,
            voided: voided,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropAuditRecord: Codable {
    public let id: String
    public let entityType: String
    public let entityId: String
    public let beforeJson: String?
    public let afterJson: String
    public let reason: String
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, reason
        case entityType = "entity_type"
        case entityId = "entity_id"
        case beforeJson = "before_json"
        case afterJson = "after_json"
        case createdAt = "created_at"
    }
    
    public init(item: PropAuditItem) {
        self.id = item.id
        self.entityType = item.entityType
        self.entityId = item.entityId
        self.beforeJson = item.beforeJson
        self.afterJson = item.afterJson
        self.reason = item.reason
        self.createdAt = item.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.entityType = c.decodeString(forKeys: ["entity_type", "entityType"]) ?? "entry"
        self.entityId = c.decodeString(forKeys: ["entity_id", "entityId"]) ?? ""
        self.beforeJson = c.decodeString(forKeys: ["before_json", "beforeJson"])
        self.afterJson = c.decodeString(forKeys: ["after_json", "afterJson"]) ?? "{}"
        self.reason = c.decodeString(forKeys: ["reason"]) ?? "sync"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func toItem() -> PropAuditItem {
        return PropAuditItem(
            id: id,
            entityType: entityType,
            entityId: entityId,
            beforeJson: beforeJson,
            afterJson: afterJson,
            reason: reason,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabaseAttachmentRecord: Codable {
    public let id: String
    public let ownerType: String
    public let ownerId: String
    public let name: String
    public let mime: String
    public let size: Int
    public let storagePath: String
    public let status: String
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, mime, size, status
        case ownerType = "owner_type"
        case ownerId = "owner_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
    
    public init(attachment: Attachment) {
        self.id = attachment.id
        self.ownerType = attachment.ownerType
        self.ownerId = attachment.ownerId
        self.name = attachment.name
        self.mime = attachment.mime
        self.size = attachment.size
        self.storagePath = attachment.storagePath
        self.status = attachment.status
        self.createdAt = attachment.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.ownerType = c.decodeString(forKeys: ["owner_type", "ownerType"]) ?? "trade"
        self.ownerId = c.decodeString(forKeys: ["owner_id", "ownerId"]) ?? ""
        self.name = c.decodeString(forKeys: ["name"]) ?? "Attachment"
        self.mime = c.decodeString(forKeys: ["mime"]) ?? "image/png"
        self.size = c.decodeInt(forKeys: ["size"]) ?? 0
        self.storagePath = c.decodeString(forKeys: ["storage_path", "storagePath"]) ?? ""
        self.status = c.decodeString(forKeys: ["status"]) ?? "ready"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func toAttachment() -> Attachment {
        return Attachment(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            name: name,
            mime: mime,
            size: size,
            storagePath: storagePath,
            status: status,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

// MARK: - Supabase Notebook Folder Record
public struct SupabaseFolderRecord: Codable {
    public let id: String
    public let name: String
    public let kind: String
    public let createdAt: String
    public let deletedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, kind
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
    
    public init(folder: NotebookFolder) {
        self.id = folder.id
        self.name = folder.name
        self.kind = folder.kind
        self.createdAt = folder.createdAt
        self.deletedAt = folder.deletedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Folder"
        self.kind = c.decodeString(forKeys: ["kind"]) ?? "user"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.deletedAt = c.decodeString(forKeys: ["deleted_at", "deletedAt"])
    }
    
    public func toFolder() -> NotebookFolder {
        NotebookFolder(
            id: id,
            name: name,
            kind: kind,
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }
}

// MARK: - Supabase Notebook Note Record
public struct SupabaseNoteRecord: Codable {
    public let id: String
    public let folderId: String
    public let title: String
    public let content: String
    public let tagsJson: String?
    public let tradeKey: String?
    public let dayDate: String?
    public let createdAt: String
    public let updatedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, title, content
        case folderId = "folder_id"
        case tagsJson = "tags_json"
        case tradeKey = "trade_key"
        case dayDate = "day_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(note: NotebookNote) {
        self.id = note.id
        self.folderId = note.folderId
        self.title = note.title
        self.content = note.content
        self.tagsJson = note.tagsJson
        self.tradeKey = note.tradeKey
        self.dayDate = note.dayDate
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.folderId = c.decodeString(forKeys: ["folder_id", "folderId"]) ?? ""
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.content = c.decodeString(forKeys: ["content"]) ?? ""
        self.tagsJson = c.decodeString(forKeys: ["tags_json", "tagsJson"])
        self.tradeKey = c.decodeString(forKeys: ["trade_key", "tradeKey"])
        self.dayDate = c.decodeString(forKeys: ["day_date", "dayDate"])
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"]) ?? JournalIds.nowIso()
    }
    
    public func toNote() -> NotebookNote {
        NotebookNote(
            id: id,
            folderId: folderId,
            title: title,
            content: content,
            tagsJson: tagsJson,
            tradeKey: tradeKey,
            dayDate: dayDate,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Supabase Progress Rule Record
public struct SupabaseProgressRuleRecord: Codable {
    public let id: String
    public let title: String
    public let stage: String
    public let weekdaysJson: String
    public let createdAt: String
    public let archivedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, title, stage
        case weekdaysJson = "weekdays_json"
        case createdAt = "created_at"
        case archivedAt = "archived_at"
    }
    
    public init(rule: ProgressRule) {
        self.id = rule.id
        self.title = rule.title
        self.stage = rule.stage
        self.weekdaysJson = rule.weekdaysJson
        self.createdAt = rule.createdAt
        self.archivedAt = rule.archivedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.stage = c.decodeString(forKeys: ["stage"]) ?? "Before trading"
        self.weekdaysJson = c.decodeString(forKeys: ["weekdays_json", "weekdaysJson"]) ?? "[1,2,3,4,5]"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.archivedAt = c.decodeString(forKeys: ["archived_at", "archivedAt"])
    }
    
    public func toRule() -> ProgressRule {
        ProgressRule(
            id: id,
            title: title,
            stage: stage,
            weekdaysJson: weekdaysJson,
            createdAt: createdAt,
            archivedAt: archivedAt
        )
    }
}

// MARK: - Supabase Progress Check Record
public struct SupabaseProgressCheckRecord: Codable {
    public let id: String
    public let ruleId: String
    public let date: String
    public let done: Bool
    
    private enum CodingKeys: String, CodingKey {
        case id, date, done
        case ruleId = "rule_id"
    }
    
    public init(check: ProgressCheck) {
        self.id = check.id
        self.ruleId = check.ruleId
        self.date = check.date
        self.done = check.done
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.ruleId = c.decodeString(forKeys: ["rule_id", "ruleId"]) ?? ""
        self.date = c.decodeString(forKeys: ["date"]) ?? ""
        self.done = c.decodeBool(forKeys: ["done"]) ?? false
    }
    
    public func toCheck() -> ProgressCheck {
        ProgressCheck(
            id: id,
            ruleId: ruleId,
            date: date,
            done: done
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

// MARK: - PostgREST AI Memory Record DTO
public struct SupabaseAIMemoryRecord: Codable {
    public let id: String
    public let category: String
    public let symbol: String?
    public let title: String
    public let content: String
    public let confidence: Double
    public let status: String
    public let supersededBy: String?
    public let sourceType: String
    public let sourceId: String?
    public let metadataJson: String
    public let createdAt: String
    public let updatedAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, category, symbol, title, content, confidence, status
        case supersededBy = "superseded_by"
        case sourceType = "source_type"
        case sourceId = "source_id"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(record: AIMemoryRecord) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = record.id
        self.category = record.category.rawValue
        self.symbol = record.symbol
        self.title = record.title
        self.content = record.content
        self.confidence = record.confidence
        self.status = record.status.rawValue
        self.supersededBy = record.supersededBy
        self.sourceType = record.sourceType.rawValue
        self.sourceId = record.sourceId
        self.metadataJson = record.metadataJson
        self.createdAt = iso.string(from: record.createdAt)
        self.updatedAt = iso.string(from: record.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.category = c.decodeString(forKeys: ["category"]) ?? "preference"
        self.symbol = c.decodeString(forKeys: ["symbol"])
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.content = c.decodeString(forKeys: ["content"]) ?? ""
        self.confidence = c.decodeDouble(forKeys: ["confidence"]) ?? 1.0
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.supersededBy = c.decodeString(forKeys: ["superseded_by", "supersededBy"])
        self.sourceType = c.decodeString(forKeys: ["source_type", "sourceType"]) ?? "manual"
        self.sourceId = c.decodeString(forKeys: ["source_id", "sourceId"])
        self.metadataJson = c.decodeString(forKeys: ["metadata_json", "metadataJson"]) ?? "{}"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"]) ?? JournalIds.nowIso()
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(supersededBy, forKey: .supersededBy)
        try c.encode(sourceType, forKey: .sourceType)
        try c.encodeIfPresent(sourceId, forKey: .sourceId)
        try c.encode(metadataJson, forKey: .metadataJson)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
    
    public func toRecord() -> AIMemoryRecord {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let created = iso.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) ?? Date()
        let updated = iso.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt) ?? Date()
        
        return AIMemoryRecord(
            id: id,
            category: AIMemoryCategory(rawValue: category) ?? .preference,
            symbol: symbol,
            title: title,
            content: content,
            confidence: confidence,
            status: AIMemoryStatus(rawValue: status) ?? .active,
            supersededBy: supersededBy,
            sourceType: AIMemorySourceType(rawValue: sourceType) ?? .manual,
            sourceId: sourceId,
            metadataJson: metadataJson,
            createdAt: created,
            updatedAt: updated
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

// MARK: - PostgREST DTO for trade_lesson_evaluations
public struct SupabaseTradeLessonEvaluationRecord: Codable, Sendable {
    public let id: String
    public let tradeId: String
    public let symbol: String
    public let taxonomy: String
    public let deviationPoints: Decimal?
    public let plannedRR: Decimal?
    public let realizedRR: Decimal?
    public let ruleBroken: String?
    public let lessonText: String
    public let verifiedCount: Int
    public let violatedCount: Int
    public let metadataJson: String
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, symbol, taxonomy
        case tradeId = "trade_id"
        case deviationPoints = "deviation_points"
        case plannedRR = "planned_rr"
        case realizedRR = "realized_rr"
        case ruleBroken = "rule_broken"
        case lessonText = "lesson_text"
        case verifiedCount = "verified_count"
        case violatedCount = "violated_count"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(evaluation: TradeLessonEvaluation) {
        self.id = evaluation.id
        self.tradeId = evaluation.tradeId
        self.symbol = evaluation.symbol
        self.taxonomy = evaluation.taxonomy.rawValue
        self.deviationPoints = evaluation.deviationPoints
        self.plannedRR = evaluation.plannedRR
        self.realizedRR = evaluation.realizedRR
        self.ruleBroken = evaluation.ruleBroken
        self.lessonText = evaluation.lessonText
        self.verifiedCount = evaluation.verifiedCount
        self.violatedCount = evaluation.violatedCount
        self.metadataJson = evaluation.metadataJson
        self.createdAt = ISO8601DateFormatter().string(from: evaluation.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: evaluation.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? JournalIds.prefixed("les_")
        self.tradeId = c.decodeString(forKeys: ["trade_id", "tradeId"]) ?? ""
        self.symbol = c.decodeString(forKeys: ["symbol"]) ?? ""
        self.taxonomy = c.decodeString(forKeys: ["taxonomy"]) ?? "unclassified"
        self.deviationPoints = c.decodeDecimal(forKeys: ["deviation_points", "deviationPoints"])
        self.plannedRR = c.decodeDecimal(forKeys: ["planned_rr", "plannedRR"])
        self.realizedRR = c.decodeDecimal(forKeys: ["realized_rr", "realizedRR"])
        self.ruleBroken = c.decodeString(forKeys: ["rule_broken", "ruleBroken"])
        self.lessonText = c.decodeString(forKeys: ["lesson_text", "lessonText"]) ?? ""
        self.verifiedCount = c.decodeInt(forKeys: ["verified_count", "verifiedCount"]) ?? 0
        self.violatedCount = c.decodeInt(forKeys: ["violated_count", "violatedCount"]) ?? 0
        self.metadataJson = c.decodeString(forKeys: ["metadata_json", "metadataJson"]) ?? "{}"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tradeId, forKey: .tradeId)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(taxonomy, forKey: .taxonomy)
        try c.encodeIfPresent(deviationPoints.map { supabaseDecimalString($0) }, forKey: .deviationPoints)
        try c.encodeIfPresent(plannedRR.map { supabaseDecimalString($0) }, forKey: .plannedRR)
        try c.encodeIfPresent(realizedRR.map { supabaseDecimalString($0) }, forKey: .realizedRR)
        try c.encodeIfPresent(ruleBroken, forKey: .ruleBroken)
        try c.encode(lessonText, forKey: .lessonText)
        try c.encode(verifiedCount, forKey: .verifiedCount)
        try c.encode(violatedCount, forKey: .violatedCount)
        try c.encode(metadataJson, forKey: .metadataJson)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toEvaluation() -> TradeLessonEvaluation {
        let formatter = ISO8601DateFormatter()
        let cDate = createdAt.flatMap { formatter.date(from: $0) } ?? Date()
        let uDate = updatedAt.flatMap { formatter.date(from: $0) } ?? Date()
        return TradeLessonEvaluation(
            id: id,
            tradeId: tradeId,
            symbol: symbol,
            taxonomy: TradeFailureTaxonomy(rawValue: taxonomy) ?? .unclassified,
            deviationPoints: deviationPoints,
            plannedRR: plannedRR,
            realizedRR: realizedRR,
            ruleBroken: ruleBroken,
            lessonText: lessonText,
            verifiedCount: verifiedCount,
            violatedCount: violatedCount,
            metadataJson: metadataJson,
            createdAt: cDate,
            updatedAt: uDate
        )
    }
}

// MARK: - PostgREST DTO for ai_research_projects (Module E)
public struct SupabaseAIResearchProjectRecord: Codable, Sendable {
    public let id: String
    public let title: String
    public let hypothesis: String
    public let status: String
    public let sampleCriteriaJson: String
    public let sampleCount: Int
    public let winRate: Decimal?
    public let profitFactor: Decimal?
    public let conclusion: String?
    public let metadataJson: String
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, title, hypothesis, status, conclusion
        case sampleCriteriaJson = "sample_criteria_json"
        case sampleCount = "sample_count"
        case winRate = "win_rate"
        case profitFactor = "profit_factor"
        case metadataJson = "metadata_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(project: AIResearchProject) {
        self.id = project.id
        self.title = project.title
        self.hypothesis = project.hypothesis
        self.status = project.status.rawValue
        
        let encoder = JSONEncoder()
        let criteriaData = (try? encoder.encode(project.criteria)) ?? Data()
        self.sampleCriteriaJson = String(data: criteriaData, encoding: .utf8) ?? "{}"
        
        self.sampleCount = project.sampleCount
        self.winRate = project.winRate.map { Decimal($0) }
        self.profitFactor = project.profitFactor.map { Decimal($0) }
        self.conclusion = project.conclusion
        
        // Encode checkpoints into metadataJson if needed
        var metaDict: [String: String] = [:]
        if let checkpointsData = try? encoder.encode(project.checkpoints),
           let chkStr = String(data: checkpointsData, encoding: .utf8) {
            metaDict["checkpoints"] = chkStr
        }
        let metaData = (try? encoder.encode(metaDict)) ?? Data()
        self.metadataJson = String(data: metaData, encoding: .utf8) ?? "{}"
        
        self.createdAt = ISO8601DateFormatter().string(from: project.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: project.updatedAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? JournalIds.prefixed("res_")
        self.title = c.decodeString(forKeys: ["title"]) ?? ""
        self.hypothesis = c.decodeString(forKeys: ["hypothesis"]) ?? ""
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.sampleCriteriaJson = c.decodeString(forKeys: ["sample_criteria_json", "sampleCriteriaJson"]) ?? "{}"
        self.sampleCount = c.decodeInt(forKeys: ["sample_count", "sampleCount"]) ?? 0
        self.winRate = c.decodeDecimal(forKeys: ["win_rate", "winRate"])
        self.profitFactor = c.decodeDecimal(forKeys: ["profit_factor", "profitFactor"])
        self.conclusion = c.decodeString(forKeys: ["conclusion"])
        self.metadataJson = c.decodeString(forKeys: ["metadata_json", "metadataJson"]) ?? "{}"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(hypothesis, forKey: .hypothesis)
        try c.encode(status, forKey: .status)
        try c.encode(sampleCriteriaJson, forKey: .sampleCriteriaJson)
        try c.encode(sampleCount, forKey: .sampleCount)
        try c.encodeIfPresent(winRate.map { supabaseDecimalString($0) }, forKey: .winRate)
        try c.encodeIfPresent(profitFactor.map { supabaseDecimalString($0) }, forKey: .profitFactor)
        try c.encodeIfPresent(conclusion, forKey: .conclusion)
        try c.encode(metadataJson, forKey: .metadataJson)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toProject() -> AIResearchProject {
        let formatter = ISO8601DateFormatter()
        let cDate = createdAt.flatMap { formatter.date(from: $0) } ?? Date()
        let uDate = updatedAt.flatMap { formatter.date(from: $0) } ?? Date()
        
        let decoder = JSONDecoder()
        var criteria = AIResearchSampleCriteria()
        if let cData = sampleCriteriaJson.data(using: .utf8),
           let decoded = try? decoder.decode(AIResearchSampleCriteria.self, from: cData) {
            criteria = decoded
        }
        
        var chks: [AIResearchCheckpoint] = []
        if let mData = metadataJson.data(using: .utf8),
           let metaDict = try? decoder.decode([String: String].self, from: mData),
           let chkStr = metaDict["checkpoints"],
           let chkData = chkStr.data(using: .utf8),
           let decodedChks = try? decoder.decode([AIResearchCheckpoint].self, from: chkData) {
            chks = decodedChks
        }
        
        let wrDouble = winRate.map { NSDecimalNumber(decimal: $0).doubleValue }
        let pfDouble = profitFactor.map { NSDecimalNumber(decimal: $0).doubleValue }
        
        return AIResearchProject(
            id: id,
            title: title,
            hypothesis: hypothesis,
            status: AIResearchProjectStatus(rawValue: status) ?? .active,
            criteria: criteria,
            checkpoints: chks,
            sampleCount: sampleCount,
            winRate: wrDouble,
            profitFactor: pfDouble,
            conclusion: conclusion,
            metadataJson: metadataJson,
            createdAt: cDate,
            updatedAt: uDate
        )
    }
}
