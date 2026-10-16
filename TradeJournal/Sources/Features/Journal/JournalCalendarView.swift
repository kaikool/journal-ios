import SwiftUI

public struct JournalCalendarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var currentMonth: Date = Date()
    @State private var selectedDateKey: String? = nil
    @State private var showDayDetailSheet: Bool = false
    @State private var journalNotes: [String: JournalNote] = [:] // key: YYYY-MM-DD
    @State private var selectedJournalSection: JournalSection = .calendar
    
    public enum JournalSection: String, CaseIterable, Identifiable {
        case calendar = "Lịch P&L"
        case playbooks = "Playbooks"
        
        public var id: String { rawValue }
    }
    
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
                Picker("Mục nhật ký", selection: $selectedJournalSection) {
                    ForEach(JournalSection.allCases) { sec in
                        Text(sec.rawValue).tag(sec)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                if selectedJournalSection == .playbooks {
                    PlaybooksView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Month Navigation & Totals Card
                    AppCard {
                        VStack(spacing: 12) {
                            HStack {
                                Button(action: { changeMonth(by: -1) }) {
                                    Image(systemName: "chevron.left")
                                        .font(.headline)
                                        .foregroundColor(AppColors.primaryText)
                                }
                                
                                Spacer()
                                
                                Text(monthTitle(for: currentMonth))
                                    .font(AppTypography.headline)
                                
                                Spacer()
                                
                                Button(action: { changeMonth(by: 1) }) {
                                    Image(systemName: "chevron.right")
                                        .font(.headline)
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                            
                            Divider().background(AppColors.border)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("P&L Tháng này")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatPnL(monthNetPnl, currency: env.currentCurrency))
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(Formatters.pnlColor(monthNetPnl))
                                }
                                
                                Spacer()
                                
                                let monthTrades = dailyStatsMap.filter { $0.key.hasPrefix(String(format: "%04d-%02d", year, month)) }
                                    .reduce(0) { $0 + $1.value.trades }
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Tổng lệnh")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text("\(monthTrades)")
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                        }
                    }
                    
                    // Calendar Grid Card
                    AppCard {
                        VStack(spacing: 10) {
                            // Weekday headers
                            let headers = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
                            HStack(spacing: 4) {
                                ForEach(headers, id: \.self) { header in
                                    Text(header)
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            // Day cells grid
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                                ForEach(0..<daysInMonth.count, id: \.self) { index in
                                    if let date = daysInMonth[index] {
                                        let key = dateKey(for: date)
                                        let stats = dailyStatsMap[key]
                                        let hasNote = journalNotes[key] != nil
                                        
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
                    
                    // Month summary notes or recent entries
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "pencil.and.list.clipboard")
                                    .foregroundColor(AppColors.accent)
                                Text("Hướng dẫn nhật ký")
                                    .font(AppTypography.headline)
                            }
                            Text("Chạm vào từng ngày giao dịch trên lịch để ghi chú tâm lý (mindset), đánh giá kỷ luật (1-5 sao) và xem chi tiết các lệnh khớp.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                .padding()
            }
            }
            .navigationTitle("Nhật Ký")
            .background(AppColors.background)
            .sheet(isPresented: $showDayDetailSheet) {
                if let key = selectedDateKey {
                    DayDetailSheet(
                        dateKey: key,
                        stats: dailyStatsMap[key],
                        trades: tradesForDay(key),
                        note: journalNotes[key] ?? JournalNote(date: key),
                        onSaveNote: { updatedNote in
                            journalNotes[key] = updatedNote
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Views & Functions
    
    private func dayCell(date: Date, key: String, stats: DayStats?, hasNote: Bool) -> some View {
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(AppTypography.captionBold)
                    .foregroundColor(isToday ? AppColors.accent : AppColors.primaryText)
                
                if hasNote {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 4, height: 4)
                }
            }
            
            if let stats = stats, stats.trades > 0 {
                Text(Formatters.formatPnL(stats.netPnl, currency: env.currentCurrency))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Formatters.pnlColor(stats.netPnl))
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
                .stroke(isToday ? AppColors.accent : AppColors.border.opacity(0.4), lineWidth: isToday ? 1.5 : 0.5)
        )
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private func tradesForDay(_ dateKey: String) -> [Trade] {
        dataStore.filteredTrades.filter {
            self.dateKey(for: $0.openedAt) == dateKey
        }
    }
}

// MARK: - Day Detail Sheet

public struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    
    let dateKey: String
    let stats: DayStats?
    let trades: [Trade]
    
    @State private var note: JournalNote
    var onSaveNote: (JournalNote) -> Void
    
    public init(dateKey: String, stats: DayStats?, trades: [Trade], note: JournalNote, onSaveNote: @escaping (JournalNote) -> Void) {
        self.dateKey = dateKey
        self.stats = stats
        self.trades = trades
        self._note = State(initialValue: note)
        self.onSaveNote = onSaveNote
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Day Stats Header
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lãi/Lỗ Ngày")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatPnL(stats?.netPnl ?? 0, currency: env.currentCurrency))
                                    .font(AppTypography.headline.bold())
                                    .foregroundColor(Formatters.pnlColor(stats?.netPnl ?? 0))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Số Lệnh: \(trades.count)")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                if let stats = stats, stats.trades > 0 {
                                    Text("Thắng: \(stats.wins) / Thua: \(stats.losses)")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                        }
                    }
                    
                    // Daily Review & Notes
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ghi chú & Tâm lý ngày")
                                .font(AppTypography.headline)
                            
                            // Rating stars
                            HStack {
                                Text("Kỷ luật:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= (note.rating ?? 0) ? "star.fill" : "star")
                                        .foregroundColor(star <= (note.rating ?? 0) ? .yellow : AppColors.secondaryText)
                                        .onTapGesture {
                                            note.rating = star
                                        }
                                }
                            }
                            
                            // Notes Text Editor
                            TextEditor(text: $note.content)
                                .frame(height: 100)
                                .padding(8)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        }
                    }
                    
                    // Trades on this day
                    if !trades.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Các lệnh đã thực hiện (\(trades.count))")
                                .font(AppTypography.headline)
                                .padding(.horizontal, 4)
                            
                            ForEach(trades) { trade in
                                AppCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(trade.symbol)
                                                    .font(AppTypography.subheadlineBold)
                                                AppBadge(
                                                    text: trade.direction.rawValue.uppercased(),
                                                    color: trade.direction == .long ? AppColors.profit : AppColors.loss
                                                )
                                            }
                                            Text("KL: \(trade.quantity) • Giá vào: \(trade.avgEntry)")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                                                .font(AppTypography.subheadlineBold)
                                                .foregroundColor(Formatters.pnlColor(trade.netPnl))
                                            Text(trade.status.rawValue.capitalized)
                                                .font(AppTypography.caption)
                                                .foregroundColor(Formatters.pnlColor(trade.netPnl))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(dateKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        note.updatedAt = Date()
                        onSaveNote(note)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}
