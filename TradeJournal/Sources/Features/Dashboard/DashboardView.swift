import SwiftUI
import Charts

public enum DashboardChartTab: String, CaseIterable, Identifiable {
    case equity = "Equity"
    case drawdown = "Drawdown"
    case session = "Sessions"
    case weekday = "Weekdays"
    
    public var id: String { rawValue }
}

public struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedRange: JournalTimeRange = .all
    @State private var selectedChartTab: DashboardChartTab = .equity
    @State private var showEdgeScoreBreakdown: Bool = false
    @State private var showAIReflection: Bool = false
    @State private var showAddTradeSheet: Bool = false
    
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
        let initialBalance = dataStore.selectedAccount?.initialBalance ?? 0
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
    
    private var sessionStats: [BucketStats] {
        AggregateEngine.bySession(trades: scopedTrades)
    }
    
    private var weekdayStats: [BucketStats] {
        AggregateEngine.byWeekday(trades: scopedTrades, timeZone: env.currentTimeZone)
    }
    
    private var symbolStats: [BucketStats] {
        AggregateEngine.bySymbol(trades: scopedTrades)
    }
    
    // Momentum: net P&L của 7 ngày qua vs 7 ngày trước đó
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
    
    public var body: some View {
        let metrics = overview.metrics
        
        VStack(spacing: 0) {
            // FilterBar chuẩn xác từ web
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
                    summaryWidgetsSection(metrics: metrics)
                    edgeScoreCard
                    chartVisualsCard
                    activityCard
                    secondaryMetricsGrid(metrics: metrics)
                    bestWorstDayCard
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
    
    @ViewBuilder
    private func summaryWidgetsSection(metrics: TradeMetrics) -> some View {
        VStack(spacing: 10) {
            // Widget 0: Net P&L
            AppCard {
                VStack(alignment: .leading, spacing: 6) {
                    AppCardHeader("Net P&L", icon: "dollarsign.circle")
                    
                    HStack(alignment: .firstTextBaseline) {
                        AppMonetaryText(
                            Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 26, weight: .semibold),
                            color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                        
                        Spacer()
                        
                        if let delta = weekDelta {
                            HStack(spacing: 3) {
                                Text(delta >= 0 ? "▲" : "▼")
                                    .font(.system(size: 9))
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
                        AppCardHeader("Trade win %", icon: "target")
                        
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
                        AppCardHeader("Profit factor", icon: "scalemass")
                        
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
                        AppCardHeader("Day win %", icon: "calendar.badge.clock")
                        
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
                        AppCardHeader("Avg win / loss", icon: "arrow.up.arrow.down")
                        
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
    
    private var edgeScoreCard: some View {
        AppCard {
            VStack(spacing: 8) {
                HStack {
                    AppCardHeader("Edge Score", icon: "info.circle")
                    
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
                
                if showEdgeScoreBreakdown, let b = edgeResult.breakdown {
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
    }
    
    private var chartVisualsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("BIỂU ĐỒ HIỆU SUẤT")
                        .font(AppTypography.cardTitle)
                        .tracking(0.88)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                }
                
                Picker("Tab biểu đồ", selection: $selectedChartTab) {
                    ForEach(DashboardChartTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                
                switch selectedChartTab {
                case .equity:
                    EquityCurveChart(points: chartEquityPoints, currency: env.currentCurrency)
                case .drawdown:
                    DrawdownChart(points: chartEquityPoints)
                case .session:
                    SessionBreakdownChart(sessions: sessionStats, currency: env.currentCurrency)
                case .weekday:
                    WeekdayChart(weekdays: weekdayStats, currency: env.currentCurrency)
                }
            }
        }
    }
    
    private var activityCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader("Activity", icon: "clock.arrow.circlepath")
                
                if scopedTrades.isEmpty {
                    Text("Chưa có lệnh giao dịch nào trong khoảng thời gian này.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    ForEach(scopedTrades.prefix(5)) { trade in
                        HStack {
                            AppBadge(trade.status.rawValue.uppercased(), color: Formatters.statusColor(trade.status))
                            
                            Text(trade.symbol)
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            Spacer()
                            
                            if let closed = trade.closedAt {
                                Text(Formatters.formatDate(closed))
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            AppMonetaryText(
                                Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                color: trade.netPnl >= 0 ? AppColors.profit : AppColors.loss
                            )
                        }
                        .padding(.vertical, 2)
                        
                        if trade.id != scopedTrades.prefix(5).last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func secondaryMetricsGrid(metrics: TradeMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            // Max drawdown
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Max drawdown", icon: "chart.line.downtrend.xyaxis")
                    
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
            
            // Streaks
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Streaks", icon: "flame")
                    
                    Text(metrics.currentStreak > 0 ? "\(metrics.currentStreak)W" : (metrics.currentStreak < 0 ? "\(-metrics.currentStreak)L" : "–"))
                        .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                        .foregroundColor(metrics.currentStreak > 0 ? AppColors.profit : (metrics.currentStreak < 0 ? AppColors.loss : AppColors.primaryText))
                    
                    Text("best \(metrics.maxWinStreak)W · worst \(metrics.maxLossStreak)L")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Expectancy / trade
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Expectancy / trade", icon: "sum")
                    
                    AppMonetaryText(
                        metrics.expectancy != nil ? Formatters.formatPnL(metrics.expectancy!, currency: env.currentCurrency) : "–",
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 18, weight: .semibold),
                        color: (metrics.expectancy ?? 0) >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    Text(metrics.avgRealizedR != nil ? String(format: "avg %.2fR over %d trades", metrics.avgRealizedR!, metrics.tradesWithRisk) : "Kỳ vọng/lệnh")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
            
            // Avg duration
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Avg duration", icon: "timer")
                    
                    Text(Formatters.formatDuration(ms: metrics.avgDurationMs))
                        .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Thời lượng nắm giữ TB")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var bestWorstDayCard: some View {
        if let best = bestDay, let worst = worstDay {
            AppCard {
                VStack(alignment: .leading, spacing: 6) {
                    AppCardHeader("Best / worst day", icon: "trophy")
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ngày thắng lớn nhất")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            HStack(spacing: 6) {
                                AppMonetaryText(
                                    Formatters.formatPnL(best.netPnl, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.financialNumber(size: 14, weight: .semibold),
                                    color: AppColors.profit
                                )
                                Text(best.date)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Ngày lỗ lớn nhất")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            HStack(spacing: 6) {
                                AppMonetaryText(
                                    Formatters.formatPnL(worst.netPnl, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.financialNumber(size: 14, weight: .semibold),
                                    color: AppColors.loss
                                )
                                Text(worst.date)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                }
            }
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
