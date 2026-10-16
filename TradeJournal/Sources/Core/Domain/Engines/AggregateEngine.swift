import Foundation

/// Represents the session name as defined in the source `time.ts`
public enum TradingSession: String, CaseIterable, Codable, Sendable {
    case asian = "Asian"
    case london = "London"
    case londonNyOverlap = "London/NY Overlap"
    case newYork = "New York"
    case offHours = "Off-hours"
}

public enum Weekday: String, CaseIterable, Codable, Sendable {
    case sun = "Sun"
    case mon = "Mon"
    case tue = "Tue"
    case wed = "Wed"
    case thu = "Thu"
    case fri = "Fri"
    case sat = "Sat"
}

/// Statistics for a discrete bucket (Symbol, Session, Weekday, Tag, etc.)
public struct BucketStats: Identifiable, Codable, Sendable, Equatable {
    public var id: String { key }
    public let key: String
    public let trades: Int
    public let netPnl: Decimal
    public let winRate: Decimal?
    public let profitFactor: Decimal?
    public let volume: Decimal

    public init(
        key: String,
        trades: Int,
        netPnl: Decimal,
        winRate: Decimal?,
        profitFactor: Decimal?,
        volume: Decimal
    ) {
        self.key = key
        self.trades = trades
        self.netPnl = netPnl
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.volume = volume
    }
}

/// Duration bucket boundaries matching `aggregate.ts`
public struct DurationBucket: Sendable {
    public let key: String
    public let maxMs: Double
    
    public static let standard: [DurationBucket] = [
        DurationBucket(key: "< 1m", maxMs: 60_000),
        DurationBucket(key: "1-5m", maxMs: 300_000),
        DurationBucket(key: "5-15m", maxMs: 900_000),
        DurationBucket(key: "15-60m", maxMs: 3_600_000),
        DurationBucket(key: "1-4h", maxMs: 14_400_000),
        DurationBucket(key: "4-24h", maxMs: 86_400_000),
        DurationBucket(key: "> 1d", maxMs: Double.infinity)
    ]
}

/// Engine to compute aggregate groupings across trades
public enum AggregateEngine {
    
    // MARK: - Time Calculations
    
    /// Determines trading session based on trade open time in UTC:
    /// - Asian: 00:00 - 08:00 UTC
    /// - London: 08:00 - 13:00 UTC
    /// - London/NY Overlap: 13:00 - 16:00 UTC
    /// - New York: 16:00 - 21:00 UTC
    /// - Off-hours: 21:00 - 24:00 UTC
    public static func session(for date: Date) -> TradingSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let hour = calendar.component(.hour, from: date)
        
        switch hour {
        case 0..<8:
            return .asian
        case 8..<13:
            return .london
        case 13..<16:
            return .londonNyOverlap
        case 16..<21:
            return .newYork
        default:
            return .offHours
        }
    }
    
    /// Weekday short name (Sun, Mon, Tue, Wed, Thu, Fri, Sat) in given timezone
    public static func weekday(for date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Weekday {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekdayIndex = calendar.component(.weekday, from: date) // 1 = Sunday, 7 = Saturday
        let mapping: [Int: Weekday] = [
            1: .sun, 2: .mon, 3: .tue, 4: .wed, 5: .thu, 6: .fri, 7: .sat
        ]
        return mapping[weekdayIndex] ?? .sun
    }
    
    /// Hour of day (0-23) in given timezone
    public static func hour(for date: Date, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }

    // MARK: - Bucket Calculation
    
    public static func calculateBucketStats(key: String, trades: [Trade]) -> BucketStats {
        var closed = 0
        var wins = 0
        var netPnl: Decimal = 0
        var profit: Decimal = 0
        var loss: Decimal = 0
        var volume: Decimal = 0
        
        for trade in trades {
            volume += trade.quantity
            guard trade.status != .open else { continue }
            closed += 1
            if trade.status == .win { wins += 1 }
            netPnl += trade.netPnl
            if trade.netPnl > 0 {
                profit += trade.netPnl
            } else if trade.netPnl < 0 {
                loss += trade.netPnl.magnitude
            }
        }
        
        let winRate: Decimal? = closed > 0 ? Decimal(wins) / Decimal(closed) : nil
        let profitFactor: Decimal? = loss > 0 ? profit / loss : nil
        
        return BucketStats(
            key: key,
            trades: trades.count,
            netPnl: netPnl,
            winRate: winRate,
            profitFactor: profitFactor,
            volume: volume
        )
    }
    
    private static func group(trades: [Trade], by keyExtractor: (Trade) -> [String]) -> [BucketStats] {
        var groups: [String: [Trade]] = [:]
        for trade in trades {
            let keys = keyExtractor(trade)
            for k in keys {
                groups[k, default: []].append(trade)
            }
        }
        return groups.map { (key, groupedTrades) in
            calculateBucketStats(key: key, trades: groupedTrades)
        }.sorted { $0.netPnl > $1.netPnl }
    }
    
    // MARK: - Aggregations
    
    public static func bySymbol(trades: [Trade]) -> [BucketStats] {
        group(trades: trades) { [$0.symbol] }
    }
    
    public static func byTag(trades: [Trade]) -> [BucketStats] {
        group(trades: trades) { $0.annotations?.tags ?? [] }
    }
    
    public static func byMistake(trades: [Trade]) -> [BucketStats] {
        group(trades: trades) { $0.annotations?.mistakes ?? [] }
    }
    
    public static func byPlaybook(trades: [Trade]) -> [BucketStats] {
        group(trades: trades) {
            if let pb = $0.annotations?.playbook, !pb.isEmpty {
                return [pb]
            }
            return []
        }
    }
    
    public static func byAssetClass(trades: [Trade]) -> [BucketStats] {
        group(trades: trades) { [$0.assetClass ?? "other"] }
    }
    
    public static func byDirection(trades: [Trade]) -> [BucketStats] {
        group(trades: trades) { [$0.direction.rawValue] }
    }
    
    public static func byWeekday(trades: [Trade], timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> [BucketStats] {
        let buckets = group(trades: trades) { [weekday(for: $0.openedAt, timeZone: timeZone).rawValue] }
        let order = Weekday.allCases.map { $0.rawValue }
        return buckets.sorted {
            let idxA = order.firstIndex(of: $0.key) ?? 999
            let idxB = order.firstIndex(of: $1.key) ?? 999
            return idxA < idxB
        }
    }
    
    public static func bySession(trades: [Trade]) -> [BucketStats] {
        let buckets = group(trades: trades) { [session(for: $0.openedAt).rawValue] }
        let order = TradingSession.allCases.map { $0.rawValue }
        return buckets.sorted {
            let idxA = order.firstIndex(of: $0.key) ?? 999
            let idxB = order.firstIndex(of: $1.key) ?? 999
            return idxA < idxB
        }
    }
    
    public static func byHour(trades: [Trade], timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> [BucketStats] {
        group(trades: trades) { [String(format: "%02d", hour(for: $0.openedAt, timeZone: timeZone))] }
            .sorted { $0.key < $1.key }
    }
    
    public static func byDuration(trades: [Trade]) -> [BucketStats] {
        let tradesWithDuration = trades.filter { $0.durationMs != nil }
        let buckets = group(trades: tradesWithDuration) { trade in
            let ms = trade.durationMs!
            let found = DurationBucket.standard.first { Double(ms) < $0.maxMs }
            return [found?.key ?? "> 1d"]
        }
        let order = DurationBucket.standard.map { $0.key }
        return buckets.sorted {
            let idxA = order.firstIndex(of: $0.key) ?? 999
            let idxB = order.firstIndex(of: $1.key) ?? 999
            return idxA < idxB
        }
    }
}
