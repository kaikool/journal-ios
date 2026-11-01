import SwiftUI

// MARK: - Dashboard Activity, Time & Calendar Widgets (8: Calendar, 9: Activity, 11: Streaks, 13: Duration, 15: Time Perf)
extension DashboardView {
    internal func widget8Calendar(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(monthName)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    AppLinkButton("Full calendar") {
                        env.selectedTab = .calendar
                    }
                }
                
                // 8-column header (Sun..Sat + Week)
                let cols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Wk"]
                HStack(spacing: 4) {
                    ForEach(cols, id: \.self) { c in
                        Text(c)
                            .font(AppTypography.badgeMicro)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: c == "Wk" ? .trailing : .center)
                    }
                }
                
                let isoFormatter: DateFormatter = {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    f.timeZone = env.currentTimeZone
                    return f
                }()
                
                // Calendar Weeks with Week Total Column
                VStack(spacing: 4) {
                    ForEach(0..<calendarWeeks.count, id: \.self) { wIndex in
                        let week = calendarWeeks[wIndex]
                        let weekDays = week.compactMap { $0 }
                        let weekPnl = weekDays.compactMap { d -> Decimal? in
                            let key = isoFormatter.string(from: d)
                            return snap.daysWithTradesMap[key]?.netPnl
                        }.reduce(Decimal.zero, +)
                        
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { dayIdx in
                                if let date = week[dayIdx] {
                                    let key = isoFormatter.string(from: date)
                                    let stats = snap.daysWithTradesMap[key]
                                    let dayNum = Calendar.current.component(.day, from: date)
                                    
                                    VStack(spacing: 1) {
                                        Text("\(dayNum)")
                                            .font(stats != nil ? AppTypography.numberMicro : AppTypography.disclaimer)
                                            .foregroundColor(stats != nil ? AppColors.primaryText : AppColors.secondaryText)
                                        
                                        if let s = stats {
                                            Text(s.netPnl >= 0 ? "+" : "-")
                                                .font(AppTypography.badgeMicro)
                                                .foregroundColor(s.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        }
                                    }
                                    .frame(height: 26)
                                    .frame(maxWidth: .infinity)
                                    .appSubCardStyle(cornerRadius: 6, padding: 0)
                                    .overlay(
                                        stats.map { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke($0.netPnl >= 0 ? AppColors.profit.opacity(0.24) : AppColors.loss.opacity(0.24), lineWidth: 0.5) }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        NativeHaptics.lightImpact()
                                        openCalendarDay(dateKey: key, stats: stats)
                                    }
                                } else {
                                    Color.clear
                                        .frame(height: 26)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            
                            // Week total column
                            let weekPnlText: String = {
                                if weekPnl == 0 { return "–" }
                                if abs(weekPnl) >= 1000 {
                                    return Formatters.compactCurrency(weekPnl, currency: env.currentCurrency)
                                } else {
                                    return Formatters.formatPnL(weekPnl, currency: env.currentCurrency)
                                }
                            }()
                            
                            Text(weekPnlText)
                                .font(AppTypography.number(9, weight: .semibold))
                                .foregroundColor(weekPnl > 0 ? AppColors.profit : (weekPnl < 0 ? AppColors.loss : AppColors.secondaryText))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.6))
                
                HStack {
                    Text("\(snap.currentMonthStats.tradingDays) trading days · \(snap.currentMonthStats.winningDays) green")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text("Month: \(Formatters.formatPnL(snap.currentMonthStats.monthPnl, currency: env.currentCurrency))")
                        .font(AppTypography.captionBold)
                        .monospacedDigit()
                        .foregroundColor(snap.currentMonthStats.monthPnl >= 0 ? AppColors.profit : AppColors.loss)
                }
            }
        }
    }
    
    // Widget 9: Activity (Recent trades & Open positions)
    @ViewBuilder

    internal func widget9Activity(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ACTIVITY")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                }
                
                // Apple HIG Sliding Pill Segmented Control
                AppSegmentedBar(
                    selection: $activityTab,
                    items: ["recent", "open"],
                    titleFor: { $0 == "recent" ? "Recent trades" : "Open positions" },
                    height: 32
                )
                
                if activityTab == "recent" {
                    let recent = Array(
                        scopedTrades
                            .filter { $0.status != .open }
                            .sorted { ($0.closedAt ?? $0.openedAt) > ($1.closedAt ?? $1.openedAt) }
                            .prefix(5)
                    )
                    if recent.isEmpty {
                        Text("No closed trades yet")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(recent) { t in
                                HStack(spacing: 8) {
                                    AppBadge(t.status.rawValue.uppercased(), color: Formatters.statusColor(t.status))
                                    
                                    AppBadge(
                                        t.direction == .long ? "BUY" : "SELL",
                                        variant: t.direction == .long ? .brand : .warning
                                    )
                                    
                                    Text(t.symbol)
                                        .font(AppTypography.rowTitle)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    let timeDateText: String = {
                                        let date = t.closedAt ?? t.openedAt
                                        let timeStr = Formatters.formatTime(date)
                                        let dateStr = Formatters.formatDate(date)
                                        return "\(timeStr) · \(dateStr)"
                                    }()
                                    
                                    Text(timeDateText)
                                        .font(AppTypography.captionMicro)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    
                                    AppMonetaryText(
                                        Formatters.formatPnL(t.netPnl, currency: env.currentCurrency),
                                        isPrivate: env.isPrivacyModeEnabled,
                                        font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                        color: t.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                    )
                                }
                                .padding(.vertical, 3)
                                
                                if t.id != recent.last?.id {
                                    Divider().background(AppColors.border.opacity(0.5))
                                }
                            }
                        }
                    }
                } else {
                    let openPos = dataStore.filteredTrades
                        .filter { $0.status == .open }
                        .sorted { $0.openedAt > $1.openedAt }
                    if openPos.isEmpty {
                        Text("Flat -- no open positions")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(openPos) { p in
                                HStack(spacing: 8) {
                                    AppBadge(p.direction.rawValue.uppercased(), color: p.direction == .long ? AppColors.profit : AppColors.loss)
                                    
                                    Text(p.symbol)
                                        .font(AppTypography.rowTitle)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text("\(p.quantity) @ \(Formatters.formatCurrency(p.avgEntry, currency: env.currentCurrency))")
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .padding(.vertical, 3)
                                
                                if p.id != openPos.last?.id {
                                    Divider().background(AppColors.border.opacity(0.5))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Widget 10: Max drawdown (TrendingDown)
    @ViewBuilder

    internal func widget11Streaks(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Streaks",
                    icon: "flame",
                    hint: "Current run of consecutive wins (W) or losses (L), with the best and worst runs."
                )
                
                Spacer(minLength: 4)
                
                Text(metrics.currentStreak > 0 ? "\(metrics.currentStreak)W" : (metrics.currentStreak < 0 ? "\(-metrics.currentStreak)L" : "–"))
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(metrics.currentStreak > 0 ? AppColors.profit : (metrics.currentStreak < 0 ? AppColors.loss : AppColors.primaryText))
                
                Text("best \(metrics.maxWinStreak)W · worst \(metrics.maxLossStreak)L")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 12: Expectancy / trade (Sigma)
    @ViewBuilder

    internal func widget13AvgDuration(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Avg duration",
                    icon: "timer",
                    hint: "Average time from first entry fill to final exit."
                )
                
                Spacer(minLength: 4)
                
                Text(Formatters.formatDuration(ms: metrics.avgDurationMs))
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                Text("winners vs losers in Reports")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 14: Best / worst day (Trophy)
    @ViewBuilder

    internal func widget15TradeTimePerformance(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Trade time performance",
                    icon: "clock",
                    hint: "Trades grouped by their opening hour. The upper chart shows net P&L; the lower chart shows trade count."
                )
                
                if snap.hourlyStats.isEmpty {
                    Text("No hourly trade data available.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    TimeHeatmapView(
                        hours: snap.hourlyStats,
                        currency: env.currentCurrency,
                        isPrivate: env.isPrivacyModeEnabled
                    )
                }
            }
        }
    }
    

    // MARK: - Day Selection Action
    
    internal func openCalendarDay(dateKey: String, stats: DayStats?) {
        NativeHaptics.lightImpact()
        let tradesForDay = dataStore.filteredTrades.filter {
            Formatters.isoDayString(from: $0.closedAt ?? $0.openedAt, timeZone: env.currentTimeZone) == dateKey
        }
        let note = dataStore.calendarNotes[dateKey] ?? JournalNote(date: dateKey)
        selectedDayContext = DayDetailContext(
            dateKey: dateKey,
            stats: stats,
            trades: tradesForDay,
            note: note
        )
    }
    
    internal func parseDate(from key: String) -> Date {
        Formatters.date(fromIsoDay: key, timeZone: env.currentTimeZone) ?? Date()
    }
}
