import SwiftUI
import Charts

/// Model representing pre-computed day details passed directly to DayDetailSheet
public struct DayDetailContext: Identifiable {
    public var id: String { dateKey }
    public let dateKey: String
    public let stats: DayStats?
    public let trades: [Trade]
    public let note: JournalNote
    
    public init(dateKey: String, stats: DayStats?, trades: [Trade], note: JournalNote) {
        self.dateKey = dateKey
        self.stats = stats
        self.trades = trades
        self.note = note
    }
}

/// Monthly P&L Calendar view matching 100% of web parity:
/// - `source-repo/apps/web/src/app/calendar/page.tsx`
/// - `source-repo/apps/web/src/components/calendar-pnl.tsx`
/// - `source-repo/apps/web/src/components/calendar-insights.tsx`
///
/// Features:
/// 1. FilterBar with Month navigator (< Month Year >) and Account/Filter controls
/// 2. CurrencyNotice if multi-currency accounts are selected
/// 3. 8-column calendar grid: Sun, Mon, Tue, Wed, Thu, Fri, Sat, and Week total column
/// 4. Day cells with magnitude-scaled profit/loss background tint, trade count, and note dots
/// 5. Week total cell per row showing net P&L and total trades
/// 6. Footer showing active trading days, green days, and total month net P&L
/// 7. Performance insights breakdown:
///    - 4 Metric cards: Net P&L, Average daily P&L, Trade win rate, Total closed trades
///    - Best & worst day extrema card
///    - Average green & red day card
///    - Day consistency card (% profitable days)
///    - Daily performance chart with zero reference line and 5-day average trend
///    - Expandable daily results table
///    - Performance by weekday with most profitable highlight and bidirectional progress bars
public struct JournalCalendarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var currentMonth: Date = Date()
    @State private var selectedDayContext: DayDetailContext? = nil
    @State private var selectedWeekdayIndex: Int? = nil
    @State private var addTradeDate: Date? = nil
    @State private var showAddTradeSheet: Bool = false
    @State private var showDailyTable: Bool = false
    @State private var selectedTrendDate: String? = nil
    
    public init() {}
    
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = env.currentTimeZone
        return cal
    }
    
    private var year: Int {
        calendar.component(.year, from: currentMonth)
    }
    
    private var month: Int {
        calendar.component(.month, from: currentMonth)
    }
    
    private var monthPrefix: String {
        String(format: "%04d-%02d", year, month)
    }
    
    private var overview: (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        FinancialMetricsEngine.computeOverview(
            trades: dataStore.filteredTrades,
            timeZone: env.currentTimeZone
        )
    }
    
    private var dateKeyFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = env.currentTimeZone
        return f
    }
    
    private var dailyStatsMap: [String: DayStats] {
        var map: [String: DayStats] = [:]
        for d in overview.days {
            map[d.date] = d
        }
        return map
    }
    
    private var tradesByDateMap: [String: [Trade]] {
        let f = dateKeyFormatter
        var map: [String: [Trade]] = [:]
        for trade in dataStore.filteredTrades {
            let key = f.string(from: trade.closedAt ?? trade.openedAt)
            map[key, default: []].append(trade)
        }
        return map
    }
    
    private var calendarMonth: CalendarMonth {
        AggregateEngine.calendarMonthFromDays(
            dayStats: overview.days,
            year: year,
            month: month
        )
    }
    
    private var insights: CalendarInsights {
        CalendarInsightsEngine.calendarInsights(calendar: calendarMonth)
    }
    
    private var maxAbsPnl: Double {
        let maxVal = calendarMonth.weeks
            .flatMap { $0.days }
            .compactMap { $0 }
            .map { abs(($0.netPnl as NSDecimalNumber).doubleValue) }
            .max() ?? 1.0
        return max(1.0, maxVal)
    }
    
    private var peakWeekdayAbsPnl: Double {
        let peak = insights.weekdays.map { abs(($0.netPnl as NSDecimalNumber).doubleValue) }.max() ?? 1.0
        return max(1.0, peak)
    }
    
    private var availableCurrencies: [String] {
        dataStore.availableCurrencies
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header FilterBar matching calendar/page.tsx
                FilterBarView(
                    title: "Calendar",
                    showFilters: false
                ) {
                    HStack(spacing: 6) {
                        Button(action: { changeMonth(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                                .frame(width: 28, height: 28)
                                .background(AppColors.cardBackground)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel("Previous month")
                        
                        Text(monthTitle(for: currentMonth))
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                            .frame(minWidth: 124, alignment: .center)
                        
                        Button(action: { changeMonth(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                                .frame(width: 28, height: 28)
                                .background(AppColors.cardBackground)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel("Next month")
                    }
                }
                
                ScrollView {
                    VStack(spacing: 14) {
                        // Multi-currency notice matching calendar/page.tsx line 74
                        if availableCurrencies.count > 1 {
                            currencyNoticeBanner
                        }
                        
                        // Monthly Calendar Card with 8 columns matching calendar-pnl.tsx
                        calendarCard
                        
                        // Performance Insights Section matching calendar-insights.tsx
                        performanceInsightsSection
                    }
                    .padding(14)
                }
                .background(AppColors.background)
            }
            // Dedicated item-based presentation eliminates white screens and guarantees instant loading
            .sheet(item: $selectedDayContext) { ctx in
                DayDetailSheet(
                    dateKey: ctx.dateKey,
                    stats: ctx.stats,
                    trades: ctx.trades,
                    note: ctx.note,
                    onSaveNote: { updatedNote in
                        dataStore.saveCalendarNote(updatedNote)
                    },
                    onAddTrade: {
                        let targetDate = parseDate(from: ctx.dateKey)
                        selectedDayContext = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            addTradeDate = targetDate
                            showAddTradeSheet = true
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(isPresented: $showAddTradeSheet) {
                AddTradeSheet(initialDate: addTradeDate ?? Date())
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
    }
    
    // MARK: - Instant Day Selection Handler
    
    private func openDayDetail(for dateKey: String) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let stats = dailyStatsMap[dateKey]
        let trades = tradesByDateMap[dateKey] ?? []
        let note = dataStore.calendarNotes[dateKey] ?? JournalNote(date: dateKey)
        selectedDayContext = DayDetailContext(
            dateKey: dateKey,
            stats: stats,
            trades: trades,
            note: note
        )
    }
    
    // MARK: - Currency Notice Banner
    
    @ViewBuilder
    private var currencyNoticeBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(AppColors.brand)
                .font(.system(size: 14))
            
            Text("These trades use multiple currencies (\(availableCurrencies.joined(separator: ", "))). Select accounts with one currency to compare monetary performance; no exchange-rate conversion is applied.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(10)
        .background(AppColors.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
    
    // MARK: - Calendar Card (8-Column Grid matching calendar-pnl.tsx)
    
    @ViewBuilder
    private var calendarCard: some View {
        let headers = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        AppCard {
            VStack(spacing: 8) {
                // Header row: 7 weekday columns + 8th "Week" column
                HStack(spacing: 4) {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                    
                    Text("Week")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 48, alignment: .trailing)
                }
                
                Divider().background(AppColors.border)
                
                // Calendar Week Rows
                VStack(spacing: 4) {
                    ForEach(0..<calendarMonth.weeks.count, id: \.self) { weekIndex in
                        let week = calendarMonth.weeks[weekIndex]
                        weekRowView(week: week)
                    }
                }
                
                Divider().background(AppColors.border)
                
                // Calendar Card Footer matching calendar-pnl.tsx lines 71-83
                HStack {
                    Text("\(calendarMonth.tradingDays) trading days · \(calendarMonth.winningDays) green")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("Month:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppMonetaryText(
                            Formatters.formatPnL(calendarMonth.monthNetPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.captionBold,
                            color: calendarMonth.monthNetPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    // MARK: - Week Row View (7 Days + 1 Week Total Cell)
    
    @ViewBuilder
    private func weekRowView(week: CalendarWeek) -> some View {
        HStack(spacing: 4) {
            // 7 Days of the Week
            ForEach(0..<7, id: \.self) { dayIndex in
                if dayIndex < week.days.count, let day = week.days[dayIndex] {
                    Button {
                        openDayDetail(for: day.date)
                    } label: {
                        dayCellView(day: day)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
            }
            
            // 8th Cell: Week Total Summary matching calendar-pnl.tsx lines 183-195
            weekTotalCellView(week: week)
                .frame(width: 48, height: 52)
        }
    }
    
    // MARK: - Individual Day Cell
    
    @ViewBuilder
    private func dayCellView(day: DayStats) -> some View {
        let isToday = isDateToday(day.date)
        let traded = day.trades > 0
        let pnlDouble = (day.netPnl as NSDecimalNumber).doubleValue
        let intensity = traded ? min(1.0, 0.12 + 0.38 * (abs(pnlDouble) / maxAbsPnl)) : 0
        let isProfit = day.netPnl >= 0
        let hasNote = dataStore.calendarNotes[day.date] != nil
        let dayNum = dayNumber(from: day.date)
        
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.system(size: 10, weight: isToday ? .bold : .medium))
                    .foregroundColor(isToday ? AppColors.brand : AppColors.primaryText)
                
                if hasNote {
                    Circle()
                        .fill(AppColors.brand)
                        .frame(width: 3.5, height: 3.5)
                }
            }
            
            if traded {
                AppMonetaryText(
                    compactMoney(day.netPnl),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: .system(size: 8, weight: .bold, design: .monospaced),
                    color: isProfit ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                
                Text("\(day.trades)t")
                    .font(.system(size: 7, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
            } else {
                Spacer().frame(height: 14)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    traded
                        ? (isProfit ? AppColors.profit.opacity(intensity) : AppColors.loss.opacity(intensity))
                        : AppColors.secondaryBackground.opacity(0.3)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isToday ? AppColors.brand : (traded ? AppColors.border.opacity(0.6) : Color.clear),
                    lineWidth: isToday ? 1.5 : 0.6
                )
        )
    }
    
    // MARK: - Week Total Cell
    
    @ViewBuilder
    private func weekTotalCellView(week: CalendarWeek) -> some View {
        VStack(spacing: 1) {
            Text("W")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(AppColors.mutedText)
            
            if week.weekTrades > 0 {
                AppMonetaryText(
                    compactMoney(week.weekNetPnl),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: .system(size: 8, weight: .bold, design: .monospaced),
                    color: week.weekNetPnl >= 0 ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                
                Text("\(week.weekTrades)t")
                    .font(.system(size: 7, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
            } else {
                Text("–")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(AppColors.mutedText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.secondaryBackground.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
        )
    }
    
    // MARK: - Performance Insights Section matching calendar-insights.tsx
    
    @ViewBuilder
    private var performanceInsightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance insights")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.primaryText)
                
                Text("Visible month × active filters · Closed trades, after fees · \(env.currentTimeZone.identifier)")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 2)
            
            if insights.tradingDays == 0 {
                AppCard {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 26))
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("No closed trades in this view")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Choose another month or adjust your account and filters. Open positions and days without trades aren't included in performance insights.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                // 4 Metric cards matching calendar-insights.tsx lines 136-168
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricCard(
                        title: "Net P&L",
                        value: Formatters.formatPnL(insights.netPnl, currency: env.currentCurrency),
                        detail: "\(insights.tradingDays) trading day\(insights.tradingDays == 1 ? "" : "s") · \(env.currentCurrency)",
                        valueColor: insights.netPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    metricCard(
                        title: "Average daily P&L",
                        value: Formatters.formatPnL(insights.avgDailyPnl ?? .zero, currency: env.currentCurrency),
                        detail: "Per day with closed trades",
                        valueColor: (insights.avgDailyPnl ?? .zero) >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    metricCard(
                        title: "Trade win rate",
                        value: String(format: "%.1f%%", (insights.winRate ?? 0) * 100),
                        detail: "\(insights.wins) wins · \(insights.losses) losses · \(insights.breakevens) break-even",
                        valueColor: AppColors.primaryText
                    )
                    
                    metricCard(
                        title: "Total closed trades",
                        value: "\(insights.trades)",
                        detail: "Round-trip trades, not executions",
                        valueColor: AppColors.primaryText
                    )
                }
                
                // Extrema & Consistency Cards matching calendar-insights.tsx lines 171-218
                VStack(spacing: 10) {
                    // Best & Worst Day
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Best & worst day")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                Text("Best day")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                if let best = insights.bestDay {
                                    HStack(spacing: 6) {
                                        AppMonetaryText(
                                            Formatters.formatPnL(best.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: AppColors.profit
                                        )
                                        Text(dateLabel(for: best.date))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                } else {
                                    Text("—").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                                }
                            }
                            
                            HStack {
                                Text("Worst day")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                if let worst = insights.worstDay {
                                    HStack(spacing: 6) {
                                        AppMonetaryText(
                                            Formatters.formatPnL(worst.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: AppColors.loss
                                        )
                                        Text(dateLabel(for: worst.date))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                } else {
                                    Text("—").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                                }
                            }
                            
                            Text(insights.tradingDays == 1 ? "One trading day; both extrema are the same." : "Highest and lowest daily net P&L.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.mutedText)
                        }
                    }
                    
                    // Average green & red day
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Average green & red day")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                Text("\(insights.greenDays) profitable days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                AppMonetaryText(
                                    Formatters.formatPnL(insights.avgGreenDay ?? .zero, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.profit
                                )
                            }
                            
                            HStack {
                                Text("\(insights.redDays) losing days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                AppMonetaryText(
                                    Formatters.formatPnL(insights.avgRedDay ?? .zero, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.loss
                                )
                            }
                            
                            Text("Each average uses only its own group.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.mutedText)
                        }
                    }
                    
                    // Day consistency
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Day consistency")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                Text("\(insights.greenDays) positive · \(insights.redDays) negative · \(insights.flatDays) flat days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Spacer()
                            
                            let rate = (insights.profitableDayRate ?? 0) * 100
                            Text(String(format: "%.1f%%", rate))
                                .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                                .foregroundColor(rate >= 50 ? AppColors.profit : AppColors.secondaryText)
                        }
                    }
                }
                
                // Detailed Charts: Daily Performance & Weekday Performance
                dailyPerformanceCard
                weekdayPerformanceCard
                
                if insights.tradingDays < 5 {
                    Text("Small sample: \(insights.tradingDays) trading day\(insights.tradingDays == 1 ? "" : "s"). Weekday results and consistency describe this selection only.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.mutedText)
                        .padding(.horizontal, 2)
                }
            }
        }
    }
    
    // MARK: - Daily Performance Chart Card matching calendar-insights.tsx lines 220-289
    
    @ViewBuilder
    private var dailyPerformanceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily performance")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Net P&L by closing day · \(env.currentCurrency)\(insights.tradingDays >= 8 ? " · Dashed line: 5-trading-day average" : "")")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                if insights.tradingDays >= 2 {
                    let activeTrend = insights.trend.first { dateLabel(for: $0.date) == selectedTrendDate }
                    
                    if let active = activeTrend {
                        HStack {
                            Text(dateLabel(for: active.date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(Formatters.formatPnL(active.netPnl, currency: env.currentCurrency))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        }
                        .padding(.horizontal, 2)
                    }
                    
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(AppColors.border.opacity(0.8))
                        
                        ForEach(insights.trend) { pt in
                            let label = dateLabel(for: pt.date)
                            BarMark(
                                x: .value("Day", label),
                                y: .value("Net P&L", (pt.netPnl as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(
                                pt.netPnl >= 0 ?
                                LinearGradient(
                                    colors: [AppColors.profit, AppColors.profit.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ) :
                                LinearGradient(
                                    colors: [AppColors.loss.opacity(0.75), AppColors.loss],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(3.5)
                            .opacity(selectedTrendDate == nil || selectedTrendDate == label ? 1.0 : 0.45)
                        }
                        
                        if insights.tradingDays >= 8 {
                            ForEach(insights.trend.filter { $0.average != nil }) { pt in
                                LineMark(
                                    x: .value("Day", dateLabel(for: pt.date)),
                                    y: .value("5-Day Avg", ((pt.average ?? .zero) as NSDecimalNumber).doubleValue)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                .foregroundStyle(AppColors.brand)
                            }
                        }
                        
                        if let sel = selectedTrendDate {
                            RuleMark(x: .value("Selected", sel))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(AppColors.primaryText.opacity(0.4))
                        }
                    }
                    .chartXSelection(value: $selectedTrendDate)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.border.opacity(0.3))
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(Formatters.formatCurrency(Decimal(d), currency: env.currentCurrency))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    .frame(height: 160)
                } else {
                    VStack(spacing: 4) {
                        Text("A trend needs more than one day")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        if let first = insights.days.first {
                            Text("\(dateLabel(for: first.date)) · \(Formatters.formatPnL(first.netPnl, currency: env.currentCurrency)) · \(first.trades) closed trades")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Text("Explore an earlier month with more trading history.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(AppColors.secondaryBackground.opacity(0.3))
                    .cornerRadius(6)
                }
                
                // Collapsible Daily Values Table matching calendar-insights.tsx line 247-287
                DisclosureGroup(
                    isExpanded: $showDailyTable,
                    content: {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Closing day").font(.system(size: 10, weight: .medium)).foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("Trades").font(.system(size: 10, weight: .medium)).foregroundColor(AppColors.secondaryText)
                                    .frame(width: 50, alignment: .trailing)
                                Text("Net P&L").font(.system(size: 10, weight: .medium)).foregroundColor(AppColors.secondaryText)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.top, 4)
                            
                            Divider().background(AppColors.border)
                            
                            ForEach(insights.days) { day in
                                Button(action: {
                                    openDayDetail(for: day.date)
                                }) {
                                    HStack {
                                        Text(dateLabel(for: day.date))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.brand)
                                        Spacer()
                                        Text("\(day.trades)")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.primaryText)
                                            .frame(width: 50, alignment: .trailing)
                                        AppMonetaryText(
                                            Formatters.formatPnL(day.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: day.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                        )
                                        .frame(width: 80, alignment: .trailing)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    },
                    label: {
                        Text("Daily values & trade links (\(insights.tradingDays))")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                )
            }
        }
    }
    
    // MARK: - Weekday Performance Card matching calendar-insights.tsx lines 290-384
    
    @ViewBuilder
    private var weekdayPerformanceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance by weekday")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Closing-day net P&L · \(env.currentCurrency) · Select a row")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                // Highlight box: Most profitable weekday
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Most profitable weekday")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(AppColors.mutedText)
                        
                        if let bestWd = insights.mostProfitableWeekday {
                            HStack(spacing: 8) {
                                Text(bestWd.label)
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                AppMonetaryText(
                                    Formatters.formatPnL(bestWd.netPnl, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.profit
                                )
                            }
                        } else {
                            Text("No profitable weekday yet")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(AppColors.secondaryBackground.opacity(0.4))
                .cornerRadius(6)
                
                // 7 Weekday rows with bidirectional progress bar matching calendar-insights.tsx lines 314-360
                VStack(spacing: 4) {
                    ForEach(insights.weekdays) { wd in
                        weekdayRowView(wd: wd)
                    }
                }
                
                // Selected weekday detailed closing days matching calendar-insights.tsx lines 362-381
                if let selectedIndex = selectedWeekdayIndex,
                   let selected = insights.weekdays.first(where: { $0.index == selectedIndex }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider().background(AppColors.border)
                        
                        Text("\(selected.label) · \(selected.trades) trades across \(selected.days.count) days")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(selected.days) { day in
                                    Button(action: {
                                        openDayDetail(for: day.date)
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(dateLabel(for: day.date))
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.primaryText)
                                            Text("· \(day.trades)t")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppColors.cardBackground)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(AppColors.border, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Weekday Row View with Bidirectional Bar
    
    @ViewBuilder
    private func weekdayRowView(wd: WeekdayPerformance) -> some View {
        let isSelected = selectedWeekdayIndex == wd.index
        let hasTrades = wd.trades > 0
        let pnlDouble = (wd.netPnl as NSDecimalNumber).doubleValue
        let ratio = peakWeekdayAbsPnl > 0 ? (abs(pnlDouble) / peakWeekdayAbsPnl) : 0
        let isProfit = wd.netPnl >= 0
        
        Button(action: {
            guard hasTrades else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedWeekdayIndex = (selectedWeekdayIndex == wd.index) ? nil : wd.index
            }
        }) {
            HStack(spacing: 8) {
                Text(String(wd.label.prefix(3)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hasTrades ? AppColors.primaryText : AppColors.mutedText)
                    .frame(width: 28, alignment: .leading)
                
                // Bidirectional horizontal bar centered at 50%
                GeometryReader { geo in
                    let halfWidth = geo.size.width / 2
                    let barWidth = max(2.0, halfWidth * CGFloat(min(1.0, ratio)))
                    
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.secondaryBackground.opacity(0.3))
                            .frame(height: 6)
                        
                        // Center axis mark
                        Rectangle()
                            .fill(AppColors.border)
                            .frame(width: 1, height: 12)
                            .offset(x: halfWidth)
                        
                        if hasTrades {
                            if isProfit {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.profit)
                                    .frame(width: barWidth, height: 6)
                                    .offset(x: halfWidth)
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.loss)
                                    .frame(width: barWidth, height: 6)
                                    .offset(x: halfWidth - barWidth)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)
                
                // Formatted P&L on right
                if hasTrades {
                    AppMonetaryText(
                        Formatters.formatPnL(wd.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: .system(size: 11, weight: .semibold, design: .monospaced),
                        color: isProfit ? AppColors.profit : AppColors.loss
                    )
                    .frame(width: 76, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(AppColors.mutedText)
                        .frame(width: 76, alignment: .trailing)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isSelected ? AppColors.cardBackground : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? AppColors.border : Color.clear, lineWidth: 1)
            )
        }
        .disabled(!hasTrades)
    }
    
    // MARK: - Metric Card Component
    
    private func metricCard(title: String, value: String, detail: String, valueColor: Color) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundColor(AppColors.secondaryText)
                
                AppMonetaryText(
                    value,
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 17, weight: .semibold),
                    color: valueColor
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Helpers
    
    private func compactMoney(_ value: Decimal) -> String {
        let doubleVal = (value as NSDecimalNumber).doubleValue
        let prefix = value > 0 ? "+" : (value < 0 ? "-" : "")
        let absVal = abs(doubleVal)
        if absVal >= 1_000_000 {
            return String(format: "%@$%.1fM", prefix, absVal / 1_000_000)
        } else if absVal >= 1_000 {
            return String(format: "%@$%.1fk", prefix, absVal / 1_000)
        } else {
            return String(format: "%@$%.0f", prefix, absVal)
        }
    }
    
    private func isDateToday(_ dateString: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = env.currentTimeZone
        let todayStr = f.string(from: Date())
        return todayStr == dateString
    }
    
    private func dayNumber(from dateString: String) -> Int {
        Int(dateString.suffix(2)) ?? 1
    }
    
    private func dateLabel(for dateString: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        inFormatter.timeZone = TimeZone(identifier: "UTC")
        guard let d = inFormatter.date(from: dateString) else { return dateString }
        let outFormatter = DateFormatter()
        outFormatter.locale = Locale(identifier: "en_US")
        outFormatter.dateFormat = "MMM d"
        outFormatter.timeZone = TimeZone(identifier: "UTC")
        return outFormatter.string(from: d)
    }
    
    private func parseDate(from dateKey: String) -> Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = env.currentTimeZone
        return fmt.date(from: dateKey) ?? Date()
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = env.currentTimeZone
        return formatter.string(from: date)
    }
}

// MARK: - DayDetailSheet

public struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    
    public let dateKey: String
    public let stats: DayStats?
    public let trades: [Trade]
    public let note: JournalNote
    public let onSaveNote: (JournalNote) -> Void
    public let onAddTrade: () -> Void
    
    @State private var noteContent: String = ""
    @State private var rating: Int = 0
    
    public init(
        dateKey: String,
        stats: DayStats?,
        trades: [Trade],
        note: JournalNote,
        onSaveNote: @escaping (JournalNote) -> Void,
        onAddTrade: @escaping () -> Void
    ) {
        self.dateKey = dateKey
        self.stats = stats
        self.trades = trades
        self.note = note
        self.onSaveNote = onSaveNote
        self.onAddTrade = onAddTrade
        _noteContent = State(initialValue: note.content)
        _rating = State(initialValue: note.rating ?? 0)
    }
    
    private func formattedDateTitle(_ key: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        inFormatter.timeZone = TimeZone(identifier: "UTC")
        guard let d = inFormatter.date(from: key) else { return key }
        let outFormatter = DateFormatter()
        outFormatter.locale = Locale(identifier: "en_US")
        outFormatter.dateFormat = "EEEE, MMM d, yyyy"
        outFormatter.timeZone = TimeZone(identifier: "UTC")
        return outFormatter.string(from: d)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    noteCard
                    tradesCard
                    actionButtons
                }
                .padding(14)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(formattedDateTitle(dateKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brand)
                }
            }
        }
    }
    
    @ViewBuilder
    private var summaryCard: some View {
        let netPnl = stats?.netPnl ?? .zero
        let isProfit = netPnl >= 0
        let pnlColor = isProfit ? AppColors.profit : AppColors.loss
        let tradeCount = stats?.trades ?? trades.count
        
        AppCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    AppCardHeader("Net P&L")
                    AppMonetaryText(
                        Formatters.formatPnL(netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 22, weight: .bold),
                        color: pnlColor
                    )
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    AppCardHeader("Trades")
                    Text("\(tradeCount)")
                        .font(AppTypography.financialNumber(size: 22, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var noteCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    AppCardHeader("Daily Note")
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 13))
                                .foregroundColor(star <= rating ? .yellow : AppColors.mutedText)
                                .onTapGesture {
                                    rating = (rating == star) ? 0 : star
                                    save()
                                }
                        }
                    }
                }
                
                TextField("Write thoughts or notes for this day...", text: $noteContent, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                    .padding(10)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .onChange(of: noteContent) { _ in
                        save()
                    }
            }
        }
    }
    
    @ViewBuilder
    private var tradesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader("Trades (\(trades.count))")
                
                if trades.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.secondaryText)
                        Text("No closed trades on this day")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(trades) { trade in
                        tradeRow(trade)
                        if trade.id != trades.last?.id {
                            Divider().background(AppColors.border)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func tradeRow(_ trade: Trade) -> some View {
        let isProfit = trade.netPnl >= 0
        let pnlColor = isProfit ? AppColors.profit : AppColors.loss
        
        HStack {
            AppBadge(trade.status.rawValue.uppercased(), color: Formatters.statusColor(trade.status))
            Text(trade.symbol)
                .font(AppTypography.bodyBold)
                .foregroundColor(AppColors.primaryText)
            Spacer()
            AppMonetaryText(
                Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                isPrivate: env.isPrivacyModeEnabled,
                font: AppTypography.financialNumber(size: 13, weight: .semibold),
                color: pnlColor
            )
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onAddTrade) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Trade")
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brandTextOnDark)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.brand)
                .cornerRadius(6)
            }
            
            NavigationLink(destination: DailyJournalDetailView(date: dateKey)) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("Full Journal")
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.cardBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
        }
    }
    
    private func save() {
        var updated = note
        updated.content = noteContent
        updated.rating = rating > 0 ? rating : nil
        updated.updatedAt = Date()
        onSaveNote(updated)
    }
}
