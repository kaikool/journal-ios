import SwiftUI
import Charts

public struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedRange: JournalTimeRange = .all
    @State private var showEdgeScoreBreakdown: Bool = false
    @State private var showAIReflection: Bool = false
    @State private var showAddTradeSheet: Bool = false
    @State private var activityTab: String = "recent" // "recent" or "open"
    
    public init() {}
    
    private var scopedTrades: [Trade] {
        let baseTrades = dataStore.filteredTrades
        guard selectedRange != .all else { return baseTrades }
        
        let now = Date()
        let calendar = Calendar.current
        let cutoff: Date
        
        switch selectedRange {
        case .all:
            return baseTrades
        case .d7:
            cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .d30:
            cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .d90:
            cutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .ytd:
            let comps = calendar.dateComponents([.year], from: now)
            cutoff = calendar.date(from: comps) ?? now
        }
        
        return baseTrades.filter { $0.openedAt >= cutoff }
    }
    
    private var overview: (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        let initialBalance: Decimal = {
            if dataStore.selectedAccountId == "all" {
                return dataStore.visibleAccounts.reduce(Decimal.zero) { $0 + $1.initialBalance }
            }
            return dataStore.selectedAccount?.initialBalance ?? 0
        }()
        return FinancialMetricsEngine.computeOverview(
            trades: scopedTrades,
            timeZone: env.currentTimeZone,
            initialBalance: initialBalance
        )
    }
    
    private var edgeResult: EdgeScoreResult {
        EdgeScoreEngine.computeEdgeScore(metrics: overview.metrics)
    }
    
    private var chartEquityPoints: [EquityPointItem] {
        overview.curve.map { pt in
            EquityPointItem(
                date: pt.timestamp,
                dateKey: pt.dateString,
                netPnl: pt.cumNetPnl,
                cumulativePnl: pt.cumNetPnl,
                drawdown: Decimal.zero
            )
        }
    }
    
    private var hourlyStats: [BucketStats] {
        AggregateEngine.byHour(trades: scopedTrades, timeZone: env.currentTimeZone)
    }
    
    // Momentum: net P&L of the last 7 calendar days vs prior 7 days
    private var weekDelta: Decimal? {
        let now = Date().timeIntervalSince1970 * 1000
        var last: Decimal = 0
        var prior: Decimal = 0
        var lastDays = 0
        var priorDays = 0
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        for day in overview.days {
            if let date = formatter.date(from: day.date) {
                let ageDays = (now - (date.timeIntervalSince1970 * 1000)) / 86_400_000
                if ageDays <= 7 {
                    last += day.netPnl
                    lastDays += 1
                } else if ageDays <= 14 {
                    prior += day.netPnl
                    priorDays += 1
                }
            }
        }
        return (lastDays > 0 && priorDays > 0) ? (last - prior) : nil
    }
    
    private var bestDay: DayStats? {
        overview.days.max(by: { $0.netPnl < $1.netPnl })
    }
    
    private var worstDay: DayStats? {
        overview.days.min(by: { $0.netPnl < $1.netPnl })
    }
    
    // Current month calendar helper
    private var calendarMonthDays: [Date?] {
        let cal = Calendar.current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstDay) // 1 = Sunday
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: firstDay) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: Date())
    }
    
    private var daysWithTradesMap: [String: DayStats] {
        var map: [String: DayStats] = [:]
        for d in overview.days {
            map[d.date] = d
        }
        return map
    }
    
    private var currentMonthStats: (tradingDays: Int, winningDays: Int, monthPnl: Decimal) {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM"
        let prefix = isoFormatter.string(from: Date())
        
        let monthDays = overview.days.filter { $0.date.hasPrefix(prefix) }
        let tradingDays = monthDays.count
        let winningDays = monthDays.filter { $0.netPnl > 0 }.count
        let pnl = monthDays.reduce(Decimal.zero) { $0 + $1.netPnl }
        return (tradingDays, winningDays, pnl)
    }
    
    public var body: some View {
        let metrics = overview.metrics
        
        VStack(spacing: 0) {
            // FilterBar matching web filter-bar.tsx
            FilterBarView(
                title: "Dashboard",
                selectedRange: $selectedRange,
                showFilters: true
            ) {
                AppButton("Add trade", icon: "plus", style: .primary) {
                    showAddTradeSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    syncNotificationSection
                    
                    // SECTION 1: Summary Group (Widgets 0-4) matching web DashboardLayout
                    summaryGroupSection(metrics: metrics)
                    
                    // SECTION 2: Visuals Group (Widgets 5, 6, 7) matching web DashboardLayout
                    visualsGroupSection(metrics: metrics)
                    
                    // SECTION 3: Detail Group (Widgets 8, 9) matching web DashboardLayout
                    detailGroupSection
                    
                    // SECTION 4: Secondary Metrics Group (Widgets 10-14) matching web DashboardLayout
                    secondaryMetricsGrid(metrics: metrics)
                    
                    // SECTION 5: Full Width Performance (Widget 15) matching web DashboardLayout
                    tradeTimePerformanceCard
                }
                .padding(14)
            }
            .refreshable {
                if The5ersService.shared.isConfigured {
                    _ = try? await dataStore.syncWithThe5ers()
                } else if SupabaseService.shared.isConfigured {
                    await dataStore.syncWithSupabase()
                }
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showAIReflection) {
            AIReflectionView()
        }
        .sheet(isPresented: $showAddTradeSheet) {
            AddTradeSheet()
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var syncNotificationSection: some View {
        if let summary = dataStore.lastSyncSummary {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.profit)
                Text(summary)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                Button {
                    dataStore.lastSyncSummary = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.profit.opacity(0.12))
            .cornerRadius(6)
        }
        
        if let err = dataStore.lastSyncError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.loss)
                Text(err)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                Spacer()
                Button {
                    dataStore.lastSyncError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.loss.opacity(0.12))
            .cornerRadius(6)
        }
    }
    
    // MARK: - 1. Summary Group (Widgets 0, 1, 2, 3, 4)
    @ViewBuilder
    private func summaryGroupSection(metrics: TradeMetrics) -> some View {
        VStack(spacing: 10) {
            // Widget 0: Net P&L (full width on mobile)
            AppCard {
                VStack(alignment: .leading, spacing: 6) {
                    statHeader("Net P&L", icon: "dollarsign.circle")
                    
                    HStack(alignment: .firstTextBaseline) {
                        AppMonetaryText(
                            Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 28, weight: .semibold),
                            color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                        
                        Spacer()
                        
                        if let delta = weekDelta {
                            HStack(spacing: 3) {
                                Text(delta >= 0 ? "▲" : "▼")
                                    .font(.system(size: 9, weight: .bold))
                                Text(Formatters.formatCurrency(abs(delta), currency: env.currentCurrency))
                                    .font(AppTypography.captionBold)
                                Text("vs prior 7d")
                                    .font(AppTypography.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(delta >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                            .foregroundColor(delta >= 0 ? AppColors.profit : AppColors.loss)
                            .clipShape(Capsule())
                        }
                    }
                    
                    Text("\(metrics.closedTrades) closed trades · \(Formatters.formatCurrency(metrics.fees, currency: env.currentCurrency)) fees")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // 2x2 Grid for Widgets 1, 2, 3, 4
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Widget 1: Trade win %
                AppCard {
                    VStack(alignment: .leading, spacing: 6) {
                        statHeader("Trade win %", icon: "target")
                        
                        HStack(alignment: .center, spacing: 8) {
                            GaugeView(value: metrics.winRate, label: "Trade win rate", size: 84)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(metrics.wins) W")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(metrics.breakevens) BE")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("\(metrics.losses) L")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                }
                
                // Widget 2: Profit factor
                AppCard {
                    VStack(alignment: .leading, spacing: 6) {
                        statHeader("Profit factor", icon: "scalemass")
                        
                        Text(metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor != nil ? String(format: "%.2f", metrics.profitFactor!) : "–"))
                            .font(AppTypography.financialNumber(size: 24, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("gross profit ÷ gross loss")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                // Widget 3: Day win %
                AppCard {
                    VStack(alignment: .leading, spacing: 6) {
                        statHeader("Day win %", icon: "calendar.badge.clock")
                        
                        HStack(alignment: .center, spacing: 8) {
                            GaugeView(value: metrics.dayWinRate, label: "Day win rate", size: 84)
                            
                            Spacer()
                            
                            Text("\(metrics.tradingDays) days")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                // Widget 4: Avg win / loss
                AppCard {
                    VStack(alignment: .leading, spacing: 6) {
                        statHeader("Avg win / loss", icon: "arrow.up.arrow.down")
                        
                        Text(metrics.avgWinLossRatio != nil ? String(format: "%.2f", metrics.avgWinLossRatio!) : "–")
                            .font(AppTypography.financialNumber(size: 24, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                        
                        if let w = metrics.avgWin, let l = metrics.avgLoss, (w + l) > 0 {
                            let ratio = (w as NSDecimalNumber).doubleValue / ((w + l) as NSDecimalNumber).doubleValue
                            AppRatioBar(greenRatio: ratio)
                                .padding(.vertical, 2)
                        }
                        
                        HStack(spacing: 2) {
                            Text(Formatters.formatCurrency(metrics.avgWin, currency: env.currentCurrency))
                                .foregroundColor(AppColors.profit)
                            Text(" win · ")
                            Text(Formatters.formatCurrency(metrics.avgLoss, currency: env.currentCurrency))
                                .foregroundColor(AppColors.loss)
                            Text(" loss")
                        }
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    }
                }
            }
        }
    }
    
    // MARK: - 2. Visuals Group (Widgets 5, 6, 7)
    @ViewBuilder
    private func visualsGroupSection(metrics: TradeMetrics) -> some View {
        VStack(spacing: 10) {
            // Widget 5: Edge Score
            AppCard {
                VStack(spacing: 8) {
                    HStack {
                        statHeader("Edge Score", icon: "info.circle")
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Text(edgeResult.score != nil ? "\(Int(edgeResult.score!))" : "–")
                                .font(AppTypography.financialNumber(size: 20, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                            Text("/100")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            showEdgeScoreBreakdown.toggle()
                        }
                    }
                    
                    if metrics.closedTrades < 5 {
                        Text("Needs 5+ closed trades. A 0–100 score combining win rate, profit factor, average win/loss, drawdown, recovery, and consistency.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else if showEdgeScoreBreakdown, let b = edgeResult.breakdown {
                        Divider().background(AppColors.border)
                        
                        VStack(spacing: 5) {
                            scorePillarRow("Win rate", value: b.winRate, max: 15)
                            scorePillarRow("Profit factor", value: b.profitFactor, max: 25)
                            scorePillarRow("Avg win / loss", value: b.avgWinLoss, max: 20)
                            scorePillarRow("Drawdown", value: b.drawdown, max: 15)
                            scorePillarRow("Recovery", value: b.recovery, max: 10)
                            scorePillarRow("Consistency", value: b.consistency, max: 15)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            // Widget 6: Daily net cumulative P&L (Equity area + Drawdown bars)
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily net cumulative P&L")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            Text("Running total of net profit and loss over the selected period.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Spacer()
                    }
                    
                    EquityCurveChart(points: chartEquityPoints, currency: env.currentCurrency)
                        .frame(height: 180)
                    
                    Divider().background(AppColors.border)
                    
                    DrawdownChart(points: chartEquityPoints)
                        .frame(height: 70)
                }
            }
            
            // Widget 7: Net daily P&L (DailyBars)
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Net daily P&L")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            Text("Net profit or loss for each trading day. Bars above zero are profitable; bars below zero are losses.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Spacer()
                    }
                    
                    if overview.days.isEmpty {
                        Text("No trading day data available.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Chart {
                            RuleMark(y: .value("Zero", 0))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(AppColors.border)
                            
                            ForEach(overview.days, id: \.date) { d in
                                BarMark(
                                    x: .value("Date", String(d.date.suffix(5))),
                                    y: .value("Net P&L", (d.netPnl as NSDecimalNumber).doubleValue)
                                )
                                .foregroundStyle(d.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                .cornerRadius(3)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .frame(height: 160)
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Detail Group (Widgets 8, 9)
    @ViewBuilder
    private var detailGroupSection: some View {
        VStack(spacing: 10) {
            // Widget 8: Calendar Mini Widget
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(monthName)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        Button {
                            env.selectedTab = .calendar
                        } label: {
                            Text("Full calendar")
                                .font(AppTypography.captionBold)
                                .underline()
                                .foregroundColor(AppColors.brand)
                        }
                    }
                    
                    // Weekday headers
                    let weekCols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                        ForEach(weekCols, id: \.self) { w in
                            Text(w)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(maxWidth: .infinity)
                        }
                        
                        let isoFormatter: DateFormatter = {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd"
                            return f
                        }()
                        
                        ForEach(Array(calendarMonthDays.enumerated()), id: \.offset) { _, d in
                            if let date = d {
                                let key = isoFormatter.string(from: date)
                                let stats = daysWithTradesMap[key]
                                let dayNum = Calendar.current.component(.day, from: date)
                                
                                VStack(spacing: 1) {
                                    Text("\(dayNum)")
                                        .font(.system(size: 9))
                                        .foregroundColor(stats != nil ? AppColors.primaryText : AppColors.secondaryText)
                                    
                                    if let s = stats {
                                        Text(s.netPnl >= 0 ? "+" : "-")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundColor(s.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    }
                                }
                                .frame(height: 26)
                                .frame(maxWidth: .infinity)
                                .background(stats != nil ? (stats!.netPnl >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12)) : Color.clear)
                                .cornerRadius(4)
                            } else {
                                Color.clear
                                    .frame(height: 26)
                            }
                        }
                    }
                    
                    Divider().background(AppColors.border)
                    
                    HStack {
                        Text("\(currentMonthStats.tradingDays) trading days · \(currentMonthStats.winningDays) green")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("Month: \(Formatters.formatPnL(currentMonthStats.monthPnl, currency: env.currentCurrency))")
                            .font(AppTypography.captionBold)
                            .foregroundColor(currentMonthStats.monthPnl >= 0 ? AppColors.profit : AppColors.loss)
                    }
                }
            }
            
            // Widget 9: Activity (Tabs: Recent trades & Open positions)
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    Picker("Activity Tab", selection: $activityTab) {
                        Text("Recent trades").tag("recent")
                        Text("Open positions").tag("open")
                    }
                    .pickerStyle(.segmented)
                    
                    if activityTab == "recent" {
                        let recent = scopedTrades.filter { $0.status != .open }.prefix(5)
                        if recent.isEmpty {
                            Text("No closed trades yet")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(recent) { t in
                                    HStack {
                                        AppBadge(t.status.rawValue.uppercased(), color: Formatters.statusColor(t.status))
                                        
                                        Text(t.symbol)
                                            .font(AppTypography.bodyBold)
                                            .foregroundColor(AppColors.primaryText)
                                        
                                        Spacer()
                                        
                                        if let closed = t.closedAt {
                                            Text(Formatters.formatDate(closed))
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        
                                        AppMonetaryText(
                                            Formatters.formatPnL(t.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                            color: t.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                        )
                                    }
                                    .padding(.vertical, 2)
                                    
                                    if t.id != recent.last?.id {
                                        Divider().background(AppColors.border)
                                    }
                                }
                            }
                        }
                    } else {
                        let openPos = dataStore.trades.filter { $0.status == .open }
                        if openPos.isEmpty {
                            Text("Flat — no open positions")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(openPos) { p in
                                    HStack {
                                        AppBadge(p.direction.rawValue.uppercased(), color: p.direction == .long ? AppColors.profit : AppColors.loss)
                                        
                                        Text(p.symbol)
                                            .font(AppTypography.bodyBold)
                                            .foregroundColor(AppColors.primaryText)
                                        
                                        Spacer()
                                        
                                        Text("\(p.quantity) @ \(Formatters.formatCurrency(p.avgEntry, currency: env.currentCurrency))")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    .padding(.vertical, 2)
                                    
                                    if p.id != openPos.last?.id {
                                        Divider().background(AppColors.border)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 4. Secondary Metrics (Widgets 10, 11, 12, 13, 14)
    @ViewBuilder
    private func secondaryMetricsGrid(metrics: TradeMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            // Widget 10: Max drawdown
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    statHeader("Max drawdown", icon: "chart.line.downtrend.xyaxis")
                    
                    AppMonetaryText(
                        Formatters.formatCurrency(metrics.maxDrawdown, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 18, weight: .semibold),
                        color: AppColors.loss
                    )
                    
                    Text(metrics.maxDrawdownPct != nil ? String(format: "-%.1f%%", metrics.maxDrawdownPct! * 100) : "–")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Widget 11: Streaks
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    statHeader("Streaks", icon: "flame")
                    
                    Text(metrics.currentStreak > 0 ? "\(metrics.currentStreak)W" : (metrics.currentStreak < 0 ? "\(-metrics.currentStreak)L" : "–"))
                        .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                        .foregroundColor(metrics.currentStreak > 0 ? AppColors.profit : (metrics.currentStreak < 0 ? AppColors.loss : AppColors.primaryText))
                    
                    Text("best \(metrics.maxWinStreak)W · worst \(metrics.maxLossStreak)L")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Widget 12: Expectancy / trade
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    statHeader("Expectancy / trade", icon: "sum")
                    
                    AppMonetaryText(
                        metrics.expectancy != nil ? Formatters.formatPnL(metrics.expectancy!, currency: env.currentCurrency) : "–",
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 18, weight: .semibold),
                        color: (metrics.expectancy ?? 0) >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    Text(metrics.avgRealizedR != nil ? String(format: "avg %.2fR over %d trades", metrics.avgRealizedR!, metrics.tradesWithRisk) : "net P&L ÷ closed trades")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
            
            // Widget 13: Avg duration
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    statHeader("Avg duration", icon: "timer")
                    
                    Text(Formatters.formatDuration(ms: metrics.avgDurationMs))
                        .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("average holding time")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Widget 14: Best / worst day
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    statHeader("Best / worst day", icon: "trophy")
                    
                    if let best = bestDay, let worst = worstDay {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                AppMonetaryText(
                                    Formatters.formatPnL(best.netPnl, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                    color: AppColors.profit
                                )
                                Spacer()
                                Text(String(best.date.suffix(5)))
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            HStack {
                                AppMonetaryText(
                                    Formatters.formatPnL(worst.netPnl, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                    color: AppColors.loss
                                )
                                Spacer()
                                Text(String(worst.date.suffix(5)))
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    } else {
                        Text("No closed trades yet")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }
    
    // MARK: - 5. Full Width Performance (Widget 15)
    private var tradeTimePerformanceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trade time performance")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Text("Trades grouped by their opening hour. Bars show net P&L.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                
                if hourlyStats.isEmpty {
                    Text("No hourly trade data available.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(AppColors.border)
                        
                        ForEach(hourlyStats) { h in
                            BarMark(
                                x: .value("Hour", "\(h.key):00"),
                                y: .value("P&L", (h.netPnl as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(h.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                            .cornerRadius(3)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 160)
                }
            }
        }
    }
    
    private func statHeader(_ title: String, icon: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.cardTitle)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AppColors.secondaryText.opacity(0.8))
        }
    }
    
    private func scorePillarRow(_ title: String, value: Double, max: Double) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Text(String(format: "%.1f / %.0f", value, max))
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
        }
    }
}
