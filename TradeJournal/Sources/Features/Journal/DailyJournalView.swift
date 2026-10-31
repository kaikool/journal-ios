import SwiftUI

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
        let query = (env.isSearchActive ? env.searchQuery : searchText).trimmingCharacters(in: .whitespacesAndNewlines)
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
        ScrollView {
            VStack(spacing: 12) {
                if daysList.isEmpty {
                    AppEmptyState(
                        icon: "calendar.badge.exclamationmark",
                        title: "No trading days yet",
                        message: "Import trades or write your first day note to get started."
                    )
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
        .onReceive(env.$requestOpenTodayJournal) { requested in
            if requested {
                env.requestOpenTodayJournal = false
                selectedDateForDetail = todayKey
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
            AppSearchBar("Search date, note...", text: $searchText, height: 36)
            
            Button {
                selectedDateForDetail = todayKey
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(AppTypography.actionButtonCompact)
                    Text("Today")
                        .font(AppTypography.actionButtonCompact)
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
                        .font(AppTypography.rowPrimary)
                        .foregroundColor(day.date == todayKey ? AppColors.brand : AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(day.weekday.uppercased())
                        .font(AppTypography.captionMicro)
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
                                .font(AppTypography.statValue)
                                .foregroundColor(day.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Text("• \(day.tradesCount)T")
                                .font(AppTypography.statLabel)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                        
                        HStack(spacing: 6) {
                            if let wr = day.winRate {
                                Text("\(Int(wr * 100))% win")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                            }
                            Text("(\(day.winsCount)W / \(day.lossesCount)L)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("No trades")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Compact Note badge indicator (circular icon only, preventing overflow)
                if day.hasNote {
                    Image(systemName: "note.text")
                        .font(AppTypography.captionMicro)
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
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
            }
        }
    }
}

public typealias DailyJournalView = DailyJournalListView
