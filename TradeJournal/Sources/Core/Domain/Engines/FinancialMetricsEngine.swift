import Foundation

public struct TradeMetrics: Equatable {
    public let totalTrades: Int
    public let closedTrades: Int
    public let openTrades: Int
    public let wins: Int
    public let losses: Int
    public let breakevens: Int
    public let netPnl: Decimal
    public let grossPnl: Decimal?
    public let fees: Decimal?
    public let winRate: Double?
    public let dayWinRate: Double?
    public let tradingDays: Int
    public let profitFactor: Double?
    public let profitFactorIsInfinite: Bool
    public let avgWin: Decimal?
    public let avgLoss: Decimal?
    public let avgWinLossRatio: Double?
    public let expectancy: Decimal?
    public let largestWin: Decimal
    public let largestLoss: Decimal
    public let maxWinStreak: Int
    public let maxLossStreak: Int
    public let currentStreak: Int
    public let totalVolume: Decimal
    public let avgDurationMs: Int64?
    public let maxDrawdown: Decimal
    public let maxDrawdownPct: Double?
    public let recoveryFactor: Double?
    public let profitConcentration: Double?
    public let avgRealizedR: Double?
    public let tradesWithRisk: Int
}

extension TradeMetrics {
    /// Gross profit of the winning trades (net of fees and swap, so it matches the profit factor).
    public var profit: Decimal {
        netPnl > 0 ? netPnl : 0
    }
    /// Gross loss of the losing trades (net of fees and swap, so it matches the profit factor).
    public var loss: Decimal {
        netPnl < 0 ? abs(netPnl) : 0
    }
    public var winningTrades: Int { wins }
    public var losingTrades: Int { losses }
    public var breakevenTrades: Int { breakevens }
    public var maxConsecutiveWins: Int { maxWinStreak }
    public var maxConsecutiveLosses: Int { maxLossStreak }
}

public struct EquityPoint: Equatable {
    public let timestamp: Date
    public let dateString: String
    public let cumNetPnl: Decimal
    
    public init(timestamp: Date, dateString: String, cumNetPnl: Decimal) {
        self.timestamp = timestamp
        self.dateString = dateString
        self.cumNetPnl = cumNetPnl
    }
}

public struct DayStats: Equatable, Identifiable {
    public var id: String { date }
    public let date: String
    public var netPnl: Decimal
    public var grossPnl: Decimal?
    public var fees: Decimal?
    public var trades: Int
    public var wins: Int
    public var losses: Int
    public var breakevens: Int
    public var volume: Decimal
}

public struct DrawdownStats: Equatable {
    public let maxDrawdown: Decimal
    public let maxDrawdownPct: Double?
    public let peak: Decimal
}

public struct IntradayPoint: Equatable {
    public let t: String
    public let cumNetPnl: Decimal

    public init(t: String, cumNetPnl: Decimal) {
        self.t = t
        self.cumNetPnl = cumNetPnl
    }
}

/// High-performance financial metrics calculation engine matching web domain specifications
public enum FinancialMetricsEngine {
    public static let utcTimeZone: TimeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
    
    public static func computeOverview(trades: [Trade], timeZone: TimeZone = .current, initialBalance: Decimal = 0) -> (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        let curve = equityCurve(trades: trades)
        let days = dailyStats(trades: trades, timeZone: timeZone)
        let metrics = computeMetrics(trades: trades, curve: curve, days: days, initialBalance: initialBalance)
        return (metrics, curve, days)
    }
    
    /// Computes chronological cumulative equity points for all closed trades
    public static func equityCurve(trades: [Trade]) -> [EquityPoint] {
        let closedTrades = trades
            .filter { $0.status != .open }
            .sorted {
                let d0 = $0.closedAt ?? $0.openedAt
                let d1 = $1.closedAt ?? $1.openedAt
                if d0 != d1 {
                    return d0 < d1
                }
                return $0.key < $1.key
            }
        
        var cum: Decimal = 0
        let formatter = ISO8601DateFormatter()
        return closedTrades.map { trade in
            let date = trade.closedAt ?? trade.openedAt
            cum += trade.netPnl
            return EquityPoint(
                timestamp: date,
                dateString: formatter.string(from: date),
                cumNetPnl: cum
            )
        }
    }
    
    /// Aggregates trade performance by calendar date according to the specified timezone
    public static func dailyStats(trades: [Trade], timeZone: TimeZone = .current) -> [DayStats] {
        let closedTrades = trades
            .filter { $0.status != .open }
            .sorted {
                let d0 = $0.closedAt ?? $0.openedAt
                let d1 = $1.closedAt ?? $1.openedAt
                if d0 != d1 {
                    return d0 < d1
                }
                return $0.key < $1.key
            }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = timeZone
        
        var dayMap: [String: DayStats] = [:]
        
        for trade in closedTrades {
            let targetDate = trade.closedAt ?? trade.openedAt
            let dateKey = dateFormatter.string(from: targetDate)
            var day = dayMap[dateKey] ?? DayStats(
                date: dateKey,
                netPnl: 0,
                grossPnl: 0,
                fees: 0,
                trades: 0,
                wins: 0,
                losses: 0,
                breakevens: 0,
                volume: 0
            )
            
            day.netPnl += trade.netPnl
            if let currentGross = day.grossPnl {
                day.grossPnl = currentGross + trade.grossPnl
            }
            if let currentFees = day.fees {
                day.fees = currentFees + trade.fees
            }
            day.trades += 1
            day.volume += trade.quantity
            
            if trade.status == .win {
                day.wins += 1
            } else if trade.status == .loss {
                day.losses += 1
            } else {
                day.breakevens += 1
            }
            dayMap[dateKey] = day
        }
        
        return dayMap.values.sorted { $0.date < $1.date }
    }
    
    /// Daily cumulative net P&L curve (1:1 port from equity.ts)
    public static func dailyCumulative(trades: [Trade], timeZone: TimeZone = .current) -> [EquityPoint] {
        dailyCumulativeFromDays(days: dailyStats(trades: trades, timeZone: timeZone))
    }

    /// Daily cumulative net P&L from pre-computed daily stats (1:1 port from equity.ts)
    public static func dailyCumulativeFromDays(days: [DayStats]) -> [EquityPoint] {
        var cum: Decimal = 0
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return days.map { day in
            cum += day.netPnl
            // Anchor at noon UTC (12:00:00) so date rendering remains strictly on the same calendar day across all western and eastern time zones
            let parsedDate = (formatter.date(from: day.date) ?? Date()).addingTimeInterval(43200)
            return EquityPoint(timestamp: parsedDate, dateString: day.date, cumNetPnl: cum)
        }
    }

    /// Running realized P&L across one day, built from per-exit attributions (1:1 port from equity.ts)
    public static func intradayCurve(
        trades: [Trade],
        executionTimes: [String: Date],
        date: String,
        timeZone: TimeZone = utcTimeZone
    ) -> [IntradayPoint] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = timeZone

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var events: [(date: Date, t: String, pnl: Decimal)] = []

        for trade in trades {
            if trade.exits.isEmpty && trade.status != .open, let closedAt = trade.closedAt {
                if dateFormatter.string(from: closedAt) == date {
                    events.append((closedAt, isoFormatter.string(from: closedAt), trade.netPnl))
                }
                continue
            }
            let totalExitQty = trade.exits.reduce(Decimal.zero) { $0 + $1.quantity }
            for exit in trade.exits {
                guard let execTime = executionTimes[exit.executionId],
                      dateFormatter.string(from: execTime) == date else { continue }
                let share = totalExitQty > 0 ? (exit.quantity / totalExitQty) : 0
                let feeShare = trade.fees * share
                let swapShare = trade.swapAmount * share
                events.append((execTime, isoFormatter.string(from: execTime), exit.grossPnl - feeShare + swapShare))
            }
        }

        events.sort { $0.date < $1.date }
        var cum: Decimal = 0
        return events.map { event in
            cum += event.pnl
            return IntradayPoint(t: event.t, cumNetPnl: cum)
        }
    }
    
    /// Computes max drawdown absolute amount and percentage against initial balance
    public static func drawdown(curve: [EquityPoint], initialBalance: Decimal) -> DrawdownStats {
        var peak: Decimal = 0
        var maxDrawdown: Decimal = 0
        var peakAtMax: Decimal = 0
        
        for point in curve {
            if point.cumNetPnl > peak {
                peak = point.cumNetPnl
            }
            let fall = peak - point.cumNetPnl
            if fall > maxDrawdown {
                maxDrawdown = fall
                peakAtMax = peak
            }
        }
        
        let base = initialBalance + peakAtMax
        let maxDrawdownPct: Double? = base > 0 ? (NSDecimalNumber(decimal: maxDrawdown).doubleValue / NSDecimalNumber(decimal: base).doubleValue) : nil
        
        return DrawdownStats(maxDrawdown: maxDrawdown, maxDrawdownPct: maxDrawdownPct, peak: peak)
    }
    
    /// Calculates high-level performance metrics including profit factor, win rates, and streaks
    public static func computeMetrics(
        trades: [Trade],
        curve: [EquityPoint]? = nil,
        days: [DayStats]? = nil,
        initialBalance: Decimal = 0,
        timeZone: TimeZone = .current
    ) -> TradeMetrics {
        let curvePoints = curve ?? equityCurve(trades: trades)
        let dayStatsList = days ?? dailyStats(trades: trades, timeZone: timeZone)
        
        let closed = trades.filter { $0.status != .open }
        let wins = closed.filter { $0.status == .win }
        let losses = closed.filter { $0.status == .loss }
        let breakevens = closed.filter { $0.status == .breakeven }
        
        let grossProfit = closed.reduce(Decimal.zero) { $0 + max(0, $1.netPnl) }
        let grossLoss = closed.reduce(Decimal.zero) { $0 - min(0, $1.netPnl) }
        let netPnl = closed.reduce(Decimal.zero) { $0 + $1.netPnl }
        let totalFees = closed.reduce(Decimal.zero) { $0 + $1.fees }
        let totalGross = closed.reduce(Decimal.zero) { $0 + $1.grossPnl }
        
        let winRate: Double? = !closed.isEmpty ? (Double(wins.count) / Double(closed.count)) : nil
        let winningDays = dayStatsList.filter { $0.netPnl > 0 }.count
        let dayWinRate: Double? = !dayStatsList.isEmpty ? (Double(winningDays) / Double(dayStatsList.count)) : nil
        
        // Chronological order for streak analysis
        let ordered = closed.map { trade -> (Trade, Date) in
            let date = trade.closedAt ?? trade.openedAt
            return (trade, date)
        }.sorted { $0.1 < $1.1 }.map { $0.0 }
        var maxWinStreak = 0
        var maxLossStreak = 0
        var run = 0
        for trade in ordered {
            if trade.status == .breakeven { continue }
            let direction = trade.status == .win ? 1 : -1
            run = (run > 0 && direction > 0) || (run < 0 && direction < 0) ? run + direction : direction
            if run > maxWinStreak { maxWinStreak = run }
            if -run > maxLossStreak { maxLossStreak = -run }
        }
        
        let dd = drawdown(curve: curvePoints, initialBalance: initialBalance)
        
        let avgWin: Decimal? = !wins.isEmpty ? (wins.reduce(Decimal.zero) { $0 + $1.netPnl } / Decimal(wins.count)) : nil
        let avgLoss: Decimal? = !losses.isEmpty ? (losses.reduce(Decimal.zero) { $0 + abs($1.netPnl) } / Decimal(losses.count)) : nil
        
        let avgWinLossRatio: Double?
        if let avgW = avgWin, let avgL = avgLoss, avgL > 0 {
            avgWinLossRatio = NSDecimalNumber(decimal: avgW).doubleValue / NSDecimalNumber(decimal: avgL).doubleValue
        } else {
            avgWinLossRatio = nil
        }
        
        let profitFactor: Double?
        let profitFactorIsInfinite: Bool
        if !closed.isEmpty {
            if grossLoss > 0 {
                profitFactor = NSDecimalNumber(decimal: grossProfit).doubleValue / NSDecimalNumber(decimal: grossLoss).doubleValue
                profitFactorIsInfinite = false
            } else if grossProfit > 0 {
                profitFactor = nil
                profitFactorIsInfinite = true
            } else {
                profitFactor = nil
                profitFactorIsInfinite = false
            }
        } else {
            profitFactor = nil
            profitFactorIsInfinite = false
        }
        
        let expectancy: Decimal? = !closed.isEmpty ? (netPnl / Decimal(closed.count)) : nil
        let largestWin = wins.reduce(Decimal.zero) { max($0, $1.netPnl) }
        let largestLoss = losses.reduce(Decimal.zero) { min($0, $1.netPnl) }
        
        let recoveryFactor: Double? = dd.maxDrawdown > 0 ? (NSDecimalNumber(decimal: netPnl).doubleValue / NSDecimalNumber(decimal: dd.maxDrawdown).doubleValue) : nil
        
        let totalDayProfit = dayStatsList.filter { $0.netPnl > 0 }.reduce(Decimal.zero) { $0 + $1.netPnl }
        let maxSingleDayProfit = dayStatsList.filter { $0.netPnl > 0 }.reduce(Decimal.zero) { max($0, $1.netPnl) }
        let profitConcentration: Double? = totalDayProfit > 0 ? (NSDecimalNumber(decimal: maxSingleDayProfit).doubleValue / NSDecimalNumber(decimal: totalDayProfit).doubleValue) : nil
        
        let totalDuration = closed.compactMap { $0.durationMs }.reduce(Int64(0), +)
        let closedWithDuration = closed.compactMap { $0.durationMs }.count
        let avgDurationMs: Int64? = closedWithDuration > 0 ? (totalDuration / Int64(closedWithDuration)) : nil
        
        let rMultiples = trades.compactMap { TradeAnalysisEngine.tradeR(trade: $0) }
        let avgRealizedR: Double? = !rMultiples.isEmpty ? (rMultiples.reduce(0.0, +) / Double(rMultiples.count)) : nil
        
        return TradeMetrics(
            totalTrades: trades.count,
            closedTrades: closed.count,
            openTrades: trades.count - closed.count,
            wins: wins.count,
            losses: losses.count,
            breakevens: breakevens.count,
            netPnl: netPnl,
            grossPnl: totalGross,
            fees: totalFees,
            winRate: winRate,
            dayWinRate: dayWinRate,
            tradingDays: dayStatsList.count,
            profitFactor: profitFactor,
            profitFactorIsInfinite: profitFactorIsInfinite,
            avgWin: avgWin,
            avgLoss: avgLoss,
            avgWinLossRatio: avgWinLossRatio,
            expectancy: expectancy,
            largestWin: largestWin,
            largestLoss: largestLoss,
            maxWinStreak: maxWinStreak,
            maxLossStreak: maxLossStreak,
            currentStreak: run,
            totalVolume: trades.reduce(Decimal.zero) { $0 + $1.quantity },
            avgDurationMs: avgDurationMs,
            maxDrawdown: dd.maxDrawdown,
            maxDrawdownPct: dd.maxDrawdownPct,
            recoveryFactor: recoveryFactor,
            profitConcentration: profitConcentration,
            avgRealizedR: avgRealizedR,
            tradesWithRisk: rMultiples.count
        )
    }
    
    /// Point-in-time relative drawdown for an underwater chart.
/// Ported 1:1 from `packages/core/src/equity.ts` `relativeDrawdownCurve`.
    public static func relativeDrawdownCurve(curve: [EquityPoint], initialBalance: Decimal = 0) -> [(timestamp: Date, dateString: String, drawdownPct: Double?)] {
        var peak: Decimal = 0
        return curve.map { point in
            if point.cumNetPnl > peak { peak = point.cumNetPnl }
            let base = initialBalance + peak
            let dd = peak - point.cumNetPnl
            let pct: Double? = base > 0 ? (NSDecimalNumber(decimal: dd).doubleValue / NSDecimalNumber(decimal: base).doubleValue) : nil
            return (timestamp: point.timestamp, dateString: point.dateString, drawdownPct: pct)
        }
    }
}
