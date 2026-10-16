import SwiftUI
import Charts

/// Model đại diện cho một ngày giao dịch trong danh sách nhật ký ngày
/// Port 1:1 từ `JournalDay` trong `source-repo/apps/web/src/app/journal/page.tsx`
public struct JournalDaySummary: Identifiable {
    public var id: String { date }
    public let date: String
    public let weekday: String
    public let tradesCount: Int
    public let winsCount: Int
    public let lossesCount: Int
    public let netPnl: Decimal
    public let winRate: Double?
    public let hasNote: Bool
    public let notePreview: String
}

/// Màn hình danh sách nhật ký giao dịch hàng ngày
/// Port 1:1 từ `source-repo/apps/web/src/app/journal/page.tsx`
public struct DailyJournalListView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var searchText: String = ""
    @State private var navigateToToday: Bool = false
    
    public init() {}
    
    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        return formatter.string(from: Date())
    }
    
    private var daysList: [JournalDaySummary] {
        let trades = dataStore.filteredTrades
        let calendar = Calendar.current
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.timeZone = env.currentTimeZone
        
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"
        weekdayFormatter.locale = Locale(identifier: "vi_VN")
        
        // Thu thập toàn bộ ngày có lệnh hoặc có ghi chú
        var dateMap: [String: [Trade]] = [:]
        for t in trades {
            let key = t.closedAt != nil ? isoFormatter.string(from: t.closedAt!) : isoFormatter.string(from: t.openedAt)
            dateMap[key, default: []].append(t)
        }
        
        // Thêm các ngày có ghi chú
        for dateKey in dataStore.journalDays.keys {
            if dateMap[dateKey] == nil {
                dateMap[dateKey] = []
            }
        }
        for (dateKey, note) in dataStore.calendarNotes {
            if !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if dateMap[dateKey] == nil {
                    dateMap[dateKey] = []
                }
            }
        }
        
        // Đảm bảo có ngày hôm nay trong danh sách
        if dateMap[todayKey] == nil {
            dateMap[todayKey] = []
        }
        
        let sortedDates = dateMap.keys.sorted(by: >)
        
        return sortedDates.compactMap { dKey -> JournalDaySummary? in
            let dayTrades = dateMap[dKey] ?? []
            let dateObj = isoFormatter.date(from: dKey) ?? Date()
            let weekday = weekdayFormatter.string(from: dateObj).capitalized
            
            let closed = dayTrades.filter { $0.status != .open }
            let net = closed.reduce(Decimal.zero) { $0 + $1.netPnl }
            let wins = closed.filter { $0.netPnl > 0 }.count
            let losses = closed.filter { $0.netPnl < 0 }.count
            let winRate: Double? = closed.isEmpty ? nil : Double(wins) / Double(closed.count)
            
            let noteContent = dataStore.getJournalDayNote(date: dKey)
            let calNote = dataStore.calendarNotes[dKey]?.content ?? ""
            let combinedNote = !noteContent.isEmpty ? noteContent : calNote
            let hasNote = !combinedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            if !searchText.isEmpty {
                let matches = dKey.contains(searchText) || weekday.localizedCaseInsensitiveContains(searchText) || combinedNote.localizedCaseInsensitiveContains(searchText)
                if !matches { return nil }
            }
            
            return JournalDaySummary(
                date: dKey,
                weekday: weekday,
                tradesCount: closed.count,
                winsCount: wins,
                lossesCount: losses,
                netPnl: net,
                winRate: winRate,
                hasNote: hasNote,
                notePreview: String(combinedNote.prefix(80))
            )
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Thanh công cụ đầu trang với nút "Hôm nay của tôi" (View my day)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nhật Ký Ngày")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.primaryText)
                            Text("Tổng hợp diễn biến, P&L và bài học theo từng ngày giao dịch")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        NavigationLink(destination: DailyJournalDetailView(date: todayKey)) {
                            HStack(spacing: 6) {
                                Image(systemName: "sun.max.fill")
                                Text("Hôm nay của tôi")
                            }
                            .font(AppTypography.captionBold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Ô tìm kiếm ngày
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppColors.secondaryText)
                        TextField("Tìm theo ngày (YYYY-MM-DD), thứ, ghi chú...", text: $searchText)
                            .font(AppTypography.body)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
                    
                    // Danh sách thẻ ngày
                    if daysList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            Text("Chưa có ngày giao dịch nào")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            Text("Hãy nhập lệnh hoặc ghi chú đầu tiên để bắt đầu lưu lại nhật ký hành trình.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(daysList) { day in
                                NavigationLink(destination: DailyJournalDetailView(date: day.date)) {
                                    dayRowCard(day)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @ViewBuilder
    private func dayRowCard(_ day: JournalDaySummary) -> some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                // Cột ngày & thứ
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date)
                        .font(AppTypography.bodyBold)
                        .foregroundColor(day.date == todayKey ? AppColors.accent : AppColors.primaryText)
                    Text(day.weekday)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(width: 95, alignment: .leading)
                
                Divider()
                    .frame(height: 36)
                
                // Cột PnL & chỉ số
                if day.tradesCount > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(day.netPnl >= 0 ? "+\(Formatters.currency(day.netPnl))" : Formatters.currency(day.netPnl))
                                .font(AppTypography.bodyBold)
                                .foregroundColor(day.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                            
                            Text("(\(day.tradesCount) lệnh)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        HStack(spacing: 8) {
                            if let wr = day.winRate {
                                Text("\(Int(wr * 100))% win")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            Text("\(day.winsCount)W / \(day.lossesCount)L")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                } else {
                    Text("Không có lệnh giao dịch")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                // Huy hiệu có ghi chú
                if day.hasNote {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                        Text("Ghi chú")
                            .font(AppTypography.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.accent.opacity(0.12))
                    .foregroundColor(AppColors.accent)
                    .clipShape(Capsule())
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.5))
            }
        }
    }
}

/// Màn hình chi tiết một ngày giao dịch
/// Port 1:1 từ `source-repo/apps/web/src/app/journal/[date]/page.tsx`
public struct DailyJournalDetailView: View {
    public let date: String
    
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var noteText: String = ""
    @State private var isSaving: Bool = false
    @State private var saveStatusMessage: String = ""
    @State private var isGeneratingAiRecap: Bool = false
    @State private var aiErrorMessage: String? = nil
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    
    public init(date: String) {
        self.date = date
    }
    
    private var dayTrades: [Trade] {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.timeZone = env.currentTimeZone
        
        return dataStore.filteredTrades.filter { t in
            let closeKey = t.closedAt != nil ? isoFormatter.string(from: t.closedAt!) : nil
            let openKey = isoFormatter.string(from: t.openedAt)
            return closeKey == date || (t.status == .open && openKey == date)
        }.sorted { ($0.closedAt ?? $0.openedAt) < ($1.closedAt ?? $1.openedAt) }
    }
    
    private var metrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(trades: dayTrades)
    }
    
    private var intradayPoints: [(timeStr: String, cumPnl: Decimal)] {
        var points: [(timeStr: String, cumPnl: Decimal)] = []
        var running: Decimal = 0
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = env.currentTimeZone
        
        let closed = dayTrades.filter { $0.closedAt != nil }
        for t in closed {
            running += t.netPnl
            let tStr = timeFormatter.string(from: t.closedAt!)
            points.append((timeStr: tStr, cumPnl: running))
        }
        return points
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header & Action Bar
                dayHeaderSection
                
                // Card 1: Day stats KPI grid (Port 1:1 từ Card Day stats)
                dayStatsCard
                
                // Card 2: Biểu đồ Intraday cumulative net P&L
                if !intradayPoints.isEmpty {
                    intradayChartCard
                }
                
                // Card 3: Danh sách các lệnh trong ngày (Trades list)
                if !dayTrades.isEmpty {
                    dayTradesCard
                }
                
                // Card 4: Day note editor, Voice Note & AI Recap
                dayNoteCard
                
                // Card 5: Tệp đính kèm & Ảnh biểu đồ của ngày
                AttachmentsSectionView(ownerType: "day", ownerId: date, title: "Tệp đính kèm & Biểu đồ ngày \(date)")
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Nhật ký · \(date)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    prepareExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ReviewExportModal(title: "Nhật ký ngày · \(date)", exportText: exportText)
        }
        .onAppear {
            loadNote()
        }
    }
    
    // MARK: - Subviews
    
    private var dayHeaderSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date)
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.primaryText)
                Text(weekdayLabel)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            // Huy hiệu tổng kết P&L nhanh
            VStack(alignment: .trailing, spacing: 2) {
                Text(metrics.netPnl >= 0 ? "+\(Formatters.currency(metrics.netPnl))" : Formatters.currency(metrics.netPnl))
                    .font(AppTypography.title3)
                    .foregroundColor(metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                Text("\(metrics.closedTrades) lệnh đã đóng")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        guard let d = formatter.date(from: date) else { return "" }
        let wf = DateFormatter()
        wf.dateFormat = "EEEE, dd MMMM yyyy"
        wf.locale = Locale(identifier: "vi_VN")
        return wf.string(from: d)
    }
    
    private var dayStatsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chỉ số ngày (Day stats)")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                if metrics.closedTrades > 0 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        statItem(label: "Net P&L", value: metrics.netPnl >= 0 ? "+\(Formatters.currency(metrics.netPnl))" : Formatters.currency(metrics.netPnl), color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        statItem(label: "Tổng lệnh", value: "\(metrics.closedTrades)")
                        statItem(label: "Tỷ lệ thắng", value: Formatters.percent(metrics.winRate))
                        
                        statItem(label: "Lệnh thắng", value: "\(metrics.wins)", color: AppColors.profit)
                        statItem(label: "Lệnh thua", value: "\(metrics.losses)", color: AppColors.loss)
                        statItem(label: "Lãi gộp", value: Formatters.currency(metrics.grossPnl ?? 0))
                        
                        statItem(label: "Phí & Phí sàn", value: Formatters.currency(metrics.fees ?? 0))
                        statItem(label: "Khối lượng", value: "\(metrics.totalVolume.formatted())")
                        statItem(label: "Profit Factor", value: metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor != nil ? String(format: "%.2f", metrics.profitFactor!) : "–"))
                        
                        statItem(label: "Kỳ vọng (Exp)", value: metrics.expectancy != nil ? Formatters.currency(metrics.expectancy!) : "–")
                    }
                } else {
                    Text("Chưa có lệnh giao dịch nào được đóng trong ngày này.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func statItem(label: String, value: String, color: Color = AppColors.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
    }
    
    private var intradayChartCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lợi nhuận tích luỹ trong ngày (Intraday Net P&L)")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Chart {
                    ForEach(Array(intradayPoints.enumerated()), id: \.offset) { index, point in
                        LineMark(
                            x: .value("Thời gian", point.timeStr),
                            y: .value("P&L", NSDecimalNumber(decimal: point.cumPnl).doubleValue)
                        )
                        .foregroundStyle(metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        
                        AreaMark(
                            x: .value("Thời gian", point.timeStr),
                            y: .value("P&L", NSDecimalNumber(decimal: point.cumPnl).doubleValue)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    (metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss).opacity(0.3),
                                    (metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss).opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var dayTradesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Lệnh giao dịch (\(dayTrades.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    ForEach(dayTrades) { trade in
                        NavigationLink(destination: TradeDetailView(trade: trade)) {
                            HStack(spacing: 8) {
                                // Badge trạng thái WIN / LOSS / BE
                                Text(trade.status.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        trade.netPnl > 0 ? AppColors.profit.opacity(0.15) :
                                        (trade.netPnl < 0 ? AppColors.loss.opacity(0.15) : AppColors.secondaryBackground)
                                    )
                                    .foregroundColor(
                                        trade.netPnl > 0 ? AppColors.profit :
                                        (trade.netPnl < 0 ? AppColors.loss : AppColors.secondaryText)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                
                                Text(trade.symbol)
                                    .font(AppTypography.bodyBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Text(trade.direction.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(trade.direction == .long ? AppColors.profit : AppColors.loss)
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(trade.netPnl >= 0 ? "+\(Formatters.currency(trade.netPnl))" : Formatters.currency(trade.netPnl))
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    
                                    Text("\(trade.quantity.formatted()) @ \(trade.avgEntry.formatted())")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        
                        if trade.id != dayTrades.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var dayNoteCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ghi chú ngày (Day note)")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    // Nút AI Recap
                    Button {
                        generateAiRecap()
                    } label: {
                        HStack(spacing: 4) {
                            if isGeneratingAiRecap {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("AI Recap")
                        }
                        .font(AppTypography.captionBold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.accent.opacity(0.12))
                        .foregroundColor(AppColors.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(isGeneratingAiRecap || dayTrades.isEmpty)
                }
                
                Text("Ghi chú này được lưu trữ cục bộ và đồng bộ khi kết nối. Bạn có thể tự do viết cảm xúc, kịch bản thị trường hoặc để AI tạo tổng kết tự động.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // Trình soạn thảo ghi chú
                ZStack(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Nhập nhật ký cảm xúc, nhận định thị trường ngày \(date)...")
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                    }
                    
                    TextEditor(text: $noteText)
                        .font(AppTypography.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onChange(of: noteText) { newValue in
                            scheduleSaveNote(newValue)
                        }
                }
                
                HStack {
                    if !saveStatusMessage.isEmpty {
                        Text(saveStatusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Button("Lưu ngay") {
                        saveNoteImmediately()
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.accent)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Actions & Persistence
    
    private func loadNote() {
        let saved = dataStore.getJournalDayNote(date: date)
        if !saved.isEmpty {
            noteText = saved
        } else if let cal = dataStore.calendarNotes[date] {
            noteText = cal.content
        }
    }
    
    private func scheduleSaveNote(_ text: String) {
        saveStatusMessage = "Đang lưu..."
        dataStore.saveJournalDayNote(date: date, note: text)
        var calNote = dataStore.calendarNotes[date] ?? JournalNote(date: date, content: text)
        calNote.content = text
        calNote.updatedAt = Date()
        dataStore.saveCalendarNote(calNote)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.saveStatusMessage = "Đã lưu tự động"
        }
    }
    
    private func saveNoteImmediately() {
        dataStore.saveJournalDayNote(date: date, note: noteText)
        var calNote = dataStore.calendarNotes[date] ?? JournalNote(date: date, content: noteText)
        calNote.content = noteText
        calNote.updatedAt = Date()
        dataStore.saveCalendarNote(calNote)
        saveStatusMessage = "Đã lưu"
    }
    
    private func generateAiRecap() {
        guard !dayTrades.isEmpty else { return }
        isGeneratingAiRecap = true
        aiErrorMessage = nil
        
        Task {
            let prompt = "Hãy tổng kết ngày giao dịch \(date) gồm \(metrics.closedTrades) lệnh, Net P&L: \(metrics.netPnl), Tỷ lệ thắng: \(metrics.winRate?.description ?? "0"). Chỉ ra 2 điểm tốt và 1 điểm cần cải thiện trong kỷ luật."
            let recap = await AIReflectionService.shared.generateReflection(prompt: prompt, trades: dayTrades)
            
            await MainActor.run {
                self.isGeneratingAiRecap = false
                let section = "\n\n## AI Recap (\(self.date))\n\n\(recap)"
                self.noteText += section
                self.saveNoteImmediately()
            }
        }
    }
    
    private func prepareExport() {
        let header = "Nhật ký giao dịch · \(date)\n"
        let stats = "Tổng lệnh: \(metrics.closedTrades) | Net P&L: \(Formatters.currency(metrics.netPnl)) | Tỷ lệ thắng: \(Formatters.percent(metrics.winRate))\n\n"
        let note = "Ghi chú:\n\(noteText)"
        exportText = header + stats + note
        showExportSheet = true
    }
}

/// Modal xuất và chia sẻ tài liệu đánh giá ngày
public struct ReviewExportModal: View {
    public let title: String
    public let exportText: String
    @Environment(\.dismiss) private var dismiss
    
    public init(title: String, exportText: String) {
        self.title = title
        self.exportText = exportText
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: .constant(exportText))
                    .font(AppTypography.monoCaption)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(16)
                
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = exportText
                    #endif
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Sao chép vào Clipboard")
                    }
                    .font(AppTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppColors.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
        }
    }
}
