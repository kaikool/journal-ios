import Foundation

// MARK: - Captured AI Account & Intraday Session Summary
// Immutable snapshot of intraday trading performance, prop firm rules, and behavioral leaks
public struct AIAccountSessionSummary: Sendable {
    public let todayDateStr: String
    public let totalTradesToday: Int
    public let openTradesToday: Int
    public let closedTradesToday: Int
    public let netPnlToday: Decimal
    public let winsToday: Int
    public let lossesToday: Int
    public let breakevensToday: Int
    public let currentStreakToday: Int // Positive for wins, negative for losses
    public let symbolsToday: [String]
    
    // Explicit Chronological Separation (Today vs Yesterday vs Weekly/Monthly)
    public let currentTimestampStr: String
    public let yesterdayDateStr: String
    public let totalTradesYesterday: Int
    public let closedTradesYesterday: Int
    public let netPnlYesterday: Decimal
    public let winsYesterday: Int
    public let lossesYesterday: Int
    public let weekToDateNetPnl: Decimal
    public let weekToDateTradesCount: Int
    public let monthToDateNetPnl: Decimal
    public let monthToDateTradesCount: Int
    
    // Prop Firm / Account Risk Rules
    public let accountName: String?
    public let propFirmName: String?
    public let accountCurrency: String
    public let balance: Decimal?
    public let equity: Decimal?
    public let dailyLossLimitUsd: Decimal?
    public let maxLossLimitUsd: Decimal?
    public let dailyLossBufferRemainingUsd: Decimal?
    public let stepOrPhaseName: String?
    
    // Recent Behavioral Mistakes & Discipline (Last 14 Days)
    public let recentMistakeFrequencies: [(tag: String, count: Int)]
    public let playbookComplianceRate: Double?
    public let totalAssessedRules: Int
    
    // Overall Account Historical Edge
    public let overallWinRate: Double?
    public let overallProfitFactor: Double?
    public let overallExpectancy: Decimal?
    public let maxDrawdownPct: Double?
    
    public init(
        todayDateStr: String,
        totalTradesToday: Int,
        openTradesToday: Int,
        closedTradesToday: Int,
        netPnlToday: Decimal,
        winsToday: Int,
        lossesToday: Int,
        breakevensToday: Int,
        currentStreakToday: Int,
        symbolsToday: [String],
        currentTimestampStr: String = "",
        yesterdayDateStr: String = "",
        totalTradesYesterday: Int = 0,
        closedTradesYesterday: Int = 0,
        netPnlYesterday: Decimal = .zero,
        winsYesterday: Int = 0,
        lossesYesterday: Int = 0,
        weekToDateNetPnl: Decimal = .zero,
        weekToDateTradesCount: Int = 0,
        monthToDateNetPnl: Decimal = .zero,
        monthToDateTradesCount: Int = 0,
        accountName: String?,
        propFirmName: String?,
        accountCurrency: String,
        balance: Decimal?,
        equity: Decimal?,
        dailyLossLimitUsd: Decimal?,
        maxLossLimitUsd: Decimal?,
        dailyLossBufferRemainingUsd: Decimal?,
        stepOrPhaseName: String?,
        recentMistakeFrequencies: [(tag: String, count: Int)],
        playbookComplianceRate: Double?,
        totalAssessedRules: Int,
        overallWinRate: Double?,
        overallProfitFactor: Double?,
        overallExpectancy: Decimal?,
        maxDrawdownPct: Double?
    ) {
        self.todayDateStr = todayDateStr
        self.totalTradesToday = totalTradesToday
        self.openTradesToday = openTradesToday
        self.closedTradesToday = closedTradesToday
        self.netPnlToday = netPnlToday
        self.winsToday = winsToday
        self.lossesToday = lossesToday
        self.breakevensToday = breakevensToday
        self.currentStreakToday = currentStreakToday
        self.symbolsToday = symbolsToday
        self.currentTimestampStr = currentTimestampStr
        self.yesterdayDateStr = yesterdayDateStr
        self.totalTradesYesterday = totalTradesYesterday
        self.closedTradesYesterday = closedTradesYesterday
        self.netPnlYesterday = netPnlYesterday
        self.winsYesterday = winsYesterday
        self.lossesYesterday = lossesYesterday
        self.weekToDateNetPnl = weekToDateNetPnl
        self.weekToDateTradesCount = weekToDateTradesCount
        self.monthToDateNetPnl = monthToDateNetPnl
        self.monthToDateTradesCount = monthToDateTradesCount
        self.accountName = accountName
        self.propFirmName = propFirmName
        self.accountCurrency = accountCurrency
        self.balance = balance
        self.equity = equity
        self.dailyLossLimitUsd = dailyLossLimitUsd
        self.maxLossLimitUsd = maxLossLimitUsd
        self.dailyLossBufferRemainingUsd = dailyLossBufferRemainingUsd
        self.stepOrPhaseName = stepOrPhaseName
        self.recentMistakeFrequencies = recentMistakeFrequencies
        self.playbookComplianceRate = playbookComplianceRate
        self.totalAssessedRules = totalAssessedRules
        self.overallWinRate = overallWinRate
        self.overallProfitFactor = overallProfitFactor
        self.overallExpectancy = overallExpectancy
        self.maxDrawdownPct = maxDrawdownPct
    }
}
