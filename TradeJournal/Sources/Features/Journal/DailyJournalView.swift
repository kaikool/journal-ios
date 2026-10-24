import SwiftUI
import Charts

/// Model representing a single day in the daily journal list
/// Port 1:1 from `JournalDay` in `source-repo/apps/web/src/app/journal/page.tsx`
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

public struct IdentifiableDateItem: Identifiable {
    public var id: String { date }
    public let date: String
    
    public init(date: String) {
        self.date = date
    }
}

/// Daily journal list screen
/// Port 1:1 from `source-repo/apps/web/src/app/journal/page.tsx`
public struct DailyJournalListView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var searchText: String = ""
    @State private var navigateToToday: Bool = false
    @State private var selectedDateForDetail: String? = nil
    
    public init() {}
    
    @State private var cache = DailyJournalCache()
    
    @MainActor
    private final class DailyJournalCache {
        var lastKey: String = ""
        var lastList: [JournalDaySummary] = []
    }
    
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
    
    private var todayKey: String {
        Self.isoFormatter.timeZone = env.currentTimeZone
        return Self.isoFormatter.string(from: Date())
    }
    
    private var baseDaysList: [JournalDaySummary] {
        let key = "\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.journalDays.count)_\(dataStore.calendarNotes.count)_\(dataStore.cacheVersion)_\(env.currentTimeZone.identifier)"
        if cache.lastKey == key {
            return cache.lastList
        }
        let fresh = computeBaseDaysList()
        cache.lastKey = key
        cache.lastList = fresh
        return fresh
    }
    
    private var daysList: [JournalDaySummary] {
        let base = baseDaysList
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { item in
            item.date.localizedCaseInsensitiveContains(query) ||
            item.weekday.localizedCaseInsensitiveContains(query) ||
            item.notePreview.localizedCaseInsensitiveContains(query)
        }
    }
    
    private func computeBaseDaysList() -> [JournalDaySummary] {
        let trades = dataStore.filteredTrades
        Self.isoFormatter.timeZone = env.currentTimeZone
        let isoFormatter = Self.isoFormatter
        let weekdayFormatter = Self.weekdayFormatter
        
        // Collect all dates with trades or notes
        var dateMap: [String: [Trade]] = [:]
        for t in trades {
            let key = t.closedAt.map { isoFormatter.string(from: $0) } ?? isoFormatter.string(from: t.openedAt)
            dateMap[key, default: []].append(t)
        }
        
        // Add dates with notes
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
        
        // Ensure today is present in the list
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
        VStack(spacing: 0) {
            // Fixed pinned Search & Today bar - sits cleanly below ShellHeaderView
            searchAndTodayBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .overlay(
                    Divider().background(AppColors.border.opacity(0.35)),
                    alignment: .bottom
                )
            
            ScrollView {
                VStack(spacing: 10) {
                    // Day cards list
                    if daysList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            Text("No trading days yet")
                                .font(AppTypography.cardTitle)
                                .foregroundColor(AppColors.primaryText)
                            Text("No trading days yet — import trades or write your first day note.")
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
                                Button {
                                    selectedDateForDetail = day.date
                                } label: {
                                    dayRowCard(day)
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 88)
            }
            .background(AppColors.background)
        }
        .background(AppColors.background)
        .sheet(item: Binding<IdentifiableDateItem?>(
            get: { selectedDateForDetail.map { IdentifiableDateItem(date: $0) } },
            set: { selectedDateForDetail = $0?.date }
        )) { item in
            DailyJournalDetailView(date: item.date, isModal: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }
    
    private var searchAndTodayBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.system(size: 13))
                TextField("Search date, note...", text: $searchText)
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
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
            )
            
            Button {
                selectedDateForDetail = todayKey
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12))
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(AppColors.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ApplePressableButtonStyle())
            .fixedSize()
        }
    }
    
    @ViewBuilder
    private func dayRowCard(_ day: JournalDaySummary) -> some View {
        AppCard {
            HStack(alignment: .center, spacing: 10) {
                // Date & Weekday column (compact & non-wrapping)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(day.date == todayKey ? AppColors.brand : AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(day.weekday.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                
                Divider()
                    .frame(height: 32)
                
                // PnL & stats column (tightly fitted with line limits)
                if day.tradesCount > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(day.netPnl >= 0 ? "+\(Formatters.currency(day.netPnl))" : Formatters.currency(day.netPnl))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(day.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Text("• \(day.tradesCount)T")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                        
                        HStack(spacing: 6) {
                            if let wr = day.winRate {
                                Text("\(Int(wr * 100))% win")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                            }
                            Text("(\(day.winsCount)W / \(day.lossesCount)L)")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("No trades")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Compact Note badge indicator (circular icon only, preventing overflow)
                if day.hasNote {
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(AppColors.secondaryBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                        )
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
            }
        }
    }
}

/// Day detail view
/// Port 1:1 from `source-repo/apps/web/src/app/journal/[date]/page.tsx`
public struct DailyJournalDetailView: View {
    public let date: String
    public let isModal: Bool
    
    public init(date: String, isModal: Bool = false) {
        self.date = date
        self.isModal = isModal
    }
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var noteText: String = ""
    @State private var isSaving: Bool = false
    @State private var saveStatusMessage: String = ""
    @State private var showDeleteNoteAlert: Bool = false
    @State private var isGeneratingAiRecap: Bool = false
    @State private var aiErrorMessage: String? = nil
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    @State private var selectedTime: String? = nil
    @State private var selectedTradeForDetail: Trade? = nil
    @State private var autoSaveTask: Task<Void, Never>? = nil
    @State private var hasPendingChanges: Bool = false
    
    private var dayTrades: [Trade] {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.timeZone = env.currentTimeZone
        
        return dataStore.filteredTrades.filter { t in
            let closeKey = t.closedAt.map { isoFormatter.string(from: $0) }
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
        
        let closed = dayTrades.compactMap { trade -> (Date, Decimal)? in
            guard let close = trade.closedAt else { return nil }
            return (close, trade.netPnl)
        }
        for (closeDate, pnl) in closed {
            running += pnl
            let tStr = timeFormatter.string(from: closeDate)
            points.append((timeStr: tStr, cumPnl: running))
        }
        return points
    }
    
    private var strideTimeStrings: [String] {
        guard !intradayPoints.isEmpty else { return [] }
        if intradayPoints.count <= 4 {
            var unique: [String] = []
            var seen = Set<String>()
            for p in intradayPoints {
                if !seen.contains(p.timeStr) {
                    seen.insert(p.timeStr)
                    unique.append(p.timeStr)
                }
            }
            return unique
        }
        let count = intradayPoints.count
        let indices = [0, count / 3, (count * 2) / 3, count - 1]
        var seen = Set<String>()
        var result: [String] = []
        for idx in indices {
            let t = intradayPoints[idx].timeStr
            if !seen.contains(t) {
                seen.insert(t)
                result.append(t)
            }
        }
        return result
    }
    
    private var intradayDoubleVals: [Double] {
        intradayPoints.map { NSDecimalNumber(decimal: $0.cumPnl).doubleValue }
    }
    
    private var intradayYDomainMax: Double {
        let maxData = intradayDoubleVals.max() ?? 0.0
        let minData = intradayDoubleVals.min() ?? 0.0
        if maxData <= 0 && minData < 0 {
            return 0.0
        }
        let top = max(0.0, maxData)
        let span = max(1.0, top - min(0.0, minData))
        return top + (span * 0.06)
    }
    
    private var intradayYDomainMin: Double {
        let maxData = intradayDoubleVals.max() ?? 0.0
        let minData = intradayDoubleVals.min() ?? 0.0
        if minData >= 0 && maxData > 0 {
            return 0.0
        }
        let bottom = min(0.0, minData)
        let span = max(1.0, max(0.0, maxData) - bottom)
        return bottom - (span * 0.06)
    }
    
    private var intradayAreaGradient: LinearGradient {
        let top = intradayYDomainMax
        let bottom = intradayYDomainMin
        if bottom >= 0 {
            return LinearGradient(
                colors: [AppColors.brand.opacity(0.28), AppColors.brand.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if top <= 0 {
            return LinearGradient(
                colors: [AppColors.loss.opacity(0.02), AppColors.loss.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            let zeroFraction = CGFloat(top / (top - bottom))
            return LinearGradient(
                stops: [
                    .init(color: AppColors.brand.opacity(0.28), location: 0.0),
                    .init(color: AppColors.brand.opacity(0.02), location: max(0.0, zeroFraction - 0.001)),
                    .init(color: AppColors.loss.opacity(0.02), location: min(1.0, zeroFraction + 0.001)),
                    .init(color: AppColors.loss.opacity(0.28), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var intradayLineGradient: LinearGradient {
        let top = intradayYDomainMax
        let bottom = intradayYDomainMin
        if bottom >= 0 {
            return LinearGradient(colors: [AppColors.brand, AppColors.brand], startPoint: .top, endPoint: .bottom)
        } else if top <= 0 {
            return LinearGradient(colors: [AppColors.loss, AppColors.loss], startPoint: .top, endPoint: .bottom)
        } else {
            let zeroFraction = CGFloat(top / (top - bottom))
            return LinearGradient(
                stops: [
                    .init(color: AppColors.brand, location: 0.0),
                    .init(color: AppColors.brand, location: max(0.0, zeroFraction - 0.002)),
                    .init(color: AppColors.loss, location: min(1.0, zeroFraction + 0.002)),
                    .init(color: AppColors.loss, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Card 1: Day stats KPI grid (port 1:1 from web Day stats)
                dayStatsCard
                
                // Card 2: Intraday cumulative net P&L chart
                if !intradayPoints.isEmpty {
                    intradayChartCard
                }
                
                // Card 3: Closed and open trades list
                if !dayTrades.isEmpty {
                    dayTradesCard
                }
                
                // Card 4: Day note editor & AI Recap
                dayNoteCard
                
                // Card 5: Attachments & chart screenshots
                AttachmentsSectionView(ownerType: "day", ownerId: date, title: "Attachments")
                    .padding(.horizontal, 14)
            }
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBarView(
                title: "Journal · \(date)",
                showFilters: false,
                onBack: { dismiss() },
                isModal: isModal
            ) {
                AppActionPill("Export", icon: "square.and.arrow.up", isPrimary: false) {
                    prepareExport()
                }
            }
        }
        .background(AppColors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveEdgeBack(onBack: isModal ? nil : { dismiss() })
        .enableNativePopGesture()
        .sheet(isPresented: $showExportSheet) {
            ReviewExportModal(title: "Journal · \(date)", exportText: exportText)
        }
        .sheet(item: $selectedTradeForDetail) { trade in
            TradeDetailView(trade: trade, isModal: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .alert("Delete note for \(date)?", isPresented: $showDeleteNoteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                noteText = ""
                dataStore.deleteCalendarNote(for: date)
                saveStatusMessage = "Deleted"
            }
        } message: {
            Text("This note will be permanently removed from your calendar and Supabase.")
        }
        .onAppear {
            loadNote()
        }
        .onDisappear {
            saveNoteImmediately()
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
            
            // Quick P&L summary badge
            VStack(alignment: .trailing, spacing: 2) {
                Text(metrics.netPnl >= 0 ? "+\(Formatters.currency(metrics.netPnl))" : Formatters.currency(metrics.netPnl))
                    .font(AppTypography.title3)
                    .foregroundColor(metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                Text("\(metrics.closedTrades) closed trade\(metrics.closedTrades == 1 ? "" : "s")")
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
        wf.locale = Locale(identifier: "en_US")
        return wf.string(from: d)
    }
    
    private var dayStatsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Day stats")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                if metrics.closedTrades > 0 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        statItem(label: "Net P&L", value: metrics.netPnl >= 0 ? "+\(Formatters.currency(metrics.netPnl))" : Formatters.currency(metrics.netPnl), color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        statItem(label: "Trades", value: "\(metrics.closedTrades)")
                        statItem(label: "Winrate", value: Formatters.percent(metrics.winRate))
                        
                        statItem(label: "Winners", value: "\(metrics.wins)", color: AppColors.profit)
                        statItem(label: "Losers", value: "\(metrics.losses)", color: AppColors.loss)
                        statItem(label: "Gross", value: Formatters.currency(metrics.grossPnl ?? 0))
                        
                        statItem(label: "Fees", value: Formatters.currency(metrics.fees ?? 0))
                        statItem(label: "Volume", value: "\(metrics.totalVolume.formatted())")
                        statItem(label: "Profit Factor", value: metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor.map { String(format: "%.2f", $0) } ?? "–"))
                        
                        statItem(label: "Expectancy", value: metrics.expectancy.map { Formatters.currency($0) } ?? "–")
                    }
                } else {
                    Text("No closed trades this day.")
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
        let activePoint = intradayPoints.first { $0.timeStr == selectedTime } ?? intradayPoints.last
        let isPositive = (activePoint?.cumPnl ?? metrics.netPnl) >= 0
        let chartColor = isPositive ? AppColors.brand : AppColors.loss
        
        return AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTime.map { "At \($0)" } ?? "Intraday Cumulative Net P&L")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Text(Formatters.formatPnL(activePoint?.cumPnl ?? metrics.netPnl, currency: env.currentCurrency))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(chartColor)
                    }
                    
                    Spacer()
                }
                
                Chart {
                    RuleMark(y: .value("Zero", 0.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.85))
                    
                    ForEach(Array(intradayPoints.enumerated()), id: \.offset) { _, point in
                        let val = NSDecimalNumber(decimal: point.cumPnl).doubleValue
                        
                        // Single area fill anchored strictly to 0.0 baseline with locked sub-pixel gradient
                        AreaMark(
                            x: .value("Time", point.timeStr),
                            yStart: .value("Baseline", 0.0),
                            yEnd: .value("P&L", val)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(intradayAreaGradient)
                        .alignsMarkStylesWithPlotArea()
                        
                        LineMark(
                            x: .value("Time", point.timeStr),
                            y: .value("P&L", val)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(intradayLineGradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .alignsMarkStylesWithPlotArea()
                    }
                    
                    if intradayPoints.count == 1, let single = intradayPoints.first {
                        let singleVal = NSDecimalNumber(decimal: single.cumPnl).doubleValue
                        PointMark(
                            x: .value("Time", single.timeStr),
                            y: .value("P&L", singleVal)
                        )
                        .foregroundStyle(singleVal >= 0 ? AppColors.brand : AppColors.loss)
                        .symbolSize(36)
                    }
                    
                    if let time = selectedTime, let p = activePoint {
                        let activeVal = NSDecimalNumber(decimal: p.cumPnl).doubleValue
                        
                        RuleMark(x: .value("Cursor", time))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.45))
                        
                        PointMark(
                            x: .value("Time", time),
                            y: .value("P&L", activeVal)
                        )
                        .foregroundStyle(activeVal >= 0 ? AppColors.brand : AppColors.loss)
                        .symbolSize(36)
                    }
                }
                .chartXSelection(value: $selectedTime)
                .chartYScale(domain: intradayYDomainMin...intradayYDomainMax)
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
                    AxisMarks(values: strideTimeStrings) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let str = value.as(String.self) {
                                Text(str)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var dayTradesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Trades (\(dayTrades.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    ForEach(dayTrades) { trade in
                        Button {
                            selectedTradeForDetail = trade
                        } label: {
                            HStack(spacing: 8) {
                                // Status badge WIN / LOSS / BE
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
                                    .lineLimit(1)
                                
                                Text(trade.symbol)
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                                
                                Text(trade.direction.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                                    .lineLimit(1)
                                
                                Spacer(minLength: 4)
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(trade.netPnl >= 0 ? "+\(Formatters.currency(trade.netPnl))" : Formatters.currency(trade.netPnl))
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        .lineLimit(1)
                                    
                                    Text("\(Formatters.formatNumber(trade.quantity)) lots @ \(Formatters.price(trade.avgEntry))")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                        
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
                    Text("Day note")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    if !noteText.isEmpty {
                        Button {
                            showDeleteNoteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.loss.opacity(0.75))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // AI Recap button
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
                
                if let err = aiErrorMessage {
                    Text(err)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.loss)
                }
                
                Text("Notes are saved locally and synced automatically. Write your reflections, market observations, or generate an AI recap.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // Formatting toolbar
                HStack(spacing: 8) {
                    Button {
                        applyFormat(marker: "**")
                    } label: {
                        Text("B")
                            .font(.system(size: 13, weight: .black))
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        applyFormat(marker: "*")
                    } label: {
                        Text("I")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .italic()
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        insertNumberedList()
                    } label: {
                        Image(systemName: "list.number")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Button {
                        insertBullet()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 26)
                            .background(AppColors.secondaryBackground)
                            .foregroundColor(AppColors.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    Spacer()
                }
                
                // Note text editor
                ZStack(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Write your review for \(date)...")
                            .font(AppTypography.inputText)
                            .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                    }
                    
                    TextEditor(text: $noteText)
                        .font(AppTypography.inputText)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onChange(of: noteText) { newValue in
                            scheduleSaveNote(newValue)
                        }
                }
                
                HStack(spacing: 12) {
                    if !saveStatusMessage.isEmpty {
                        Text(saveStatusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if !noteText.isEmpty {
                        Button("Clear") {
                            noteText = ""
                            dataStore.deleteCalendarNote(for: date)
                            saveStatusMessage = "Cleared"
                        }
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Button("Save now") {
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
        hasPendingChanges = true
        saveStatusMessage = "Editing..."
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            saveNoteImmediately()
        }
    }
    
    private func saveNoteImmediately() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        guard hasPendingChanges else { return }
        hasPendingChanges = false
        
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dataStore.deleteCalendarNote(for: date)
            saveStatusMessage = "Cleared"
            return
        }
        dataStore.saveJournalDayNote(date: date, note: noteText)
        saveStatusMessage = "Auto-saved"
    }
    
    private func applyFormat(marker: String) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let res = NoteFormattingEngine.formatInlineSelection(
            value: noteText,
            start: (noteText as NSString).length,
            end: (noteText as NSString).length,
            marker: marker
        )
        noteText = res.value
        scheduleSaveNote(noteText)
    }
    
    private func insertBullet() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if noteText.isEmpty || noteText.hasSuffix("\n") {
            noteText += "- "
        } else {
            noteText += "\n- "
        }
        scheduleSaveNote(noteText)
    }
    
    private func insertNumberedList() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if noteText.isEmpty || noteText.hasSuffix("\n") {
            noteText += "1. "
        } else {
            noteText += "\n1. "
        }
        scheduleSaveNote(noteText)
    }
    
    private func generateAiRecap() {
        guard !dayTrades.isEmpty else { return }
        isGeneratingAiRecap = true
        aiErrorMessage = nil
        
        Task {
            do {
                let prompt = "Please summarize the trading day \(date) with \(metrics.closedTrades) trades, Net P&L: \(metrics.netPnl), Win rate: \(metrics.winRate?.description ?? "0"). Highlight 2 strengths and 1 area for discipline improvement."
                let recap = try await AIReflectionService.shared.requestReflection(action: .recap, prompt: prompt, metrics: metrics)
                
                await MainActor.run {
                    self.isGeneratingAiRecap = false
                    let section = "\n\n## AI Recap (\(self.date))\n\n\(recap)"
                    self.noteText += section
                    self.saveNoteImmediately()
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingAiRecap = false
                    self.aiErrorMessage = "AI Recap notice: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func prepareExport() {
        let header = "Trade Journal · \(date)\n"
        let stats = "Trades: \(metrics.closedTrades) | Net P&L: \(Formatters.currency(metrics.netPnl)) | Win rate: \(Formatters.percent(metrics.winRate))\n\n"
        let note = "Notes:\n\(noteText)"
        exportText = header + stats + note
        showExportSheet = true
    }
}

/// Modal for exporting and sharing daily review
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
                        Text("Copy to Clipboard")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

public typealias DailyJournalView = DailyJournalListView
