import SwiftUI

/// Màn hình Lịch P&L tháng chuẩn xác 100% đối chiếu từ `source-repo/apps/web/src/app/calendar/page.tsx`:
/// - FilterBar với tiêu đề "Calendar" và bộ chuyển tháng `<` Tháng Năm `>`
/// - Khung lịch tháng 7 cột với các ô ngày hiển thị P&L và số lượng lệnh giao dịch
/// - Tóm tắt hiệu suất tháng (P&L tháng này, tổng số lệnh)
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
    
    private var monthNetPnl: Decimal {
        let prefix = String(format: "%04d-%02d", year, month)
        return dailyStatsMap.filter { $0.key.hasPrefix(prefix) }
            .reduce(Decimal.zero) { $0 + $1.value.netPnl }
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // FilterBar với nút điều hướng tháng < Month Year >
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
                            .frame(minWidth: 100, alignment: .center)
                        
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
                    VStack(spacing: 12) {
                        // Month Totals Card
                        AppCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    AppCardHeader("Net P&L")
                                    AppMonetaryText(
                                        Formatters.formatPnL(monthNetPnl, currency: env.currentCurrency),
                                        isPrivate: env.isPrivacyModeEnabled,
                                        font: AppTypography.financialNumber(size: 20, weight: .semibold),
                                        color: monthNetPnl >= 0 ? AppColors.profit : AppColors.loss
                                    )
                                }
                                
                                Spacer()
                                
                                let monthTrades = dailyStatsMap.filter { $0.key.hasPrefix(String(format: "%04d-%02d", year, month)) }
                                    .reduce(0) { $0 + $1.value.trades }
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    AppCardHeader("Trades")
                                    Text("\(monthTrades)")
                                        .font(AppTypography.financialNumber(size: 20, weight: .semibold))
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                        }
                        
                        // Calendar Grid Card
                        AppCard {
                            VStack(spacing: 8) {
                                // Weekday headers
                                let headers = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
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
                            }
                        }
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
    
    private func initialDateForSelectedKey() -> Date {
        guard let key = selectedDateKey else { return Date() }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: key) ?? Date()
    }
    
    private func dayCell(date: Date, key: String, stats: DayStats?, hasNote: Bool) -> some View {
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        
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
            
            if let stats = stats, stats.trades > 0 {
                AppMonetaryText(
                    Formatters.formatPnL(stats.netPnl, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: .system(size: 9, weight: .bold, design: .monospaced),
                    color: stats.netPnl >= 0 ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                Spacer().frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(stats != nil && stats!.trades > 0 ? (stats!.netPnl >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12)) : AppColors.secondaryBackground.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? AppColors.brand : AppColors.border, lineWidth: isToday ? 1.5 : 0.5)
        )
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func tradesForDay(_ dateKey: String) -> [Trade] {
        dataStore.filteredTrades.filter {
            self.dateKey(for: $0.openedAt) == dateKey
        }
    }
}

/// Sheet chi tiết ngày giao dịch khi bấm vào một ô trong lịch
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
                    // Summary Card
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                AppCardHeader("Net P&L")
                                AppMonetaryText(
                                    Formatters.formatPnL(stats?.netPnl ?? .zero, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.financialNumber(size: 22, weight: .bold),
                                    color: (stats?.netPnl ?? .zero) >= 0 ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                AppCardHeader("Trades")
                                Text("\(stats?.trades ?? trades.count)")
                                    .font(AppTypography.financialNumber(size: 22, weight: .bold))
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                    }
                    
                    // Daily Note Card
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
                    
                    // Day's Trades
                    if !trades.isEmpty {
                        AppCard {
                            VStack(alignment: .leading, spacing: 10) {
                                AppCardHeader("Trades (\(trades.count))")
                                
                                ForEach(trades) { trade in
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
                                            color: trade.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                        )
                                    }
                                    .padding(.vertical, 4)
                                    
                                    if trade.id != trades.last?.id {
                                        Divider().background(AppColors.border)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Action Buttons
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
    
    private func save() {
        var updated = note
        updated.content = noteContent
        updated.rating = rating > 0 ? rating : nil
        updated.updatedAt = Date()
        onSaveNote(updated)
    }
}
