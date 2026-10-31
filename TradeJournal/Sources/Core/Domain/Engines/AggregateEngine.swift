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
    
    public static let utcTimeZone: TimeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

    /// Determines trading session based on trade open time in UTC:
    /// - Asian: 00:00 - 08:00 UTC
    /// - London: 08:00 - 13:00 UTC
    /// - London/NY Overlap: 13:00 - 16:00 UTC
    /// - New York: 16:00 - 21:00 UTC
    /// - Off-hours: 21:00 - 24:00 UTC
    public static func session(for date: Date) -> TradingSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
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
    public static func weekday(for date: Date, timeZone: TimeZone = utcTimeZone) -> Weekday {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekdayIndex = calendar.component(.weekday, from: date) // 1 = Sunday, 7 = Saturday
        let mapping: [Int: Weekday] = [
            1: .sun, 2: .mon, 3: .tue, 4: .wed, 5: .thu, 6: .fri, 7: .sat
        ]
        return mapping[weekdayIndex] ?? .sun
    }
    
    /// Hour of day (0-23) in given timezone
    public static func hour(for date: Date, timeZone: TimeZone = utcTimeZone) -> Int {
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
    
    public static func byWeekday(trades: [Trade], timeZone: TimeZone = utcTimeZone) -> [BucketStats] {
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
    
    public static func byHour(trades: [Trade], timeZone: TimeZone = utcTimeZone) -> [BucketStats] {
        group(trades: trades) { [String(format: "%02d", hour(for: $0.openedAt, timeZone: timeZone))] }
            .sorted { $0.key < $1.key }
    }
    
    public static func byDuration(trades: [Trade]) -> [BucketStats] {
        let tradesWithDuration = trades.filter { $0.durationMs != nil }
        let buckets = group(trades: tradesWithDuration) { trade in
            guard let ms = trade.durationMs else { return [] }
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

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func byMonth(trades: [Trade], timeZone: TimeZone = utcTimeZone) -> [BucketStats] {
        monthFormatter.timeZone = timeZone
        let closedTrades = trades.filter { $0.closedAt != nil }
        return group(trades: closedTrades) { trade in
            guard let closed = trade.closedAt else { return [] }
            return [monthFormatter.string(from: closed)]
        }.sorted { $0.key < $1.key }
    }

    public static func dayKeyOf(date: Date, timeZone: TimeZone = .current) -> String {
        dayFormatter.timeZone = timeZone
        return dayFormatter.string(from: date)
    }

    public static func dayKeyOf(date: Date, timeZone: String) -> String {
        let tz = TimeZone(identifier: timeZone) ?? TimeZone(identifier: "UTC") ?? .current
        return dayKeyOf(date: date, timeZone: tz)
    }

    // MARK: - Calendar Aggregations (1:1 port from aggregate.ts)

    public static func calendarMonth(
        trades: [Trade],
        year: Int,
        month: Int,
        timeZone: TimeZone = utcTimeZone
    ) -> CalendarMonth {
        calendarMonthFromDays(
            dayStats: FinancialMetricsEngine.dailyStats(trades: trades, timeZone: timeZone),
            year: year,
            month: month
        )
    }

    public static func calendarMonthFromDays(
        dayStats: [DayStats],
        year: Int,
        month: Int
    ) -> CalendarMonth {
        let monthPrefix = String(format: "%04d-%02d", year, month)
        var days: [String: DayStats] = [:]
        for d in dayStats where d.date.hasPrefix(monthPrefix) {
            days[d.date] = d
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utcTimeZone
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = 1
        let firstDate = cal.date(from: comp) ?? Date()
        let leadingBlanks = (cal.component(.weekday, from: firstDate) - 1)
        let daysInMonth = cal.range(of: .day, in: .month, for: firstDate)?.count ?? 30

        var cells: [DayStats?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...daysInMonth {
            let dateKey = String(format: "%@-%02d", monthPrefix, day)
            if let stat = days[dateKey] {
                cells.append(stat)
            } else {
                cells.append(DayStats(
                    date: dateKey,
                    netPnl: 0,
                    grossPnl: 0,
                    fees: 0,
                    trades: 0,
                    wins: 0,
                    losses: 0,
                    breakevens: 0,
                    volume: 0
                ))
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        var weeks: [CalendarWeek] = []
        for i in stride(from: 0, to: cells.count, by: 7) {
            let weekDays = Array(cells[i..<i+7])
            let weekNetPnl = weekDays.compactMap { $0?.netPnl }.reduce(Decimal.zero, +)
            let weekTrades = weekDays.compactMap { $0?.trades }.reduce(0, +)
            weeks.append(CalendarWeek(days: weekDays, weekNetPnl: weekNetPnl, weekTrades: weekTrades))
        }

        let traded = Array(days.values)
        let monthNetPnl = traded.reduce(Decimal.zero) { $0 + $1.netPnl }
        let monthTrades = traded.reduce(0) { $0 + $1.trades }
        let tradingDays = traded.filter { $0.trades > 0 }.count
        let winningDays = traded.filter { $0.netPnl > 0 }.count

        return CalendarMonth(
            year: year,
            month: month,
            weeks: weeks,
            monthNetPnl: monthNetPnl,
            monthTrades: monthTrades,
            tradingDays: tradingDays,
            winningDays: winningDays
        )
    }
}

public struct CalendarWeek: Equatable {
    public let days: [DayStats?]
    public let weekNetPnl: Decimal
    public let weekTrades: Int

    public init(days: [DayStats?], weekNetPnl: Decimal, weekTrades: Int) {
        self.days = days
        self.weekNetPnl = weekNetPnl
        self.weekTrades = weekTrades
    }
}

public struct CalendarMonth: Equatable {
    public let year: Int
    public let month: Int
    public let weeks: [CalendarWeek]
    public let monthNetPnl: Decimal
    public let monthTrades: Int
    public let tradingDays: Int
    public let winningDays: Int

    public init(
        year: Int,
        month: Int,
        weeks: [CalendarWeek],
        monthNetPnl: Decimal,
        monthTrades: Int,
        tradingDays: Int,
        winningDays: Int
    ) {
        self.year = year
        self.month = month
        self.weeks = weeks
        self.monthNetPnl = monthNetPnl
        self.monthTrades = monthTrades
        self.tradingDays = tradingDays
        self.winningDays = winningDays
    }
}

