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
    public var profit: Decimal {
        grossPnl != nil ? max(0, grossPnl!) : (netPnl > 0 ? netPnl : 0)
    }
    public var loss: Decimal {
        grossPnl != nil ? max(0, -min(0, grossPnl!)) : (netPnl < 0 ? abs(netPnl) : 0)
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

public struct DayStats: Equatable {
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

/// Engine tính toán các chỉ số hiệu suất giao dịch và đường cong vốn.
/// Port 1:1 từ `packages/core/src/metrics.ts` và `equity.ts`.
public enum FinancialMetricsEngine {
    
    public static func computeOverview(trades: [Trade], timeZone: TimeZone = .current, initialBalance: Decimal = 0) -> (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        let curve = equityCurve(trades: trades)
        let days = dailyStats(trades: trades, timeZone: timeZone)
        let metrics = computeMetrics(trades: trades, curve: curve, days: days, initialBalance: initialBalance)
        return (metrics, curve, days)
    }
    
    /// Đường cong vốn (Equity Curve) tích lũy Net P&L theo từng trade đóng
    public static func equityCurve(trades: [Trade]) -> [EquityPoint] {
        let closedTrades = trades
            .filter { $0.status != .open && $0.closedAt != nil }
            .sorted {
                if $0.closedAt! != $1.closedAt! {
                    return $0.closedAt! < $1.closedAt!
                }
                return $0.key < $1.key
            }
        
        var cum: Decimal = 0
        let formatter = ISO8601DateFormatter()
        return closedTrades.map { trade in
            cum += trade.netPnl
            return EquityPoint(
                timestamp: trade.closedAt!,
                dateString: formatter.string(from: trade.closedAt!),
                cumNetPnl: cum
            )
        }
    }
    
    /// Thống kê kết quả theo từng ngày giao dịch (YYYY-MM-DD theo múi giờ)
    public static func dailyStats(trades: [Trade], timeZone: TimeZone = .current) -> [DayStats] {
        let closedTrades = trades
            .filter { $0.status != .open && $0.closedAt != nil }
            .sorted {
                if $0.closedAt! != $1.closedAt! {
                    return $0.closedAt! < $1.closedAt!
                }
                return $0.key < $1.key
            }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = timeZone
        
        var dayMap: [String: DayStats] = [:]
        
        for trade in closedTrades {
            let dateKey = dateFormatter.string(from: trade.closedAt!)
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
    
    /// Tính toán độ sụt giảm tối đa (Drawdown)
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
    
    /// Tính toán bộ chỉ số hiệu suất tổng thể (TradeMetrics)
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
        
        // Tính Streaks
        let ordered = closed.compactMap { $0.closedAt != nil ? $0 : nil }.sorted { $0.closedAt! < $1.closedAt! }
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
            avgRealizedR: nil,
            tradesWithRisk: 0
        )
    }
}
