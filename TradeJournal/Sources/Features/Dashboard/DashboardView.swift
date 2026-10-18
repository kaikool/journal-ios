import SwiftUI
import Charts

public struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @AppStorage("dashboard_hidden_widgets") private var hiddenWidgetsRaw: String = ""
    @AppStorage("dashboard_card_order") private var cardOrderRaw: String = ""
    @AppStorage("dashboard_active_preset") private var activePresetRaw: String = "Overview"
    
    @State private var isEditingLayout: Bool = false
    @State private var selectedRange: JournalTimeRange = .all
    @State private var showEdgeScoreBreakdown: Bool = false
    @State private var showCustomizerSheet: Bool = false
    @State private var showAIReflection: Bool = false
    @State private var showAddTradeSheet: Bool = false
    @State private var activityTab: String = "recent" // "recent" or "open"
    @State private var activeTooltip: (title: String, hint: String)? = nil
    
    // Day detail sheet integration for Widget 8 (Calendar)
    @State private var selectedDayContext: DayDetailContext? = nil
    @State private var addTradeDate: Date? = nil
    
    public init() {}
    
    // MARK: - Arrangement & Presets
    
    // MARK: - Arrangement & Presets
    
    private var cardOrder: [String] {
        if cardOrderRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DashboardCardRegistry.defaultOrder
        }
        let list = cardOrderRaw.split(separator: ",").map(String.init)
        var result = list.filter { DashboardCardRegistry.defaultOrder.contains($0) }
        for card in DashboardCardRegistry.defaultOrder {
            if !result.contains(card) {
                result.append(card)
            }
        }
        return result
    }
    
    private var cardOrderBinding: Binding<[String]> {
        Binding(
            get: { cardOrder },
            set: { newOrder in
                cardOrderRaw = newOrder.joined(separator: ",")
            }
        )
    }
    
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
    
    private var activePreset: DashboardPreset {
        DashboardPreset(rawValue: activePresetRaw) ?? .overview
    }
    
    private var activePresetBinding: Binding<DashboardPreset> {
        Binding(
            get: { activePreset },
            set: { newPreset in
                activePresetRaw = newPreset.rawValue
            }
        )
    }
    
    private var visibleCardCount: Int {
        DashboardCardRegistry.allCards.count - hiddenCardIds.count
    }
    
    // MARK: - Filtered Trades by Range
    
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
    
    // MARK: - Memoized Single-Pass Snapshot
    
    private struct DashboardSnapshot {
        let metrics: TradeMetrics
        let curve: [EquityPoint]
        let days: [DayStats]
        let edgeResult: EdgeScore
        let chartEquityPoints: [EquityPointItem]
        let hourlyStats: [BucketStats]
        let weekDelta: Decimal?
        let bestDay: DayStats?
        let worstDay: DayStats?
        let daysWithTradesMap: [String: DayStats]
        let currentMonthStats: (tradingDays: Int, winningDays: Int, monthPnl: Decimal)
    }
    
    private var snapshot: DashboardSnapshot {
        let initialBalance: Decimal = {
            if dataStore.selectedAccountId == "all" {
                return dataStore.visibleAccounts.reduce(Decimal.zero) { $0 + $1.initialBalance }
            }
            return dataStore.selectedAccount?.initialBalance ?? 0
        }()
        
        let overview = FinancialMetricsEngine.computeOverview(
            trades: scopedTrades,
            timeZone: env.currentTimeZone,
            initialBalance: initialBalance
        )
        
        let edge = EdgeScoreEngine.computeEdgeScore(metrics: overview.metrics)
        
        var runningPeak: Decimal = 0
        let chartPoints = overview.curve.map { pt -> EquityPointItem in
            if pt.cumNetPnl > runningPeak {
                runningPeak = pt.cumNetPnl
            }
            let base = initialBalance + runningPeak
            let dd: Decimal = base > 0 ? (runningPeak - pt.cumNetPnl) / base : (runningPeak > 0 ? (runningPeak - pt.cumNetPnl) / runningPeak : Decimal.zero)
            return EquityPointItem(
                date: pt.timestamp,
                dateKey: pt.dateString,
                netPnl: pt.cumNetPnl,
                cumulativePnl: pt.cumNetPnl,
                drawdown: dd
            )
        }
        
        let hourly = AggregateEngine.byHour(trades: scopedTrades, timeZone: env.currentTimeZone)
        
        // Momentum: net P&L of the last 7 calendar days vs the 7 before them (matching page.tsx lines 207-224)
        let nowMs = Date().timeIntervalSince1970 * 1000
        var last: Decimal = 0
        var prior: Decimal = 0
        var lastDays = 0
        var priorDays = 0
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        for day in overview.days {
            if let date = formatter.date(from: day.date) {
                let ageDays = (nowMs - (date.timeIntervalSince1970 * 1000)) / 86_400_000
                if ageDays <= 7 {
                    last += day.netPnl
                    lastDays += 1
                } else if ageDays <= 14 {
                    prior += day.netPnl
                    priorDays += 1
                }
            }
        }
        let delta = (lastDays > 0 && priorDays > 0) ? (last - prior) : nil
        
        let best = overview.days.max(by: { $0.netPnl < $1.netPnl })
        let worst = overview.days.min(by: { $0.netPnl < $1.netPnl })
        
        var dayMap: [String: DayStats] = [:]
        for d in overview.days {
            dayMap[d.date] = d
        }
        
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM"
        let prefix = iso.string(from: Date())
        let monthDays = overview.days.filter { $0.date.hasPrefix(prefix) }
        let tradingDays = monthDays.count
        let winningDays = monthDays.filter { $0.netPnl > 0 }.count
        let monthPnl = monthDays.reduce(Decimal.zero) { $0 + $1.netPnl }
        
        return DashboardSnapshot(
            metrics: overview.metrics,
            curve: overview.curve,
            days: overview.days,
            edgeResult: edge,
            chartEquityPoints: chartPoints,
            hourlyStats: hourly,
            weekDelta: delta,
            bestDay: best,
            worstDay: worst,
            daysWithTradesMap: dayMap,
            currentMonthStats: (tradingDays, winningDays, monthPnl)
        )
    }
    
    // MARK: - Multi-Currency Group Calculations
    
    private var isMultiCurrencyNoticeActive: Bool {
        dataStore.selectedAccountId == "all" && dataStore.availableCurrencies.count > 1
    }
    
    private var currencyGroups: [(currency: String, metrics: TradeMetrics)] {
        let visibleAccs = dataStore.visibleAccounts
        let currencies = Array(Set(visibleAccs.map { $0.currency.uppercased() })).sorted()
        return currencies.map { curr in
            let accIds = Set(visibleAccs.filter { $0.currency.uppercased() == curr }.map { $0.id })
            let tradesForCurr = scopedTrades.filter { accIds.contains($0.accountId) || accIds.contains("the5ers_\($0.accountId)") }
            let initBal = visibleAccs.filter { $0.currency.uppercased() == curr }.reduce(Decimal.zero) { $0 + $1.initialBalance }
            let ov = FinancialMetricsEngine.computeOverview(trades: tradesForCurr, timeZone: env.currentTimeZone, initialBalance: initBal)
            return (curr, ov.metrics)
        }
    }
    
    // MARK: - Calendar Widget Helpers
    
    private var calendarWeeks: [[Date?]] {
        let cal = Calendar.current
        let now = Date()
        guard let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: now)),
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
    
    // MARK: - Dynamic Responsive Grid Computation (1:1 port of balancedDashboardSpans)
    
    private struct DashboardRowItem: Identifiable {
        let id: String
        let items: [String]
    }
    
    private var dashboardRows: [DashboardRowItem] {
        let visible = cardOrder.filter { !hiddenCardIds.contains($0) }
        var rows: [DashboardRowItem] = []
        var i = 0
        while i < visible.count {
            let currentId = visible[i]
            let currentSize = DashboardCardRegistry.size(for: currentId)
            
            if currentSize == .small {
                // If the next card is also .small, pair them side-by-side
                if i + 1 < visible.count {
                    let nextId = visible[i + 1]
                    let nextSize = DashboardCardRegistry.size(for: nextId)
                    if nextSize == .small {
                        rows.append(DashboardRowItem(id: "\(currentId)_\(nextId)", items: [currentId, nextId]))
                        i += 2
                        continue
                    }
                }
                // Isolated small card spans full width
                rows.append(DashboardRowItem(id: currentId, items: [currentId]))
                i += 1
            } else {
                // Medium, wide, or full width card
                rows.append(DashboardRowItem(id: currentId, items: [currentId]))
                i += 1
            }
        }
        return rows
    }
    
    // MARK: - Main Body
    
    public var body: some View {
        let snap = snapshot
        let metrics = snap.metrics
        
        VStack(spacing: 0) {
            // FilterBar matching web filter-bar.tsx
            FilterBarView(
                title: "Dashboard",
                selectedRange: $selectedRange,
                showFilters: true
            ) {
                AppActionPill("Add trade", icon: "plus") {
                    showAddTradeSheet = true
                }
            }
            
            // Top Toolbar: Saved Layout & Customize trigger matching dashboard-layout.tsx
            layoutBar
            
            ScrollView {
                VStack(spacing: 12) {
                    syncNotificationSection
                    
                    if isEditingLayout {
                        reorderBanner
                    }
                    
                    if isMultiCurrencyNoticeActive {
                        // Multi-currency notice & account breakdown matching page.tsx lines 153-188
                        multiCurrencySection
                    } else if metrics.totalTrades == 0 {
                        if selectedRange != .all {
                            filteredEmptyState
                        } else {
                            emptyStateCard
                        }
                    } else {
                        // Dynamic Grid Conforming 1:1 to balancedDashboardSpans
                        ForEach(dashboardRows) { row in
                            if row.items.count == 2 {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    renderWidget(id: row.items[0], snap: snap, isCompact: true)
                                    renderWidget(id: row.items[1], snap: snap, isCompact: true)
                                }
                            } else if let id = row.items.first {
                                renderWidget(id: id, snap: snap, isCompact: false)
                            }
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
            DashboardCustomizerSheet(
                hiddenCardIds: hiddenCardIdsBinding,
                cardOrder: cardOrderBinding,
                activePreset: activePresetBinding
            )
        }
        .sheet(isPresented: $showAIReflection) {
            AIReflectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showAddTradeSheet) {
            AddTradeSheet(initialDate: addTradeDate ?? Date())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
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
        .alert(activeTooltip?.title ?? "Info", isPresented: Binding(
            get: { activeTooltip != nil },
            set: { if !$0 { activeTooltip = nil } }
        )) {
            Button("Got it", role: .cancel) { activeTooltip = nil }
        } message: {
            Text(activeTooltip?.hint ?? "")
        }
    }
    
    // MARK: - Reorder Mode Banner
    
    private var reorderBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .foregroundColor(AppColors.brand)
                .font(.system(size: 14))
            
            Text("Reorder mode: tap arrows to move cards")
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.primaryText)
            
            Spacer()
            
            Button("Done") {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isEditingLayout = false
                }
            }
            .font(AppTypography.captionBold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColors.brand)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .padding(10)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.brand.opacity(0.35), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Top Layout Bar (Apple HIG Presets Menu & Customize)
    
    private var layoutBar: some View {
        HStack(spacing: 8) {
            // Presets Menu
            Menu {
                Section("Presets") {
                    ForEach(DashboardPreset.allCases.filter { $0 != .custom }) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.name)
                                if activePreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                if activePreset == .custom {
                    Section {
                        Text("Custom arrangement active")
                    }
                }
                
                Section {
                    Button {
                        applyPreset(.overview)
                    } label: {
                        Label("Restore default layout", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: activePreset.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    Text(activePreset.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                )
            }
            
            Text("\(visibleCardCount) of \(DashboardCardRegistry.allCards.count) cards")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            // Reorder / Edit Layout Mode Button
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isEditingLayout.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isEditingLayout ? "checkmark" : "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                    Text(isEditingLayout ? "Done" : "Reorder")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(isEditingLayout ? .white : AppColors.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isEditingLayout ? AppColors.brand : AppColors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isEditingLayout ? Color.clear : AppColors.border.opacity(0.6), lineWidth: 0.5)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            // Customize button (Sheet)
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showCustomizerSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                    Text("Customize")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
    
    // MARK: - Presets & Reorder Actions
    
    private func applyPreset(_ preset: DashboardPreset) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activePresetRaw = preset.rawValue
            cardOrderRaw = preset.canonicalOrder.joined(separator: ",")
            hiddenWidgetsRaw = preset.canonicalHidden.joined(separator: ",")
        }
    }
    
    private func moveCard(cardId: String, direction: Int) {
        var currentOrder = cardOrder
        guard let currentIndex = currentOrder.firstIndex(of: cardId) else { return }
        let newIndex = currentIndex + direction
        guard newIndex >= 0 && newIndex < currentOrder.count else { return }
        
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentOrder.swapAt(currentIndex, newIndex)
            cardOrderRaw = currentOrder.joined(separator: ",")
            activePresetRaw = DashboardPreset.custom.rawValue
        }
    }
    
    private func hideCard(cardId: String) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        var currentHidden = hiddenCardIds
        currentHidden.insert(cardId)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            hiddenWidgetsRaw = currentHidden.joined(separator: ",")
            activePresetRaw = DashboardPreset.custom.rawValue
        }
    }
    
    // MARK: - Multi-Currency Section
    
    @ViewBuilder
    private var multiCurrencySection: some View {
        VStack(spacing: 12) {
            // Notice Banner
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up conversion to see your combined dashboard")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("These accounts use \(dataStore.availableCurrencies.joined(separator: ", ")). Set your conversion rates under Settings to combine their performance. Amounts below remain in their original currencies.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            
            // All Accounts Card
            let totalClosed = currencyGroups.reduce(0) { $0 + $1.metrics.closedTrades }
            let totalWins = currencyGroups.reduce(0) { $0 + $1.metrics.wins }
            let combinedWinRate = totalClosed > 0 ? Double(totalWins) / Double(totalClosed) : nil
            
            cardContainer {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All accounts")
                        .font(AppTypography.cardTitle)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("\(totalClosed) closed trades · \(combinedWinRate != nil ? String(format: "%.1f%%", combinedWinRate! * 100) : "–") trade win rate")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Per-Currency Account Cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(currencyGroups, id: \.currency) { group in
                    cardContainer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.currency) accounts")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            
                            AppMonetaryText(
                                Formatters.formatPnL(group.metrics.netPnl, currency: group.currency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 20, weight: .bold),
                                color: group.metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                            )
                            
                            Text("\(group.metrics.closedTrades) closed · \(group.metrics.winRate != nil ? String(format: "%.0f%%", group.metrics.winRate! * 100) : "–") win")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Empty States
    
    private var filteredEmptyState: some View {
        cardContainer {
            VStack(spacing: 12) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.secondaryText)
                
                Text("No trades match these filters")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Text("Clear or adjust filters to see more results.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Button("Reset to All") {
                    withAnimation {
                        selectedRange = .all
                    }
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brand)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
    
    private var emptyStateCard: some View {
        cardContainer {
            VStack(spacing: 14) {
                Image(systemName: "tray")
                    .font(.system(size: 38))
                    .foregroundColor(AppColors.secondaryText)
                
                Text("Your journal is empty")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Text("Connect a broker for automatic sync, upload a statement from 10+ platforms (including your TradeZella export), or add trades manually.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                HStack(spacing: 10) {
                    AppButton("Import your first trades", icon: "square.and.arrow.down", style: .primary) {
                        env.selectedTab = .importTrades
                    }
                    
                    AppButton("Load demo data", icon: "sparkles", style: .secondary) {
                        dataStore.loadDemoData()
                    }
                }
                .padding(.top, 6)
                
                Text("Demo data lands in its own account; delete it anytime under Accounts.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
    
    // MARK: - Sync Notifications
    
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    // MARK: - Universal Widget Dispatcher & Reorder Wrapper
    
    @ViewBuilder
    private func renderWidget(id: String, snap: DashboardSnapshot, isCompact: Bool) -> some View {
        DashboardCardWrapper(
            cardId: id,
            isEditing: isEditingLayout,
            onMoveUp: { moveCard(cardId: id, direction: -1) },
            onMoveDown: { moveCard(cardId: id, direction: 1) },
            onHide: { hideCard(cardId: id) }
        ) {
            switch id {
            case "widget-0": widget0NetPnl(snap: snap, isCompact: isCompact)
            case "widget-1": widget1TradeWin(snap: snap, isCompact: isCompact)
            case "widget-2": widget2ProfitFactor(snap: snap, isCompact: isCompact)
            case "widget-3": widget3DayWin(snap: snap, isCompact: isCompact)
            case "widget-4": widget4AvgWinLoss(snap: snap, isCompact: isCompact)
            case "widget-5": widget5EdgeScore(snap: snap)
            case "widget-6": widget6CumulativePnl(snap: snap)
            case "widget-7": widget7DailyPnl(snap: snap)
            case "widget-8": widget8Calendar(snap: snap)
            case "widget-9": widget9Activity(snap: snap)
            case "widget-10": widget10MaxDrawdown(snap: snap, isCompact: isCompact)
            case "widget-11": widget11Streaks(snap: snap, isCompact: isCompact)
            case "widget-12": widget12Expectancy(snap: snap, isCompact: isCompact)
            case "widget-13": widget13AvgDuration(snap: snap, isCompact: isCompact)
            case "widget-14": widget14BestWorstDay(snap: snap, isCompact: isCompact)
            case "widget-15": widget15TradeTimePerformance(snap: snap)
            default: EmptyView()
            }
        }
    }
    
    // MARK: - 16 Canonical Widgets (1:1 port from apps/web/src/app/page.tsx)
    
    // Widget 0: Net P&L (CircleDollarSign)
    @ViewBuilder
    private func widget0NetPnl(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Net P&L",
                    icon: "dollarsign.circle",
                    hint: "Realized profit and loss net of fees, over the selected range."
                )
                
                if isCompact {
                    Spacer(minLength: 2)
                    AppMonetaryText(
                        Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 20, weight: .bold),
                        color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    if let delta = snap.weekDelta {
                        HStack(spacing: 3) {
                            Text(delta >= 0 ? "▲" : "▼")
                                .font(.system(size: 9, weight: .bold))
                            Text(Formatters.formatCurrency(abs(delta), currency: env.currentCurrency))
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                            Text("vs 7d")
                                .font(AppTypography.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(delta >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                        .foregroundColor(delta >= 0 ? AppColors.profit : AppColors.loss)
                        .clipShape(Capsule())
                    }
                    
                    Text("\(metrics.closedTrades) closed · \(Formatters.formatCurrency(metrics.fees, currency: env.currentCurrency)) fees")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        AppMonetaryText(
                            Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 28, weight: .bold),
                            color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                        
                        Spacer()
                        
                        if let delta = snap.weekDelta {
                            HStack(spacing: 3) {
                                Text(delta >= 0 ? "▲" : "▼")
                                    .font(.system(size: 9, weight: .bold))
                                Text(Formatters.formatCurrency(abs(delta), currency: env.currentCurrency))
                                    .font(AppTypography.captionBold)
                                    .monospacedDigit()
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
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 1: Trade win % (Target)
    @ViewBuilder
    private func widget1TradeWin(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Trade win %",
                    icon: "target",
                    hint: "Winning trades divided by all closed trades, including breakevens."
                )
                
                Spacer(minLength: 2)
                
                HStack(alignment: .center, spacing: 8) {
                    GaugeView(value: metrics.winRate, label: "Trade win rate", size: 68)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(metrics.wins) W")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.profit)
                        Text("\(metrics.breakevens) BE")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(metrics.losses) L")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.loss)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 2: Profit factor (Scale)
    @ViewBuilder
    private func widget2ProfitFactor(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Profit factor",
                    icon: "scalemass",
                    hint: "Gross profit ÷ gross loss. Above 1 means the wins outweigh the losses."
                )
                
                Spacer(minLength: 4)
                
                Text(metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor != nil ? String(format: "%.2f", metrics.profitFactor!) : "–"))
                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                Text("gross profit ÷ gross loss")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 3: Day win % (CalendarCheck2)
    @ViewBuilder
    private func widget3DayWin(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Day win %",
                    icon: "calendar.badge.clock",
                    hint: "Green trading days ÷ all trading days in the selected range."
                )
                
                Spacer(minLength: 2)
                
                HStack(alignment: .center, spacing: 8) {
                    GaugeView(value: metrics.dayWinRate, label: "Day win rate", size: 68)
                    
                    Spacer()
                    
                    Text("\(metrics.tradingDays) days")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 4: Avg win / loss (ArrowUpDown)
    @ViewBuilder
    private func widget4AvgWinLoss(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Avg win / loss",
                    icon: "arrow.up.arrow.down",
                    hint: "Average winning trade ÷ average losing trade. The bar shows the two to scale."
                )
                
                Spacer(minLength: 2)
                
                Text(metrics.avgWinLossRatio != nil ? String(format: "%.2f", metrics.avgWinLossRatio!) : "–")
                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                if let w = metrics.avgWin, let l = metrics.avgLoss, (w + l) > 0 {
                    let ratio = (w as NSDecimalNumber).doubleValue / ((w + l) as NSDecimalNumber).doubleValue
                    AppRatioBar(greenRatio: ratio)
                        .padding(.vertical, 1)
                }
                
                HStack(spacing: 2) {
                    Text(Formatters.formatCurrency(metrics.avgWin, currency: env.currentCurrency))
                        .foregroundColor(AppColors.profit)
                        .monospacedDigit()
                    Text(" win · ")
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.formatCurrency(metrics.avgLoss, currency: env.currentCurrency))
                        .foregroundColor(AppColors.loss)
                        .monospacedDigit()
                    Text(" loss")
                        .foregroundColor(AppColors.secondaryText)
                }
                .font(AppTypography.caption)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 5: Edge Score (Gauge)
    @ViewBuilder
    private func widget5EdgeScore(snap: DashboardSnapshot) -> some View {
        let metrics = snap.metrics
        let edgeResult = snap.edgeResult
        cardContainer {
            VStack(spacing: 10) {
                HStack {
                    statHeader(
                        "Edge Score",
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        hint: "A 0–100 score combining win rate, profit factor, average win/loss, drawdown, recovery, and consistency. Requires at least five closed trades."
                    )
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        Text(edgeResult.score != nil ? "\(Int(edgeResult.score!))" : "–")
                            .font(AppTypography.financialNumber(size: 24, weight: .bold))
                            .monospacedDigit()
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
                    EdgeRadarView(components: edgeResult.components, height: 210)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation {
                            showEdgeScoreBreakdown.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showEdgeScoreBreakdown ? "Hide component breakdown" : "View component breakdown")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: showEdgeScoreBreakdown ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .padding(.top, 2)
                    
                    if showEdgeScoreBreakdown, let b = edgeResult.breakdown {
                        Divider().background(AppColors.border.opacity(0.6))
                        
                        VStack(spacing: 5) {
                            scorePillarRow("Win rate", value: b.winRate, max: 15)
                            scorePillarRow("Profit factor", value: b.profitFactor, max: 25)
                            scorePillarRow("Avg win / loss", value: b.avgWinLoss, max: 20)
                            scorePillarRow("Drawdown", value: b.drawdown, max: 15)
                            scorePillarRow("Recovery", value: b.recovery, max: 10)
                            scorePillarRow("Consistency", value: b.consistency, max: 15)
                        }
                    }
                }
            }
        }
    }
    
    // Widget 6: Daily net cumulative P&L
    @ViewBuilder
    private func widget6CumulativePnl(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Daily net cumulative P&L",
                    icon: "chart.line.uptrend.xyaxis",
                    hint: "Running total of net profit and loss over the selected period. The drawdown bars below show declines from the running equity peak."
                )
                
                EquityCurveChart(points: snap.chartEquityPoints, currency: env.currentCurrency, height: 180)
                
                Divider().background(AppColors.border.opacity(0.6))
                
                DrawdownChart(points: snap.chartEquityPoints, height: 75)
            }
        }
    }
    
    // Widget 7: Net daily P&L
    @ViewBuilder
    private func widget7DailyPnl(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Net daily P&L",
                    icon: "chart.bar.xaxis",
                    hint: "Net profit or loss for each trading day. Bars above zero are profitable; bars below zero are losses."
                )
                
                DailyBarsView(
                    data: snap.days.map { DailyBarDatum(date: $0.date, netPnl: $0.netPnl) },
                    currency: env.currentCurrency,
                    isPrivate: env.isPrivacyModeEnabled,
                    height: 160
                )
            }
        }
    }
    
    // Widget 8: Calendar Mini Widget (8-column layout matching calendar-pnl.tsx)
    @ViewBuilder
    private func widget8Calendar(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(monthName)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        env.selectedTab = .calendar
                    } label: {
                        Text("Full calendar")
                            .font(AppTypography.captionBold)
                            .underline()
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                // 8-column header (Sun..Sat + Week)
                let cols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Wk"]
                HStack(spacing: 4) {
                    ForEach(cols, id: \.self) { c in
                        Text(c)
                            .font(.system(size: 9, weight: .bold))
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
                            return snap.daysWithTradesMap[key]?.netPnl
                        }.reduce(Decimal.zero, +)
                        
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { dayIdx in
                                if let date = week[dayIdx] {
                                    let key = isoFormatter.string(from: date)
                                    let stats = snap.daysWithTradesMap[key]
                                    let dayNum = Calendar.current.component(.day, from: date)
                                    
                                    Button {
                                        openCalendarDay(dateKey: key, stats: stats)
                                    } label: {
                                        VStack(spacing: 1) {
                                            Text("\(dayNum)")
                                                .font(.system(size: 9, weight: stats != nil ? .bold : .regular))
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
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            stats != nil ? RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(stats!.netPnl >= 0 ? AppColors.profit.opacity(0.24) : AppColors.loss.opacity(0.24), lineWidth: 0.5) : nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Color.clear
                                        .frame(height: 26)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            
                            // Week total column
                            Text(weekPnl != 0 ? Formatters.formatPnL(weekPnl, currency: env.currentCurrency) : "–")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(weekPnl > 0 ? AppColors.profit : (weekPnl < 0 ? AppColors.loss : AppColors.secondaryText))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.6))
                
                HStack {
                    Text("\(snap.currentMonthStats.tradingDays) trading days · \(snap.currentMonthStats.winningDays) green")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text("Month: \(Formatters.formatPnL(snap.currentMonthStats.monthPnl, currency: env.currentCurrency))")
                        .font(AppTypography.captionBold)
                        .monospacedDigit()
                        .foregroundColor(snap.currentMonthStats.monthPnl >= 0 ? AppColors.profit : AppColors.loss)
                }
            }
        }
    }
    
    // Widget 9: Activity (Recent trades & Open positions)
    @ViewBuilder
    private func widget9Activity(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Activity")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                // Apple HIG Sliding Pill Segmented Control
                HStack(spacing: 4) {
                    ForEach(["recent", "open"], id: \.self) { tab in
                        let isSelected = activityTab == tab
                        Button {
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                activityTab = tab
                            }
                        } label: {
                            Text(tab == "recent" ? "Recent Trades" : "Open Positions")
                                .font(AppTypography.captionBold)
                                .foregroundColor(isSelected ? .white : AppColors.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? AppColors.brand : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(3)
                .background(AppColors.secondaryBackground)
                .clipShape(Capsule())
                
                if activityTab == "recent" {
                    let recentTrades = Array(scopedTrades.filter { $0.closedAt != nil }.prefix(5))
                    if recentTrades.isEmpty {
                        Text("No recent closed trades.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(recentTrades) { trade in
                                NavigationLink(destination: TradeDetailView(trade: trade)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(trade.symbol)
                                                    .font(AppTypography.bodyBold)
                                                    .foregroundColor(AppColors.primaryText)
                                                
                                                Text(trade.direction.rawValue.uppercased())
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(trade.direction == .long ? AppColors.profit.opacity(0.15) : AppColors.loss.opacity(0.15))
                                                    .foregroundColor(trade.direction == .long ? AppColors.profit : AppColors.loss)
                                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                            }
                                            
                                            if let closed = trade.closedAt {
                                                Text(closed.formatted(date: .abbreviated, time: .shortened))
                                                    .font(AppTypography.caption)
                                                    .foregroundColor(AppColors.secondaryText)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if let pnl = trade.netPnl {
                                            AppMonetaryText(
                                                Formatters.formatPnL(pnl, currency: trade.currency),
                                                isPrivate: env.isPrivacyModeEnabled,
                                                font: AppTypography.financialNumber(size: 14, weight: .bold),
                                                color: pnl >= 0 ? AppColors.profit : AppColors.loss
                                            )
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                
                                if trade.id != recentTrades.last?.id {
                                    Divider().background(AppColors.border.opacity(0.4))
                                }
                            }
                        }
                    }
                } else {
                    let openTrades = scopedTrades.filter { $0.status == .open }
                    if openTrades.isEmpty {
                        Text("No open positions.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(openTrades) { trade in
                                NavigationLink(destination: TradeDetailView(trade: trade)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(trade.symbol)
                                                .font(AppTypography.bodyBold)
                                                .foregroundColor(AppColors.primaryText)
                                            Text("Opened \(trade.openedAt.formatted(date: .abbreviated, time: .shortened))")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        Spacer()
                                        Text(trade.direction.rawValue.uppercased())
                                            .font(AppTypography.captionBold)
                                            .foregroundColor(trade.direction == .long ? AppColors.profit : AppColors.loss)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Widget 10: Max drawdown (TrendingDown)
    @ViewBuilder
    private func widget10MaxDrawdown(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Max drawdown",
                    icon: "chart.line.downtrend.xyaxis",
                    hint: "Largest peak-to-trough drop of the cumulative P&L curve."
                )
                
                Spacer(minLength: 4)
                
                AppMonetaryText(
                    Formatters.formatCurrency(metrics.maxDrawdown, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 20, weight: .bold),
                    color: AppColors.loss
                )
                
                HStack(spacing: 3) {
                    Text(metrics.maxDrawdownPct != nil ? String(format: "-%.1f%%", metrics.maxDrawdownPct! * 100) : "set balance for %")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if let rec = metrics.recoveryFactor {
                        Text("· rec \(String(format: "%.1f", rec))x")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 11: Streaks (Flame)
    @ViewBuilder
    private func widget11Streaks(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Streaks",
                    icon: "flame",
                    hint: "Current run of consecutive wins (W) or losses (L), with the best and worst runs."
                )
                
                Spacer(minLength: 4)
                
                Text(metrics.currentStreak > 0 ? "\(metrics.currentStreak)W" : (metrics.currentStreak < 0 ? "\(-metrics.currentStreak)L" : "–"))
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(metrics.currentStreak > 0 ? AppColors.profit : (metrics.currentStreak < 0 ? AppColors.loss : AppColors.primaryText))
                
                Text("best \(metrics.maxWinStreak)W · worst \(metrics.maxLossStreak)L")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 12: Expectancy / trade (Sigma)
    @ViewBuilder
    private func widget12Expectancy(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Expectancy / trade",
                    icon: "sum",
                    hint: "Average net P&L per closed trade: what one more trade is worth on your numbers."
                )
                
                Spacer(minLength: 4)
                
                AppMonetaryText(
                    metrics.expectancy != nil ? Formatters.formatPnL(metrics.expectancy!, currency: env.currentCurrency) : "–",
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 20, weight: .bold),
                    color: (metrics.expectancy ?? 0) >= 0 ? AppColors.profit : AppColors.loss
                )
                
                Text(metrics.avgRealizedR != nil && metrics.tradesWithRisk > 0 ? String(format: "avg %.2fR over %d trades", metrics.avgRealizedR!, metrics.tradesWithRisk) : "tag stops for R multiples")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 13: Avg duration (Timer)
    @ViewBuilder
    private func widget13AvgDuration(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Avg duration",
                    icon: "timer",
                    hint: "Average time from first entry fill to final exit."
                )
                
                Spacer(minLength: 4)
                
                Text(Formatters.formatDuration(ms: metrics.avgDurationMs))
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                Text("winners vs losers in Reports")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 14: Best / worst day (Trophy)
    @ViewBuilder
    private func widget14BestWorstDay(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Best / worst day",
                    icon: "trophy",
                    hint: "Highest and lowest single-day net P&L in the selected range."
                )
                
                Spacer(minLength: 4)
                
                if let best = snap.bestDay, let worst = snap.worstDay {
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
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 15: Trade time performance (Clock)
    @ViewBuilder
    private func widget15TradeTimePerformance(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Trade time performance",
                    icon: "clock",
                    hint: "Trades grouped by their opening hour. The upper chart shows net P&L; the lower chart shows trade count."
                )
                
                if snap.hourlyStats.isEmpty {
                    Text("No hourly trade data available.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    TimeHeatmapView(
                        hours: snap.hourlyStats,
                        currency: env.currentCurrency,
                        isPrivate: env.isPrivacyModeEnabled
                    )
                }
            }
        }
    }
    
    // MARK: - Apple HIG Reusable Card Container & Header
    
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    private func statHeader(_ title: String, icon: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(AppTypography.cardTitle)
                .foregroundColor(AppColors.primaryText)
            Spacer()
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                activeTooltip = (title: title, hint: hint)
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(AppColors.secondaryBackground.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(ApplePressableButtonStyle())
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
                .monospacedDigit()
                .foregroundColor(AppColors.primaryText)
        }
    }
    
    // MARK: - Day Selection Action
    
    private func openCalendarDay(dateKey: String, stats: DayStats?) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = env.currentTimeZone
        let tradesForDay = dataStore.filteredTrades.filter {
            f.string(from: $0.closedAt ?? $0.openedAt) == dateKey
        }
        let note = dataStore.calendarNotes[dateKey] ?? JournalNote(date: dateKey)
        selectedDayContext = DayDetailContext(
            dateKey: dateKey,
            stats: stats,
            trades: tradesForDay,
            note: note
        )
    }
    
    private func parseDate(from key: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = env.currentTimeZone
        return f.date(from: key) ?? Date()
    }
}

// MARK: - Dashboard Card Wrapper with Interactive Reorder Bar

private struct DashboardCardWrapper<Content: View>: View {
    let cardId: String
    let isEditing: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onHide: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing, let item = DashboardCardRegistry.item(for: cardId) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(item.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Move Up Button
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(.plain)
                    
                    // Move Down Button
                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(.plain)
                    
                    // Hide Button
                    Button {
                        onHide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.loss)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 6)
            }
            
            content()
        }
        .overlay(
            isEditing ?
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.brand.opacity(0.4), lineWidth: 1.5)
                : nil
        )
    }
}
