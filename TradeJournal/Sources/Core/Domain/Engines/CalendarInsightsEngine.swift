import Foundation

public struct WeekdayPerformance: Equatable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let label: String
    public let days: [DayStats]
    public let trades: Int
    public let netPnl: Decimal
}

public struct DayTrendPoint: Equatable, Identifiable {
    public var id: String { date }
    public let date: String
    public let netPnl: Decimal
    public let average: Decimal?
}

public struct CalendarInsights: Equatable {
    public let days: [DayStats]
    public let trades: Int
    public let wins: Int
    public let losses: Int
    public let breakevens: Int
    public let netPnl: Decimal
    public let tradingDays: Int
    public let greenDays: Int
    public let redDays: Int
    public let flatDays: Int
    public let winRate: Double?
    public let profitableDayRate: Double?
    public let avgDailyPnl: Decimal?
    public let avgGreenDay: Decimal?
    public let avgRedDay: Decimal?
    public let bestDay: DayStats?
    public let worstDay: DayStats?
    public let weekdays: [WeekdayPerformance]
    public let mostProfitableWeekday: WeekdayPerformance?
    public let trend: [DayTrendPoint]
}

/// Ported 1:1 from `apps/web/src/lib/calendar-insights.ts`.
public enum CalendarInsightsEngine {
    
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }()

    public static func closingWeekday(_ dateString: String) -> Int {
        guard let d = isoDayFormatter.date(from: dateString) else { return 0 }
        return (utcCalendar.component(.weekday, from: d) - 1) // Sunday = 0
    }
    
    public static func calendarInsights(calendar: CalendarMonth) -> CalendarInsights {
        let days = calendar.weeks
            .flatMap { $0.days }
            .compactMap { $0 }
            .filter { $0.trades > 0 }
            .sorted { $0.date < $1.date }
        
        let green = days.filter { $0.netPnl > 0 }
        let red = days.filter { $0.netPnl < 0 }
        let trades = days.reduce(0) { $0 + $1.trades }
        let wins = days.reduce(0) { $0 + $1.wins }
        let losses = days.reduce(0) { $0 + $1.losses }
        let breakevens = days.reduce(0) { $0 + $1.breakevens }
        let netPnl = days.reduce(Decimal(0)) { $0 + $1.netPnl }
        
        let weekdayLabels = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]
        
        var daysByWeekday: [Int: [DayStats]] = [:]
        for day in days {
            let weekday = closingWeekday(day.date)
            daysByWeekday[weekday, default: []].append(day)
        }
        
        let weekdays: [WeekdayPerformance] = weekdayLabels.enumerated().map { index, label in
            let matching = daysByWeekday[index] ?? []
            return WeekdayPerformance(
                index: index,
                label: label,
                days: matching,
                trades: matching.reduce(0) { $0 + $1.trades },
                netPnl: matching.reduce(Decimal(0)) { $0 + $1.netPnl }
            )
        }
        
        let profitableWeekdays = weekdays
            .filter { $0.netPnl > 0 }
            .sorted { $0.netPnl > $1.netPnl || ($0.netPnl == $1.netPnl && $0.index < $1.index) }
        
        let winRate = trades > 0 ? Double(wins) / Double(trades) : nil
        let profitableDayRate = !days.isEmpty ? Double(green.count) / Double(days.count) : nil
        let avgDailyPnl = !days.isEmpty ? netPnl / Decimal(days.count) : nil
        let avgGreenDay = !green.isEmpty ? green.reduce(Decimal(0)) { $0 + $1.netPnl } / Decimal(green.count) : nil
        let avgRedDay = !red.isEmpty ? red.reduce(Decimal(0)) { $0 + $1.netPnl } / Decimal(red.count) : nil
        
        let bestDay = days.reduce(nil as DayStats?) { best, day in
            guard let b = best else { return day }
            return day.netPnl > b.netPnl ? day : b
        }
        let worstDay = days.reduce(nil as DayStats?) { worst, day in
            guard let w = worst else { return day }
            return day.netPnl < w.netPnl ? day : w
        }
        
        let trend: [DayTrendPoint] = days.enumerated().map { index, day in
            let average: Decimal?
            if index < 4 {
                average = nil
            } else {
                let slice = days[(index - 4)...index]
                let sum = slice.reduce(Decimal(0)) { $0 + $1.netPnl }
                average = sum / 5
            }
            return DayTrendPoint(date: day.date, netPnl: day.netPnl, average: average)
        }
        
        return CalendarInsights(
            days: days,
            trades: trades,
            wins: wins,
            losses: losses,
            breakevens: breakevens,
            netPnl: netPnl,
            tradingDays: days.count,
            greenDays: green.count,
            redDays: red.count,
            flatDays: days.count - green.count - red.count,
            winRate: winRate,
            profitableDayRate: profitableDayRate,
            avgDailyPnl: avgDailyPnl,
            avgGreenDay: avgGreenDay,
            avgRedDay: avgRedDay,
            bestDay: bestDay,
            worstDay: worstDay,
            weekdays: weekdays,
            mostProfitableWeekday: profitableWeekdays.first,
            trend: trend
        )
    }
}
