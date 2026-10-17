import SwiftUI

/// Monthly P&L Calendar view matching `source-repo/apps/web/src/app/calendar/page.tsx`,
/// `components/calendar-pnl.tsx`, and `components/calendar-insights.tsx`:
/// - FilterBar with Month navigator (< Month Year >)
/// - 7-column calendar grid with daily net P&L and trade counts
/// - Trading day summary footer
/// - Full Performance Insights breakdown: Net P&L, Avg Daily P&L, Win Rate, Closed Trades,
///   Best/Worst Day, Avg Green/Red Day, Day Consistency
public struct JournalCalendarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var currentMonth: Date = Date()
    @State private var selectedDateKey: String? = nil
    @State private var showDayDetailSheet: Bool = false
    @State private var showAddTradeForDate: Bool = false
    
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
    
    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }
        
        let firstDay = monthInterval.start
        let leadingSpaces = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        let numberOfDays = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 30
        
        var days: [Date?] = Array(repeating: nil, count: leadingSpaces)
        for day in 1...numberOfDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        while days.count % 7 != 0 {
            days.append(nil)
        }
        
        return days
    }
    
    private var dailyStatsMap: [String: DayStats] {
        let overview = FinancialMetricsEngine.computeOverview(
            trades: dataStore.filteredTrades,
            timeZone: env.currentTimeZone
        )
        var map: [String: DayStats] = [:]
        for d in overview.days {
            map[d.date] = d
        }
        return map
    }
    
    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        return formatter.string(from: date)
    }
    
    private var monthDaysList: [DayStats] {
        dailyStatsMap
            .filter { $0.key.hasPrefix(monthPrefix) && $0.value.trades > 0 }
            .map { $0.value }
            .sorted { $0.date < $1.date }
    }
    
    private var monthTradingDays: Int {
        monthDaysList.count
    }
    
    private var monthWinningDays: Int {
        monthDaysList.filter { $0.netPnl > 0 }.count
    }
    
    private var monthLosingDays: Int {
        monthDaysList.filter { $0.netPnl < 0 }.count
    }
    
    private var monthFlatDays: Int {
        monthDaysList.filter { $0.netPnl == 0 }.count
    }
    
    private var monthNetPnl: Decimal {
        monthDaysList.reduce(Decimal.zero) { $0 + $1.netPnl }
    }
    
    private var monthTradesCount: Int {
        monthDaysList.reduce(0) { $0 + $1.trades }
    }
    
    private var monthWinsCount: Int {
        monthDaysList.reduce(0) { $0 + $1.wins }
    }
    
    private var monthLossesCount: Int {
        monthDaysList.reduce(0) { $0 + $1.losses }
    }
    
    private var monthBreakevensCount: Int {
        monthDaysList.reduce(0) { $0 + $1.breakevens }
    }
    
    private var avgDailyPnl: Decimal {
        monthTradingDays > 0 ? (monthNetPnl / Decimal(monthTradingDays)) : .zero
    }
    
    private var monthWinRate: Double {
        monthTradesCount > 0 ? (Double(monthWinsCount) / Double(monthTradesCount)) * 100 : 0
    }
    
    private var profitableDayRate: Double {
        monthTradingDays > 0 ? (Double(monthWinningDays) / Double(monthTradingDays)) * 100 : 0
    }
    
    private var bestDay: DayStats? {
        monthDaysList.max(by: { $0.netPnl < $1.netPnl })
    }
    
    private var worstDay: DayStats? {
        monthDaysList.min(by: { $0.netPnl < $1.netPnl })
    }
    
    private var avgGreenDay: Decimal {
        let greenDays = monthDaysList.filter { $0.netPnl > 0 }
        guard !greenDays.isEmpty else { return .zero }
        let total = greenDays.reduce(Decimal.zero) { $0 + $1.netPnl }
        return total / Decimal(greenDays.count)
    }
    
    private var avgRedDay: Decimal {
        let redDays = monthDaysList.filter { $0.netPnl < 0 }
        guard !redDays.isEmpty else { return .zero }
        let total = redDays.reduce(Decimal.zero) { $0 + $1.netPnl }
        return total / Decimal(redDays.count)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // FilterBar with Month navigator matching calendar/page.tsx
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
                        
                        Text(monthTitle(for: currentMonth))
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                            .frame(minWidth: 120, alignment: .center)
                        
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
                    }
                }
                
                ScrollView {
                    VStack(spacing: 14) {
                        // Monthly Calendar Card
                        calendarGridCard
                        
                        // Performance Insights Section matching calendar-insights.tsx
                        performanceInsightsSection
                    }
                    .padding(14)
                }
                .background(AppColors.background)
            }
            .sheet(isPresented: $showDayDetailSheet) {
                if let key = selectedDateKey {
                    DayDetailSheet(
                        dateKey: key,
                        stats: dailyStatsMap[key],
                        trades: tradesForDay(key),
                        note: dataStore.calendarNotes[key] ?? JournalNote(date: key),
                        onSaveNote: { updatedNote in
                            dataStore.saveCalendarNote(updatedNote)
                        },
                        onAddTrade: {
                            showDayDetailSheet = false
                            showAddTradeForDate = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showAddTradeForDate) {
                AddTradeSheet(initialDate: initialDateForSelectedKey())
            }
        }
    }
    
    @ViewBuilder
    private var calendarGridCard: some View {
        let headers = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        AppCard {
            VStack(spacing: 10) {
                // Weekday headers
                HStack(spacing: 4) {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(AppTypography.cardTitle)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                Divider().background(AppColors.border)
                
                // Day cells grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(0..<daysInMonth.count, id: \.self) { index in
                        if let date = daysInMonth[index] {
                            let key = dateKey(for: date)
                            let stats = dailyStatsMap[key]
                            let hasNote = dataStore.calendarNotes[key] != nil
                            
                            dayCell(date: date, key: key, stats: stats, hasNote: hasNote)
                                .onTapGesture {
                                    selectedDateKey = key
                                    showDayDetailSheet = true
                                }
                        } else {
                            Color.clear
                                .frame(height: 52)
                        }
                    }
                }
                
                Divider().background(AppColors.border)
                
                // Calendar bottom summary matching calendar-pnl.tsx line 71-83
                HStack {
                    Text("\(monthTradingDays) trading days · \(monthWinningDays) green")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("Month:")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        AppMonetaryText(
                            Formatters.formatPnL(monthNetPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.captionBold,
                            color: monthNetPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func dayCell(date: Date, key: String, stats: DayStats?, hasNote: Bool) -> some View {
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let traded = (stats?.trades ?? 0) > 0
        let pnl = stats?.netPnl ?? .zero
        let isProfit = pnl >= 0
        
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(AppTypography.captionBold)
                    .foregroundColor(isToday ? AppColors.brand : AppColors.primaryText)
                
                if hasNote {
                    Circle()
                        .fill(AppColors.brand)
                        .frame(width: 4, height: 4)
                }
            }
            
            if traded {
                AppMonetaryText(
                    Formatters.formatPnL(pnl, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: .system(size: 9, weight: .bold, design: .monospaced),
                    color: isProfit ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                
                Text("\(stats!.trades) trade\(stats!.trades == 1 ? "" : "s")")
                    .font(.system(size: 7, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
            } else {
                Spacer().frame(height: 14)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(traded ? (isProfit ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12)) : AppColors.secondaryBackground.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? AppColors.brand : AppColors.border, lineWidth: isToday ? 1.5 : 0.5)
        )
    }
    
    @ViewBuilder
    private var performanceInsightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance insights")
                    .font(AppTypography.subheading)
                    .foregroundColor(AppColors.primaryText)
                
                Text("Visible month × active filters · Closed trades, after fees")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 2)
            
            if monthTradingDays == 0 {
                AppCard {
                    VStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("No closed trades in this view")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Choose another month or adjust your account and filters. Open positions and days without trades aren't included.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                // 4-card metric grid matching calendar-insights.tsx line 136-168
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricCard(
                        title: "Net P&L",
                        value: Formatters.formatPnL(monthNetPnl, currency: env.currentCurrency),
                        detail: "\(monthTradingDays) trading day\(monthTradingDays == 1 ? "" : "s")",
                        valueColor: monthNetPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    metricCard(
                        title: "Average daily P&L",
                        value: Formatters.formatPnL(avgDailyPnl, currency: env.currentCurrency),
                        detail: "Per active trading day",
                        valueColor: avgDailyPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    metricCard(
                        title: "Trade win rate",
                        value: String(format: "%.1f%%", monthWinRate),
                        detail: "\(monthWinsCount)W · \(monthLossesCount)L · \(monthBreakevensCount)BE",
                        valueColor: AppColors.primaryText
                    )
                    
                    metricCard(
                        title: "Total closed trades",
                        value: "\(monthTradesCount)",
                        detail: "Round-trip trades",
                        valueColor: AppColors.primaryText
                    )
                }
                
                // Extrema & Averages matching calendar-insights.tsx line 171-218
                VStack(spacing: 10) {
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
                                if let best = bestDay {
                                    HStack(spacing: 6) {
                                        AppMonetaryText(
                                            Formatters.formatPnL(best.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: AppColors.profit
                                        )
                                        Text(best.date)
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
                                if let worst = worstDay {
                                    HStack(spacing: 6) {
                                        AppMonetaryText(
                                            Formatters.formatPnL(worst.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: AppColors.loss
                                        )
                                        Text(worst.date)
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                } else {
                                    Text("—").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Average green & red day")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                Text("\(monthWinningDays) profitable days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                AppMonetaryText(
                                    Formatters.formatPnL(avgGreenDay, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.profit
                                )
                            }
                            
                            HStack {
                                Text("\(monthLosingDays) losing days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                AppMonetaryText(
                                    Formatters.formatPnL(avgRedDay, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.loss
                                )
                            }
                        }
                    }
                    
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Day consistency")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                Text("\(monthWinningDays) positive · \(monthLosingDays) negative · \(monthFlatDays) flat")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%.1f%%", profitableDayRate))
                                .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                                .foregroundColor(profitableDayRate >= 50 ? AppColors.profit : AppColors.secondaryText)
                        }
                    }
                }
            }
        }
    }
    
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
    
    private func initialDateForSelectedKey() -> Date {
        guard let key = selectedDateKey else { return Date() }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: key) ?? Date()
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
        return formatter.string(from: date)
    }
    
    private func tradesForDay(_ dateKey: String) -> [Trade] {
        dataStore.filteredTrades.filter {
            self.dateKey(for: $0.openedAt) == dateKey
        }
    }
}

/// Sheet presenting trade details, day note, and quick actions for a selected calendar date
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
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    noteCard
                    if !trades.isEmpty {
                        tradesCard
                    }
                    actionButtons
                }
                .padding(14)
            }
            .background(AppColors.background)
            .navigationTitle(dateKey)
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
                
                ForEach(trades) { trade in
                    tradeRow(trade)
                    if trade.id != trades.last?.id {
                        Divider().background(AppColors.border)
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
