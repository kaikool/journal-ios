import SwiftUI
import Charts


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
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var currentMonth: Date = Date()
    @State private var selectedDayContext: DayDetailContext? = nil
    @State var selectedWeekdayIndex: Int? = nil
    @State private var addTradeDate: Date? = nil
    @State private var showAddTradeSheet: Bool = false
    @State var showDailyTable: Bool = false
    @State var selectedTrendDate: String? = nil
    
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
    
    private struct CalendarSnapshot {
        let overview: (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats])
        let dailyStatsMap: [String: DayStats]
        let tradesByDateMap: [String: [Trade]]
        let calendarMonth: CalendarMonth
        let insights: CalendarInsights
        let maxAbsPnl: Double
        let peakWeekdayAbsPnl: Double
    }
    
    @State private var cache = CalendarCache()
    
    @MainActor
    private final class CalendarCache {
        var lastKey: String = ""
        var lastSnapshot: CalendarSnapshot? = nil
    }
    
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private func computeSnapshot() -> CalendarSnapshot {
        let ov = FinancialMetricsEngine.computeOverview(
            trades: dataStore.filteredTrades,
            timeZone: env.currentTimeZone
        )
        Self.isoDateFormatter.timeZone = env.currentTimeZone
        let f = Self.isoDateFormatter
        
        var dayMap: [String: DayStats] = [:]
        for d in ov.days {
            dayMap[d.date] = d
        }
        
        var tradesMap: [String: [Trade]] = [:]
        for trade in dataStore.filteredTrades {
            let key = f.string(from: trade.closedAt ?? trade.openedAt)
            tradesMap[key, default: []].append(trade)
        }
        
        let calMonth = AggregateEngine.calendarMonthFromDays(
            dayStats: ov.days,
            year: year,
            month: month
        )
        
        let ins = CalendarInsightsEngine.calendarInsights(calendar: calMonth)
        
        let maxVal = calMonth.weeks
            .flatMap { $0.days }
            .compactMap { $0 }
            .map { abs(($0.netPnl as NSDecimalNumber).doubleValue) }
            .max() ?? 1.0
        let maxAbs = max(1.0, maxVal)
        
        let peak = ins.weekdays.map { abs(($0.netPnl as NSDecimalNumber).doubleValue) }.max() ?? 1.0
        let peakAbs = max(1.0, peak)
        
        return CalendarSnapshot(
            overview: ov,
            dailyStatsMap: dayMap,
            tradesByDateMap: tradesMap,
            calendarMonth: calMonth,
            insights: ins,
            maxAbsPnl: maxAbs,
            peakWeekdayAbsPnl: peakAbs
        )
    }
    
    private var snapshot: CalendarSnapshot {
        let key = "\(year)_\(month)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)_\(env.currentTimeZone.identifier)"
        if cache.lastKey == key, let cached = cache.lastSnapshot {
            return cached
        }
        let fresh = computeSnapshot()
        cache.lastKey = key
        cache.lastSnapshot = fresh
        return fresh
    }
    
    private var overview: (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        snapshot.overview
    }
    
    private var dateKeyFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = env.currentTimeZone
        return f
    }
    
    private var dailyStatsMap: [String: DayStats] {
        snapshot.dailyStatsMap
    }
    
    private var tradesByDateMap: [String: [Trade]] {
        snapshot.tradesByDateMap
    }
    
    private var calendarMonth: CalendarMonth {
        snapshot.calendarMonth
    }
    
    var insights: CalendarInsights {
        snapshot.insights
    }
    
    private var maxAbsPnl: Double {
        snapshot.maxAbsPnl
    }
    
    private var peakWeekdayAbsPnl: Double {
        snapshot.peakWeekdayAbsPnl
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
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            changeMonth(by: -1)
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .frame(width: 30, height: 30)
                                .background(AppColors.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                                    )
                                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                        .accessibilityLabel("Previous month")
                        
                        Text(monthTitle(for: currentMonth))
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                            .frame(minWidth: 124, alignment: .center)
                        
                        Button(action: {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            changeMonth(by: 1)
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .frame(width: 30, height: 30)
                                .background(AppColors.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                                    )
                                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(ApplePressableButtonStyle())
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
    
    func dateLabel(for dateString: String) -> String {
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
