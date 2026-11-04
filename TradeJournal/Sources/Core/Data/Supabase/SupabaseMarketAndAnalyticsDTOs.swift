import Foundation

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

    private enum CodingKeys: String, CodingKey {
        case id, symbol
        case userId = "user_id"
        case sessionType = "session_type"
        case sessionDate = "session_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case pocPrice = "poc_price"
        case vahPrice = "vah_price"
        case valPrice = "val_price"
        case profileHigh = "profile_high"
        case profileLow = "profile_low"
        case totalVolume = "total_volume"
        case isNaked = "is_naked"
        case mitigatedAt = "mitigated_at"
        case createdAt = "created_at"
    }

    public init(snapshot: SessionProfileSnapshot, userId: String? = nil) {
        self.id = snapshot.id
        self.userId = userId
        self.symbol = snapshot.symbol
        self.sessionType = snapshot.sessionType.rawValue
        self.sessionDate = snapshot.sessionDate
        self.startTime = Formatters.iso8601String(from: snapshot.startTime)
        self.endTime = Formatters.iso8601String(from: snapshot.endTime)
        self.pocPrice = supabaseDecimalString(snapshot.pocPrice)
        self.vahPrice = supabaseDecimalString(snapshot.vahPrice)
        self.valPrice = supabaseDecimalString(snapshot.valPrice)
        self.profileHigh = supabaseDecimalString(snapshot.profileHigh)
        self.profileLow = supabaseDecimalString(snapshot.profileLow)
        self.totalVolume = supabaseDecimalString(snapshot.totalVolume)
        self.isNaked = snapshot.isNaked
        self.mitigatedAt = snapshot.mitigatedAt.map { Formatters.iso8601String(from: $0) }
        self.createdAt = Formatters.iso8601String(from: snapshot.createdAt)
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
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(sessionType, forKey: .sessionType)
        try c.encode(sessionDate, forKey: .sessionDate)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(endTime, forKey: .endTime)
        try c.encode(pocPrice, forKey: .pocPrice)
        try c.encode(vahPrice, forKey: .vahPrice)
        try c.encode(valPrice, forKey: .valPrice)
        try c.encode(profileHigh, forKey: .profileHigh)
        try c.encode(profileLow, forKey: .profileLow)
        try c.encode(totalVolume, forKey: .totalVolume)
        try c.encode(isNaked, forKey: .isNaked)
        try c.encodeIfPresent(mitigatedAt, forKey: .mitigatedAt)
        try c.encode(createdAt, forKey: .createdAt)
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
