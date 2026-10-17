import SwiftUI
import Charts

public struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @AppStorage("dashboard_hidden_widgets") private var hiddenWidgetsRaw: String = ""
    @State private var selectedRange: JournalTimeRange = .all
    @State private var showEdgeScoreBreakdown: Bool = false
    @State private var showCustomizerSheet: Bool = false
    @State private var showAIReflection: Bool = false
    @State private var showAddTradeSheet: Bool = false
    @State private var activityTab: String = "recent" // "recent" or "open"
    @State private var activeTooltip: (title: String, hint: String)? = nil
    
    public init() {}
    
    private var hiddenCardIds: Set<String> {
        guard !hiddenWidgetsRaw.isEmpty else { return [] }
        return Set(hiddenWidgetsRaw.split(separator: ",").map(String.init))
    }
    
    private var hiddenCardIdsBinding: Binding<Set<String>> {
        Binding(
            get: { hiddenCardIds },
            set: { newSet in
                hiddenWidgetsRaw = newSet.joined(separator: ",")
            }
        )
    }
    
    private var visibleCardCount: Int {
        DashboardCardRegistry.allCards.count - hiddenCardIds.count
    }
    
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
        var runningPeak: Decimal = 0
        return overview.curve.map { pt in
            if pt.cumNetPnl > runningPeak {
                runningPeak = pt.cumNetPnl
            }
            let dd = runningPeak > 0 ? (runningPeak - pt.cumNetPnl) / runningPeak : Decimal.zero
            return EquityPointItem(
                date: pt.timestamp,
                dateKey: pt.dateString,
                netPnl: pt.cumNetPnl,
                cumulativePnl: pt.cumNetPnl,
                drawdown: dd
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
    
    // Calendar helpers for Widget 8
    private var calendarWeeks: [[Date?]] {
        let cal = Calendar.current
        let now = Date()
        guard let monthInterval = cal.dateInterval(of: .month, for: now),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let range = cal.range(of: .day, in: .month, for: now) else {
            return []
        }
        
        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = []
        
        let firstWeekday = cal.component(.weekday, from: firstDay) // 1 = Sunday
        for _ in 1..<firstWeekday {
            currentWeek.append(nil)
        }
        
        for d in range {
            if let date = cal.date(byAdding: .day, value: d - 1, to: firstDay) {
                currentWeek.append(date)
                if currentWeek.count == 7 {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }
        
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }
        return weeks
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
            
            // Top Toolbar: Saved Layout & Customize trigger matching dashboard-layout.tsx
            layoutBar
            
            ScrollView {
                VStack(spacing: 12) {
                    syncNotificationSection
                    
                    if metrics.totalTrades == 0 {
                        emptyStateCard
                    } else {
                        // SECTION 1: Summary Group (Widgets 0-4)
                        summaryGroupSection(metrics: metrics)
                        
                        // SECTION 2: Visuals Group (Widgets 5, 6, 7)
                        visualsGroupSection(metrics: metrics)
                        
                        // SECTION 3: Detail Group (Widgets 8, 9)
                        detailGroupSection
                        
                        // SECTION 4: Secondary Metrics Group (Widgets 10-14)
                        secondaryMetricsGrid(metrics: metrics)
                        
                        // SECTION 5: Full Width Performance (Widget 15)
                        if !hiddenCardIds.contains("widget-15") {
                            tradeTimePerformanceCard
                        }
                    }
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
        .sheet(isPresented: $showCustomizerSheet) {
            DashboardCustomizerSheet(hiddenCardIds: hiddenCardIdsBinding)
        }
        .sheet(isPresented: $showAIReflection) {
            AIReflectionView()
        }
        .sheet(isPresented: $showAddTradeSheet) {
            AddTradeSheet()
        }
        .alert(activeTooltip?.title ?? "Info", isPresented: Binding(
            get: { activeTooltip != nil },
            set: { if !$0 { activeTooltip = nil } }
        )) {
            Button("Got it", role: .cancel) { activeTooltip = nil }
        } message: {
            Text(activeTooltip?.hint ?? "")
        }
    }
    
    // MARK: - Top Layout Bar
    
    private var layoutBar: some View {
        HStack(spacing: 8) {
            // Saved layout badge
            HStack(spacing: 4) {
                Text("Default layout")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            
            Text("\(visibleCardCount) of \(DashboardCardRegistry.allCards.count) cards")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            // Customize button matching web dashboard-customizer.tsx
            Button {
                showCustomizerSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("Customize")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.cardBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyStateCard: some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.secondaryText)
                
                Text("Your journal is empty")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Text("Connect a broker for automatic sync, upload a statement, or add trades manually.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                
                AppButton("Import your first trades", icon: "square.and.arrow.down", style: .primary) {
                    env.selectedTab = .settings
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
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
            // Widget 0: Net P&L
            if !hiddenCardIds.contains("widget-0") {
                AppCard {
                    VStack(alignment: .leading, spacing: 6) {
                        statHeader(
                            "Net P&L",
                            icon: "dollarsign.circle",
                            hint: "Realized profit and loss net of fees, over the selected range."
                        )
                        
                        HStack(alignment: .firstTextBaseline) {
                            AppMonetaryText(
                                Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 28, weight: .bold),
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
            }
            
            // 2x2 Grid for Widgets 1, 2, 3, 4
            let showW1 = !hiddenCardIds.contains("widget-1")
            let showW2 = !hiddenCardIds.contains("widget-2")
            let showW3 = !hiddenCardIds.contains("widget-3")
            let showW4 = !hiddenCardIds.contains("widget-4")
            
            if showW1 || showW2 || showW3 || showW4 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    // Widget 1: Trade win %
                    if showW1 {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                statHeader(
                                    "Trade win %",
                                    icon: "target",
                                    hint: "Winning trades divided by all closed trades, including breakevens."
                                )
                                
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
                    }
                    
                    // Widget 2: Profit factor
                    if showW2 {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                statHeader(
                                    "Profit factor",
                                    icon: "scalemass",
                                    hint: "Gross profit ÷ gross loss. Above 1 means the wins outweigh the losses."
                                )
                                
                                Text(metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor != nil ? String(format: "%.2f", metrics.profitFactor!) : "–"))
                                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                                    .foregroundColor(AppColors.primaryText)
                                
                                Text("gross profit ÷ gross loss")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                    
                    // Widget 3: Day win %
                    if showW3 {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                statHeader(
                                    "Day win %",
                                    icon: "calendar.badge.clock",
                                    hint: "Green trading days ÷ all trading days in the selected range."
                                )
                                
                                HStack(alignment: .center, spacing: 8) {
                                    GaugeView(value: metrics.dayWinRate, label: "Day win rate", size: 84)
                                    
                                    Spacer()
                                    
                                    Text("\(metrics.tradingDays) days")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    
                    // Widget 4: Avg win / loss
                    if showW4 {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                statHeader(
                                    "Avg win / loss",
                                    icon: "arrow.up.arrow.down",
                                    hint: "Average winning trade ÷ average losing trade. The bar shows the two to scale."
                                )
                                
                                Text(metrics.avgWinLossRatio != nil ? String(format: "%.2f", metrics.avgWinLossRatio!) : "–")
                                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
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
        }
    }
    
    // MARK: - 2. Visuals Group (Widgets 5, 6, 7)
    @ViewBuilder
    private func visualsGroupSection(metrics: TradeMetrics) -> some View {
        VStack(spacing: 10) {
            // Widget 5: Edge Score
            if !hiddenCardIds.contains("widget-5") {
                AppCard {
                    VStack(spacing: 10) {
                        HStack {
                            statHeader(
                                "Edge Score",
                                icon: "info.circle",
                                hint: "A 0–100 score combining win rate, profit factor, average win/loss, drawdown, recovery, and consistency. Requires at least five closed trades."
                            )
                            
                            Spacer()
                            
                            HStack(spacing: 2) {
                                Text(edgeResult.score != nil ? "\(Int(edgeResult.score!))" : "–")
                                    .font(AppTypography.financialNumber(size: 22, weight: .bold))
                                    .foregroundColor(AppColors.brand)
                                Text("/100")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                        
                        if metrics.closedTrades < 5 {
                            Text("Needs 5+ closed trades. A 0–100 score combining win rate, profit factor, average win/loss, drawdown, recovery, and consistency.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 16)
                        } else {
                            // Apple HIG 6-Axis Radar Chart
                            EdgeRadarView(components: edgeResult.components, height: 210)
                            
                            Button {
                                withAnimation {
                                    showEdgeScoreBreakdown.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(showEdgeScoreBreakdown ? "Hide component breakdown" : "View component breakdown")
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: showEdgeScoreBreakdown ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9))
                                }
                                .foregroundColor(AppColors.brand)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                            
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
            }
            
            // Widget 6: Daily net cumulative P&L
            if !hiddenCardIds.contains("widget-6") {
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        statHeader(
                            "Daily net cumulative P&L",
                            icon: "info.circle",
                            hint: "Running total of net profit and loss over the selected period. The drawdown bars below show declines from the running equity peak."
                        )
                        
                        EquityCurveChart(points: chartEquityPoints, currency: env.currentCurrency, height: 180)
                        
                        Divider().background(AppColors.border)
                        
                        DrawdownChart(points: chartEquityPoints, height: 75)
                    }
                }
            }
            
            // Widget 7: Net daily P&L
            if !hiddenCardIds.contains("widget-7") {
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        statHeader(
                            "Net daily P&L",
                            icon: "info.circle",
                            hint: "Net profit or loss for each trading day. Bars above zero are profitable; bars below zero are losses."
                        )
                        
                        DailyBarsView(
                            data: overview.days.map { DailyBarDatum(date: $0.date, netPnl: $0.netPnl) },
                            currency: env.currentCurrency,
                            isPrivate: env.isPrivacyModeEnabled,
                            height: 160
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Detail Group (Widgets 8, 9)
    @ViewBuilder
    private var detailGroupSection: some View {
        VStack(spacing: 10) {
            // Widget 8: Calendar Mini Widget (8-column layout matching calendar-pnl.tsx)
            if !hiddenCardIds.contains("widget-8") {
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
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
                        
                        // 8-column header (Sun..Sat + Week)
                        let cols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Wk"]
                        HStack(spacing: 3) {
                            ForEach(cols, id: \.self) { c in
                                Text(c)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: c == "Wk" ? .trailing : .center)
                            }
                        }
                        
                        let isoFormatter: DateFormatter = {
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd"
                            return f
                        }()
                        
                        // Calendar Weeks with Week Total Column
                        VStack(spacing: 4) {
                            ForEach(0..<calendarWeeks.count, id: \.self) { wIndex in
                                let week = calendarWeeks[wIndex]
                                let weekDays = week.compactMap { $0 }
                                let weekPnl = weekDays.compactMap { d -> Decimal? in
                                    let key = isoFormatter.string(from: d)
                                    return daysWithTradesMap[key]?.netPnl
                                }.reduce(Decimal.zero, +)
                                
                                HStack(spacing: 3) {
                                    ForEach(0..<7, id: \.self) { dayIdx in
                                        if let date = week[dayIdx] {
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
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    
                                    // Week total column
                                    Text(weekPnl != 0 ? Formatters.formatPnL(weekPnl, currency: env.currentCurrency) : "–")
                                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(weekPnl > 0 ? AppColors.profit : (weekPnl < 0 ? AppColors.loss : AppColors.secondaryText))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
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
            }
            
            // Widget 9: Activity (Recent trades & Open positions)
            if !hiddenCardIds.contains("widget-9") {
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
    }
    
    // MARK: - 4. Secondary Metrics (Widgets 10, 11, 12, 13, 14)
    @ViewBuilder
    private func secondaryMetricsGrid(metrics: TradeMetrics) -> some View {
        let showW10 = !hiddenCardIds.contains("widget-10")
        let showW11 = !hiddenCardIds.contains("widget-11")
        let showW12 = !hiddenCardIds.contains("widget-12")
        let showW13 = !hiddenCardIds.contains("widget-13")
        let showW14 = !hiddenCardIds.contains("widget-14")
        
        if showW10 || showW11 || showW12 || showW13 || showW14 {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Widget 10: Max drawdown
                if showW10 {
                    AppCard {
                        VStack(alignment: .leading, spacing: 4) {
                            statHeader(
                                "Max drawdown",
                                icon: "chart.line.downtrend.xyaxis",
                                hint: "Largest peak-to-trough drop of the cumulative P&L curve."
                            )
                            
                            AppMonetaryText(
                                Formatters.formatCurrency(metrics.maxDrawdown, currency: env.currentCurrency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 18, weight: .bold),
                                color: AppColors.loss
                            )
                            
                            Text(metrics.maxDrawdownPct != nil ? String(format: "-%.1f%%", metrics.maxDrawdownPct! * 100) : "–")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                // Widget 11: Streaks
                if showW11 {
                    AppCard {
                        VStack(alignment: .leading, spacing: 4) {
                            statHeader(
                                "Streaks",
                                icon: "flame",
                                hint: "Current run of consecutive wins (W) or losses (L), with the best and worst runs."
                            )
                            
                            Text(metrics.currentStreak > 0 ? "\(metrics.currentStreak)W" : (metrics.currentStreak < 0 ? "\(-metrics.currentStreak)L" : "–"))
                                .font(AppTypography.financialNumber(size: 18, weight: .bold))
                                .foregroundColor(metrics.currentStreak > 0 ? AppColors.profit : (metrics.currentStreak < 0 ? AppColors.loss : AppColors.primaryText))
                            
                            Text("best \(metrics.maxWinStreak)W · worst \(metrics.maxLossStreak)L")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                // Widget 12: Expectancy / trade
                if showW12 {
                    AppCard {
                        VStack(alignment: .leading, spacing: 4) {
                            statHeader(
                                "Expectancy / trade",
                                icon: "sum",
                                hint: "Average net P&L per closed trade: what one more trade is worth on your numbers."
                            )
                            
                            AppMonetaryText(
                                metrics.expectancy != nil ? Formatters.formatPnL(metrics.expectancy!, currency: env.currentCurrency) : "–",
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 18, weight: .bold),
                                color: (metrics.expectancy ?? 0) >= 0 ? AppColors.profit : AppColors.loss
                            )
                            
                            Text(metrics.avgRealizedR != nil ? String(format: "avg %.2fR over %d trades", metrics.avgRealizedR!, metrics.tradesWithRisk) : "net P&L ÷ closed trades")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Widget 13: Avg duration
                if showW13 {
                    AppCard {
                        VStack(alignment: .leading, spacing: 4) {
                            statHeader(
                                "Avg duration",
                                icon: "timer",
                                hint: "Average time from first entry fill to final exit."
                            )
                            
                            Text(Formatters.formatDuration(ms: metrics.avgDurationMs))
                                .font(AppTypography.financialNumber(size: 18, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                            
                            Text("winners vs losers in Reports")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                // Widget 14: Best / worst day
                if showW14 {
                    AppCard {
                        VStack(alignment: .leading, spacing: 4) {
                            statHeader(
                                "Best / worst day",
                                icon: "trophy",
                                hint: "Highest and lowest single-day net P&L in the selected range."
                            )
                            
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
        }
    }
    
    // MARK: - 5. Full Width Performance (Widget 15)
    private var tradeTimePerformanceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Trade time performance",
                    icon: "clock",
                    hint: "Trades grouped by their opening hour. The upper chart shows net P&L; the lower chart shows trade count."
                )
                
                if hourlyStats.isEmpty {
                    Text("No hourly trade data available.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    TimeHeatmapView(
                        hours: hourlyStats,
                        currency: env.currentCurrency,
                        isPrivate: env.isPrivacyModeEnabled
                    )
                }
            }
        }
    }
    
    private func statHeader(_ title: String, icon: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(AppTypography.cardTitle)
                .foregroundColor(AppColors.primaryText)
            Spacer()
            Button {
                activeTooltip = (title: title, hint: hint)
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .buttonStyle(.plain)
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
