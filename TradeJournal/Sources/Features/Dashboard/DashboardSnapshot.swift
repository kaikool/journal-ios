import Foundation

// MARK: - Dashboard Snapshot & Caching Engine
public struct DashboardSnapshot {
    public let metrics: TradeMetrics
    public let curve: [EquityPoint]
    public let days: [DayStats]
    public let edgeResult: EdgeScore
    public let chartEquityPoints: [EquityPointItem]
    public let hourlyStats: [BucketStats]
    public let weekDelta: Decimal?
    public let bestDay: DayStats?
    public let worstDay: DayStats?
    public let daysWithTradesMap: [String: DayStats]
    public let currentMonthStats: (tradingDays: Int, winningDays: Int, monthPnl: Decimal)
    
    public init(
        metrics: TradeMetrics,
        curve: [EquityPoint],
        days: [DayStats],
        edgeResult: EdgeScore,
        chartEquityPoints: [EquityPointItem],
        hourlyStats: [BucketStats],
        weekDelta: Decimal?,
        bestDay: DayStats?,
        worstDay: DayStats?,
        daysWithTradesMap: [String: DayStats],
        currentMonthStats: (tradingDays: Int, winningDays: Int, monthPnl: Decimal)
    ) {
        self.metrics = metrics
        self.curve = curve
        self.days = days
        self.edgeResult = edgeResult
        self.chartEquityPoints = chartEquityPoints
        self.hourlyStats = hourlyStats
        self.weekDelta = weekDelta
        self.bestDay = bestDay
        self.worstDay = worstDay
        self.daysWithTradesMap = daysWithTradesMap
        self.currentMonthStats = currentMonthStats
    }
}

@MainActor
final class DashboardCache {
    static let shared = DashboardCache()
    var lastKey: String = ""
    var lastSnapshot: DashboardSnapshot? = nil
    var lastScopedKey: String = ""
    var lastScopedTrades: [Trade] = []
    var lastCurrencyGroupsKey: String = ""
    var lastCurrencyGroups: [(currency: String, metrics: TradeMetrics, balance: Decimal)] = []
    var lastCalendarWeeksKey: String = ""
    var lastCalendarWeeks: [[Date?]] = []
    
    private init() {}
}
