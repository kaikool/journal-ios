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
    @ObservedObject private var ffService = ForexFactoryService.shared
    
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
        let eventsByDateKey: [String: [ForexFactoryEvent]]
    }
    
    @MainActor
    private final class CalendarCache {
        static let shared = CalendarCache()
        var lastKey: String = ""
        var lastSnapshot: CalendarSnapshot? = nil
    }
    
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private var todayDateKey: String {
        Self.isoDateFormatter.timeZone = env.currentTimeZone
        return Self.isoDateFormatter.string(from: Date())
    }
    
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
        
        var eventsMap: [String: [ForexFactoryEvent]] = [:]
        for e in ffService.usdEvents {
            let k = e.dateKey
            if !k.isEmpty {
                eventsMap[k, default: []].append(e)
            }
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
            peakWeekdayAbsPnl: peakAbs,
            eventsByDateKey: eventsMap
        )
    }
    
    private var snapshot: CalendarSnapshot {
        let key = "\(year)_\(month)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)_\(ffService.usdEvents.count)_\(env.currentTimeZone.identifier)"
        if CalendarCache.shared.lastKey == key, let cached = CalendarCache.shared.lastSnapshot {
            return cached
        }
        let fresh = computeSnapshot()
        CalendarCache.shared.lastKey = key
        CalendarCache.shared.lastSnapshot = fresh
        return fresh
    }
    
    private var overview: (metrics: TradeMetrics, curve: [EquityPoint], days: [DayStats]) {
        snapshot.overview
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
    
    internal var peakWeekdayAbsPnl: Double {
        snapshot.peakWeekdayAbsPnl
    }
    
    private var eventsByDateKey: [String: [ForexFactoryEvent]] {
        snapshot.eventsByDateKey
    }
    
    private var availableCurrencies: [String] {
        if dataStore.selectedAccountId != "all" && !dataStore.selectedAccountId.isEmpty {
            if let sel = dataStore.selectedAccount {
                return [sel.currency.uppercased()]
            }
        }
        let tradeAccountIds = Set(dataStore.filteredTrades.map(\.accountId))
        let activeCurrencies = dataStore.accounts.filter { acc in
            tradeAccountIds.contains(acc.id) ||
            tradeAccountIds.contains(acc.id.cleanAccountId) ||
            tradeAccountIds.contains(acc.id.the5ersCanonicalId) ||
            tradeAccountIds.contains(acc.id.ctraderCanonicalId) ||
            tradeAccountIds.contains(acc.id.exnessCanonicalId)
        }.map { $0.currency.uppercased() }
        
        let unique = Array(Set(activeCurrencies)).sorted()
        if !unique.isEmpty { return unique }
        return dataStore.availableCurrencies
    }
    
    private var monthNavigatorBar: some View {
        HStack {
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                changeMonth(by: -1)
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 32, height: 32)
                    .background(AppColors.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.border.opacity(0.6), lineWidth: 0.5))
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Previous month")
            
            Spacer()
            
            // Month Title in a Sleek Pill Pod
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                Text(monthTitle(for: currentMonth))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(AppColors.cardBackground.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.6)
            )
            
            Spacer()
            
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                changeMonth(by: 1)
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 32, height: 32)
                    .background(AppColors.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.border.opacity(0.6), lineWidth: 0.5))
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Multi-currency notice matching calendar/page.tsx line 74
                if availableCurrencies.count > 1 && dataStore.selectedAccountId == "all" && !dataStore.currencyConversion.enabled {
                    currencyNoticeBanner
                }
                
                // Monthly Calendar Card with 8 columns matching calendar-pnl.tsx
                calendarCard
                
                // Performance Insights Section matching calendar-insights.tsx
                performanceInsightsSection
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            monthNavigatorBar
        }
        .background(AppColors.background)
        .task {
            await ForexFactoryService.shared.fetchEventsIfNeeded()
        }
        .refreshable {
            await Task {
                await ForexFactoryService.shared.fetchEvents()
                await SyncManager.shared.performQuickSync()
            }.value
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
    
    // MARK: - Instant Day Selection Handler
    
    internal func openDayDetail(for dateKey: String) {
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
        let isToday = day.date == todayDateKey
        let traded = day.trades > 0
        let pnlDouble = (day.netPnl as NSDecimalNumber).doubleValue
        let intensity = traded ? min(1.0, 0.12 + 0.38 * (abs(pnlDouble) / maxAbsPnl)) : 0
        let isProfit = day.netPnl >= 0
        let hasNote = dataStore.calendarNotes[day.date] != nil
        let dayNum = dayNumber(from: day.date)
        let dayEvents = eventsByDateKey[day.date] ?? []
        let hasNews = !dayEvents.isEmpty
        let hasHighImpactNews = dayEvents.contains { $0.impact == .high }
        
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
                
                if hasNews {
                    Circle()
                        .fill(hasHighImpactNews ? AppColors.loss : AppColors.warning)
                        .frame(width: 3.5, height: 3.5)
                }
            }
            
            if traded {
                AppMonetaryText(
                    compactMoney(day.netPnl),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.number(9, weight: .bold),
                    color: isProfit ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                
                Text("\(day.trades)t")
                    .font(.system(size: 8.5, weight: .medium))
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
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppColors.mutedText)
            
            if week.weekTrades > 0 {
                AppMonetaryText(
                    compactMoney(week.weekNetPnl),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.number(9, weight: .bold),
                    color: week.weekNetPnl >= 0 ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                
                Text("\(week.weekTrades)t")
                    .font(.system(size: 8.5, weight: .medium))
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
    
    private static let labelInFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let labelOutFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    
    private func compactMoney(_ value: Decimal) -> String {
        Formatters.compactCurrency(value, currency: env.currentCurrency)
    }
    
    private func isDateToday(_ dateString: String) -> Bool {
        todayDateKey == dateString
    }
    
    private func dayNumber(from dateString: String) -> Int {
        Int(dateString.suffix(2)) ?? 1
    }
    
    func dateLabel(for dateString: String) -> String {
        guard let d = Self.labelInFormatter.date(from: dateString) else { return dateString }
        return Self.labelOutFormatter.string(from: d)
    }
    
    private func parseDate(from dateKey: String) -> Date {
        Self.isoDateFormatter.timeZone = env.currentTimeZone
        return Self.isoDateFormatter.date(from: dateKey) ?? Date()
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func monthTitle(for date: Date) -> String {
        Self.monthTitleFormatter.timeZone = env.currentTimeZone
        return Self.monthTitleFormatter.string(from: date)
    }
}
