import Foundation

// MARK: - Centralized AI Context Provider
// Aggregates intraday session trades, prop firm drawdown metrics, and 14-day mistake frequencies
public enum AIAccountContextProvider {
    
    /// Captures the complete trading session, prop firm risk limits, and behavioral history
    @MainActor
    public static func captureContext(
        targetAccountId: String? = nil,
        dataStore: TradeDataStore = .shared
    ) -> AIAccountSessionSummary {
        let todayStr = JournalIds.todayDateString()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let activeAccId: String = {
            if let t = targetAccountId, !t.isEmpty, t != "all", t != "default-acc" {
                return t
            }
            if !dataStore.selectedAccountId.isEmpty, dataStore.selectedAccountId != "all", dataStore.selectedAccountId != "default-acc" {
                return dataStore.selectedAccountId
            }
            return dataStore.mostRecentActiveAccount?.id ?? dataStore.visibleAccounts.first?.id ?? dataStore.accounts.first?.id ?? ""
        }()
        
        // 1. Account Filtering
        let accountTrades: [Trade] = {
            if activeAccId.isEmpty || activeAccId == "default-acc" || activeAccId == "all" {
                return dataStore.trades
            } else {
                return dataStore.trades.filter { TradeDataStore.isSameAccountId($0.accountId, activeAccId) }
            }
        }()
        
        let accountObj = dataStore.accounts.first(where: { TradeDataStore.isSameAccountId($0.id, activeAccId) })
        let propObj = dataStore.propAccounts.first(where: {
            TradeDataStore.isSameAccountId($0.id, activeAccId) ||
            ($0.journalAccountId.map { TradeDataStore.isSameAccountId($0, activeAccId) } ?? false)
        })
        
        // 2. Today's Intraday Trades & Temporal Breakdown
        let todayTrades = accountTrades.filter { trade in
            dateFormatter.string(from: trade.openedAt) == todayStr
        }
        
        let closedToday = todayTrades.filter { $0.status != .open || $0.closedAt != nil }
        let openToday = todayTrades.filter { $0.status == .open && $0.closedAt == nil }
        
        let netPnlToday = closedToday.reduce(Decimal.zero) { $0 + $1.netPnl }
        let winsToday = closedToday.filter { $0.netPnl > 0 }.count
        let lossesToday = closedToday.filter { $0.netPnl < 0 }.count
        let beToday = closedToday.filter { $0.netPnl == 0 }.count
        
        // Symbols traded today
        let symbolsToday = Array(Set(todayTrades.map { $0.symbol })).sorted()
        
        // Yesterday's Trades
        let calendar = Calendar.current
        let now = Date()
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayStr = dateFormatter.string(from: yesterdayDate)
        let yesterdayTrades = accountTrades.filter { trade in
            dateFormatter.string(from: trade.openedAt) == yesterdayStr
        }
        let closedYesterday = yesterdayTrades.filter { $0.status != .open || $0.closedAt != nil }
        let netPnlYesterday = closedYesterday.reduce(Decimal.zero) { $0 + $1.netPnl }
        let winsYesterday = closedYesterday.filter { $0.netPnl > 0 }.count
        let lossesYesterday = closedYesterday.filter { $0.netPnl < 0 }.count
        
        // Week-to-Date & Month-to-Date
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let wtdTrades = accountTrades.filter { $0.openedAt >= startOfWeek && ($0.status != .open || $0.closedAt != nil) }
        let netPnlWtd = wtdTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
        
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let mtdTrades = accountTrades.filter { $0.openedAt >= startOfMonth && ($0.status != .open || $0.closedAt != nil) }
        let netPnlMtd = mtdTrades.reduce(Decimal.zero) { $0 + $1.netPnl }
        
        let tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
        let currentTimestampStr = tsFormatter.string(from: now)
        
        // Intraday Streak
        let sortedClosedToday = closedToday.sorted { ($0.closedAt ?? $0.openedAt) < ($1.closedAt ?? $1.openedAt) }
        var streakToday = 0
        if let lastTrade = sortedClosedToday.last {
            let isWin = lastTrade.netPnl > 0
            for t in sortedClosedToday.reversed() {
                if (t.netPnl > 0) == isWin && t.netPnl != 0 {
                    streakToday += (isWin ? 1 : -1)
                } else {
                    break
                }
            }
        }
        
        // 3. Prop Firm Risk & Capital Preservation Rules
        let isExnessAccount = (accountObj?.broker.lowercased() == "exness") ||
                              activeAccId.contains("exness") ||
                              (ExnessService.shared.isConnected && (activeAccId.isEmpty || activeAccId == "default-acc" || activeAccId == "all"))
        
        let currency: String = {
            if isExnessAccount && !ExnessService.shared.currency.isEmpty {
                return ExnessService.shared.currency
            }
            return accountObj?.currency ?? propObj?.currency ?? dataStore.currencyConversion.reportingCurrency
        }()
        
        let totalClosedNetPnl = accountTrades.filter { $0.status != .open || $0.closedAt != nil }.reduce(Decimal.zero) { $0 + $1.netPnl }
        
        let balance: Decimal? = {
            // Priority 1: Direct live balance from ExnessService if connected
            if isExnessAccount && ExnessService.shared.balance > 0 {
                return ExnessService.shared.balance
            }
            
            if let prop = propObj {
                if let minor = prop.balanceMinor ?? prop.sizeMinor {
                    return Decimal(minor) / 100
                }
            }
            
            if let acc = accountObj {
                // If it's a synced broker account (e.g. Exness, cTrader), its stored balance is already the live net balance from the broker.
                // Do NOT add historical closed trades net PnL to an already-current synced balance!
                if acc.kind == .sync || acc.broker.lowercased() == "exness" {
                    if acc.broker.lowercased() == "exness" && ExnessService.shared.balance > 0 {
                        return ExnessService.shared.balance
                    }
                    return acc.initialBalance
                }
                return acc.initialBalance + totalClosedNetPnl
            }
            
            let activeAcc = dataStore.mostRecentActiveAccount ?? dataStore.visibleAccounts.first ?? dataStore.accounts.first
            if let acc = activeAcc {
                if acc.broker.lowercased() == "exness" && ExnessService.shared.balance > 0 {
                    return ExnessService.shared.balance
                }
                if acc.kind == .sync || acc.broker.lowercased() == "exness" {
                    return acc.initialBalance
                }
                let accPnl = dataStore.trades.filter { TradeDataStore.isSameAccountId($0.accountId, acc.id) && ($0.status != .open || $0.closedAt != nil) }.reduce(Decimal.zero) { $0 + $1.netPnl }
                return acc.initialBalance + accPnl
            }
            
            if !dataStore.accounts.isEmpty {
                let total = dataStore.visibleAccounts.reduce(Decimal.zero) { total, account in
                    let base = (account.kind == .sync || account.broker.lowercased() == "exness")
                        ? account.initialBalance
                        : (account.initialBalance + dataStore.trades.filter { TradeDataStore.isSameAccountId($0.accountId, account.id) && ($0.status != .open || $0.closedAt != nil) }.reduce(Decimal.zero) { $0 + $1.netPnl })
                    return total + dataStore.currencyConversion.convertedBalance(base, currency: account.currency)
                }
                return total
            }
            
            // Fallback to ExnessService directly if connected
            if ExnessService.shared.isConnected && ExnessService.shared.balance > 0 {
                return ExnessService.shared.balance
            }
            
            return nil
        }()
        
        let equity: Decimal? = {
            if isExnessAccount && ExnessService.shared.equity > 0 {
                return ExnessService.shared.equity
            }
            if let prop = propObj {
                if let minor = prop.equityMinor ?? prop.balanceMinor ?? prop.sizeMinor {
                    return Decimal(minor) / 100
                }
            }
            return balance
        }()
        
        var dailyLossLimitUsd: Decimal? = nil
        var maxLossLimitUsd: Decimal? = nil
        var bufferRemaining: Decimal? = nil
        
        if let prop = propObj {
            if let dMinor = prop.maxDailyLossMinor, dMinor > 0 {
                let dLimitUsd = Decimal(dMinor) / 100
                dailyLossLimitUsd = dLimitUsd
                if netPnlToday < 0 {
                    bufferRemaining = max(Decimal.zero, dLimitUsd - abs(netPnlToday))
                } else {
                    bufferRemaining = dLimitUsd + netPnlToday
                }
            }
            if let mMinor = prop.maxLossMinor, mMinor > 0 {
                maxLossLimitUsd = Decimal(mMinor) / 100
            }
        }
        
        // 4. Behavioral Mistakes & Psychological Leaks (Past 14 Days)
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date.distantPast
        let recentTrades = accountTrades.filter { $0.openedAt >= fourteenDaysAgo }
        
        var mistakeCounts: [String: Int] = [:]
        for t in recentTrades {
            for m in t.mistakes {
                let clean = m.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    mistakeCounts[clean, default: 0] += 1
                }
            }
        }
        let sortedMistakes: [(tag: String, count: Int)] = mistakeCounts
            .map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
        
        // Playbook Rule Compliance
        let recentTradeKeys = Set(recentTrades.map { $0.key })
        let relevantAssessments = dataStore.playbookAssessments.filter { recentTradeKeys.contains($0.tradeKey) }
        let followedCount = relevantAssessments.filter { $0.followed }.count
        let complianceRate: Double? = relevantAssessments.isEmpty ? nil : (Double(followedCount) / Double(relevantAssessments.count) * 100.0)
        
        // 5. Account Overall Historical Edge
        let metrics = FinancialMetricsEngine.computeMetrics(trades: accountTrades)
        let winRate = metrics.winRate.map { $0 * 100.0 }
        let profitFactor = metrics.profitFactor
        let expectancy = metrics.expectancy
        let maxDrawdownPct = metrics.maxDrawdownPct.map { $0 * 100.0 }
        
        return AIAccountSessionSummary(
            todayDateStr: todayStr,
            totalTradesToday: todayTrades.count,
            openTradesToday: openToday.count,
            closedTradesToday: closedToday.count,
            netPnlToday: netPnlToday,
            winsToday: winsToday,
            lossesToday: lossesToday,
            breakevensToday: beToday,
            currentStreakToday: streakToday,
            symbolsToday: symbolsToday,
            currentTimestampStr: currentTimestampStr,
            yesterdayDateStr: yesterdayStr,
            totalTradesYesterday: yesterdayTrades.count,
            closedTradesYesterday: closedYesterday.count,
            netPnlYesterday: netPnlYesterday,
            winsYesterday: winsYesterday,
            lossesYesterday: lossesYesterday,
            weekToDateNetPnl: netPnlWtd,
            weekToDateTradesCount: wtdTrades.count,
            monthToDateNetPnl: netPnlMtd,
            monthToDateTradesCount: mtdTrades.count,
            accountName: accountObj?.name ?? propObj?.name ?? (isExnessAccount && ExnessService.shared.isConnected ? (!ExnessService.shared.accountName.isEmpty ? ExnessService.shared.accountName : "Exness (\(ExnessService.shared.accountId))") : nil),
            propFirmName: propObj?.firm,
            accountCurrency: currency,
            balance: balance,
            equity: equity,
            dailyLossLimitUsd: dailyLossLimitUsd,
            maxLossLimitUsd: maxLossLimitUsd,
            dailyLossBufferRemainingUsd: bufferRemaining,
            stepOrPhaseName: propObj?.currentStepName,
            recentMistakeFrequencies: sortedMistakes,
            playbookComplianceRate: complianceRate,
            totalAssessedRules: relevantAssessments.count,
            overallWinRate: winRate,
            overallProfitFactor: profitFactor,
            overallExpectancy: expectancy,
            maxDrawdownPct: maxDrawdownPct
        )
    }
    
    /// Formats the session summary cleanly into institutional prompt text
    public static func formatContextForPrompt(_ summary: AIAccountSessionSummary, isVi: Bool) -> String {
        let pnlVal = NSDecimalNumber(decimal: summary.netPnlToday).doubleValue
        let pnlStr = (summary.netPnlToday >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlVal))
        
        let pnlYesterdayVal = NSDecimalNumber(decimal: summary.netPnlYesterday).doubleValue
        let pnlYesterdayStr = (summary.netPnlYesterday >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlYesterdayVal))
        
        let pnlWtdVal = NSDecimalNumber(decimal: summary.weekToDateNetPnl).doubleValue
        let pnlWtdStr = (summary.weekToDateNetPnl >= 0 ? "+$" : "-$") + String(format: "%.2f", abs(pnlWtdVal))
        
        let symbolsStr = summary.symbolsToday.isEmpty ? "None" : summary.symbolsToday.joined(separator: ", ")
        
        let streakStr: String = {
            if summary.currentStreakToday > 0 {
                return "+\(summary.currentStreakToday) \(isVi ? "thắng liên tiếp" : "wins in a row")"
            } else if summary.currentStreakToday < 0 {
                return "\(summary.currentStreakToday) \(isVi ? "thua liên tiếp" : "losses in a row")"
            }
            return isVi ? "Chưa có chuỗi" : "None"
        }()
        
        let mistakesStr: String = {
            if summary.recentMistakeFrequencies.isEmpty {
                return isVi ? "Không ghi nhận vi phạm kỷ luật trong 14 ngày" : "Zero logged violations in past 14 days"
            }
            return summary.recentMistakeFrequencies.prefix(5)
                .map { "\($0.tag) (\($0.count)x)" }
                .joined(separator: ", ")
        }()
        
        let complianceStr: String = {
            guard let rate = summary.playbookComplianceRate else {
                return isVi ? "Chưa có đánh giá Playbook" : "No playbook evaluations"
            }
            return String(format: "%.1f%% (%d/%d quy tắc tuân thủ)", rate, Int(Double(summary.totalAssessedRules) * rate / 100.0), summary.totalAssessedRules)
        }()
        
        let propRiskBlock: String = {
            guard let dLimit = summary.dailyLossLimitUsd else { return "" }
            let dLimitVal = NSDecimalNumber(decimal: dLimit).doubleValue
            let bufferVal = NSDecimalNumber(decimal: summary.dailyLossBufferRemainingUsd ?? dLimit).doubleValue
            let firm = summary.propFirmName ?? "Prop Firm"
            
            if isVi {
                return """
                HẠN MỨC QUỸ & QUẢN TRỊ RỦI RO (\(firm)):
                - Hạn mức lỗ tối đa trong ngày (Daily Loss Limit): $\(String(format: "%.2f", dLimitVal))
                - Khoảng đệm an toàn còn lại hôm nay: $\(String(format: "%.2f", bufferVal)) \(bufferVal < (dLimitVal * 0.3) ? "⚠️ NGUY HIỂM: SẮP CHẠM TRẦN LỖ!" : "")
                - Giai đoạn / Step: \(summary.stepOrPhaseName ?? "Phase 1")
                """
            } else {
                return """
                PROP FIRM CAPITAL PRESERVATION RULES (\(firm)):
                - Daily Loss Limit: $\(String(format: "%.2f", dLimitVal))
                - Remaining Daily Safety Buffer: $\(String(format: "%.2f", bufferVal)) \(bufferVal < (dLimitVal * 0.3) ? "⚠️ DANGER: APPROACHING DRAWDOWN LIMIT!" : "")
                - Phase / Step: \(summary.stepOrPhaseName ?? "Phase 1")
                """
            }
        }()
        
        let edgeBlock: String = {
            let wr = summary.overallWinRate.map { String(format: "%.1f%%", $0) } ?? "N/A"
            let pf = summary.overallProfitFactor.map { String(format: "%.2f", $0) } ?? "N/A"
            let exp = summary.overallExpectancy.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "N/A"
            
            if isVi {
                return "- Lợi thế lịch sử tài khoản: Win Rate \(wr) | Profit Factor \(pf) | Kỳ vọng toán học \(exp)/lệnh"
            } else {
                return "- Account Historical Edge: Win Rate \(wr) | Profit Factor \(pf) | Expectancy \(exp)/trade"
            }
        }()
        
        let balanceBlockVi: String = {
            if let bal = summary.balance {
                let formattedBal = Formatters.formatCurrency(bal, currency: summary.accountCurrency)
                let eqStr = summary.equity != nil ? " | Vốn ròng (Equity): \(Formatters.formatCurrency(summary.equity!, currency: summary.accountCurrency))" : ""
                let accNameStr = summary.accountName != nil ? " (Tài khoản: \(summary.accountName!))" : ""
                return "- SỐ DƯ TÀI KHOẢN THỰC TẾ HIỆN TẠI\(accNameStr): \(formattedBal)\(eqStr)\n"
            }
            return ""
        }()
        
        let balanceBlockEn: String = {
            if let bal = summary.balance {
                let formattedBal = Formatters.formatCurrency(bal, currency: summary.accountCurrency)
                let eqStr = summary.equity != nil ? " | Equity: \(Formatters.formatCurrency(summary.equity!, currency: summary.accountCurrency))" : ""
                let accNameStr = summary.accountName != nil ? " (Account: \(summary.accountName!))" : ""
                return "- CURRENT AUTHORITATIVE ACCOUNT BALANCE\(accNameStr): \(formattedBal)\(eqStr)\n"
            }
            return ""
        }()
        
        if isVi {
            return """
            BỐI CẢNH HIỆN TẠI & PHÂN ĐỊNH MỐC THỜI GIAN THỰC TẾ:
            \(balanceBlockVi)- Thời gian hệ thống hiện tại: \(summary.currentTimestampStr.isEmpty ? "Hôm nay" : summary.currentTimestampStr)
            - HÔM NAY (NGÀY \(summary.todayDateStr)): \(summary.totalTradesToday) lệnh (Đang mở: \(summary.openTradesToday) | Đã đóng: \(summary.closedTradesToday)) | Net P&L: \(pnlStr) (\(summary.winsToday) Thắng - \(summary.lossesToday) Thua) | Chuỗi: \(streakStr)
            - HÔM QUA (NGÀY \(summary.yesterdayDateStr)): \(summary.totalTradesYesterday) lệnh (\(summary.winsYesterday) Thắng - \(summary.lossesYesterday) Thua) | Net P&L Hôm qua: \(pnlYesterdayStr)
            - TUẦN NÀY (WTD): \(summary.weekToDateTradesCount) lệnh | Net P&L Tuần này: \(pnlWtdStr)
            - Cặp tiền giao dịch hôm nay: \(symbolsStr)
            \(edgeBlock)
            
            LỖ HỔNG TÂM LÝ & KỶ LUẬT 14 NGÀY QUA:
            - Các lỗi vi phạm xuất hiện nhiều nhất: \(mistakesStr)
            - Tỷ lệ tuân thủ Playbook: \(complianceStr)
            
            \(propRiskBlock.isEmpty ? "" : propRiskBlock + "\n")
            """
        } else {
            return """
            CHRONOLOGICAL ACCOUNT CONTEXT & TIMEFRAME SEPARATION:
            \(balanceBlockEn)- Current System Timestamp: \(summary.currentTimestampStr.isEmpty ? "Now" : summary.currentTimestampStr)
            - TODAY (DATE \(summary.todayDateStr)): \(summary.totalTradesToday) trades (Open: \(summary.openTradesToday) | Closed: \(summary.closedTradesToday)) | Net P&L Today: \(pnlStr) (\(summary.winsToday)W - \(summary.lossesToday)L) | Streak: \(streakStr)
            - YESTERDAY (DATE \(summary.yesterdayDateStr)): \(summary.totalTradesYesterday) trades (\(summary.winsYesterday)W - \(summary.lossesYesterday)L) | Net P&L Yesterday: \(pnlYesterdayStr)
            - THIS WEEK (WTD): \(summary.weekToDateTradesCount) trades | Net P&L This Week: \(pnlWtdStr)
            - Traded Symbols Today: \(symbolsStr)
            \(edgeBlock)
            
            BEHAVIORAL LEAKS & DISCIPLINE AUDIT (PAST 14 DAYS):
            - Top Logged Violations: \(mistakesStr)
            - Playbook Compliance Rate: \(complianceStr)
            
            \(propRiskBlock.isEmpty ? "" : propRiskBlock + "\n")
            """
        }
    }
}
