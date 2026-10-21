import SwiftUI
import Charts

public struct DashboardView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var dataStore = TradeDataStore.shared
    
    @AppStorage("dashboard_hidden_widgets") private var hiddenWidgetsRaw: String = ""
    @AppStorage("dashboard_card_order") private var cardOrderRaw: String = ""
    @AppStorage("dashboard_active_preset") private var activePresetRaw: String = "Overview"
    
    @State var isEditingLayout: Bool = false
    @State var showEdgeScoreBreakdown: Bool = false
    @State private var showCustomizerSheet: Bool = false
    @State private var showAIReflection: Bool = false
    @State private var showAddTradeSheet: Bool = false
    @State var activityTab: String = "recent" // "recent" or "open"
    @State var activeTooltip: (title: String, hint: String)? = nil
    
    // Day detail sheet integration for Widget 8 (Calendar)
    @State var selectedDayContext: DayDetailContext? = nil
    @State private var addTradeDate: Date? = nil
    
    private static let dashboardUtcDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()
    
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
    
    var scopedTrades: [Trade] {
        dataStore.selectedTimeRange.filterTrades(dataStore.filteredTrades, timeZone: env.currentTimeZone)
    }
    
    // MARK: - Memoized Single-Pass Snapshot
    
    struct DashboardSnapshot {
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
    
    @State private var cache = DashboardCache()
    
    @MainActor
    private final class DashboardCache {
        var lastKey: String = ""
        var lastSnapshot: DashboardSnapshot? = nil
    }
    
    private static let monthPrefixFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()
    
    private var snapshot: DashboardSnapshot {
        let key = "\(dataStore.selectedTimeRange.rawValue)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.visibleAccounts.count)_\(dataStore.cacheVersion)_\(env.currentTimeZone.identifier)"
        if cache.lastKey == key, let cached = cache.lastSnapshot {
            return cached
        }
        let fresh = computeSnapshot()
        cache.lastKey = key
        cache.lastSnapshot = fresh
        return fresh
    }
    
    private func computeSnapshot() -> DashboardSnapshot {
        // Balances are stored in the account currency while every P&L figure is expressed in the
        // reporting currency, so balances are converted before being compared with the P&L curve.
        let initialBalance: Decimal = {
            if dataStore.selectedAccountId == "all" {
                return dataStore.visibleAccounts.reduce(Decimal.zero) { total, account in
                    total + dataStore.currencyConversion.convertedBalance(account.initialBalance, currency: account.currency)
                }
            }
            let account = dataStore.selectedAccount
            guard let account else { return 0 }
            return dataStore.currencyConversion.convertedBalance(account.initialBalance, currency: account.currency)
        }()
        
        let overview = FinancialMetricsEngine.computeOverview(
            trades: scopedTrades,
            timeZone: env.currentTimeZone,
            initialBalance: initialBalance
        )
        
        let edge = EdgeScoreEngine.computeEdgeScore(metrics: overview.metrics)
        
        let dailyCurve = FinancialMetricsEngine.dailyCumulativeFromDays(days: overview.days)
        let rdCurve = FinancialMetricsEngine.relativeDrawdownCurve(curve: dailyCurve, initialBalance: initialBalance)
        
        var dayMap: [String: DayStats] = [:]
        for d in overview.days {
            dayMap[d.date] = d
        }
        
        let chartPoints: [EquityPointItem] = zip(dailyCurve, rdCurve).map { dc, rd in
            let dayStat = dayMap[dc.dateString]
            let dayPnl = dayStat?.netPnl ?? 0
            let ddDecimal = Decimal(rd.drawdownPct ?? 0)
            return EquityPointItem(
                date: dc.timestamp,
                dateKey: dc.dateString,
                netPnl: dayPnl,
                cumulativePnl: dc.cumNetPnl,
                drawdown: ddDecimal
            )
        }
        
        let hourly = AggregateEngine.byHour(trades: scopedTrades, timeZone: env.currentTimeZone)
        
        // Momentum: net P&L of the last 7 calendar days vs the 7 before them (matching page.tsx lines 207-224)
        let nowMs = Date().timeIntervalSince1970 * 1000
        var last: Decimal = 0
        var prior: Decimal = 0
        var lastDays = 0
        var priorDays = 0
        
        for day in overview.days {
            if let date = Self.dashboardUtcDateFormatter.date(from: day.date) {
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
        
        let prefix = Self.monthPrefixFormatter.string(from: Date())
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
    
    private var currencyGroups: [(currency: String, metrics: TradeMetrics, balance: Decimal)] {
        let visibleAccs = dataStore.visibleAccounts
        let currencies = Array(Set(visibleAccs.map { $0.currency.uppercased() })).sorted()
        return currencies.map { curr in
            let accIds = Set(visibleAccs.filter { $0.currency.uppercased() == curr }.map { $0.id })
            let tradesForCurr = scopedTrades.filter { accIds.contains($0.accountId) || accIds.contains("the5ers_\($0.accountId)") }
            let initBal = visibleAccs.filter { $0.currency.uppercased() == curr }.reduce(Decimal.zero) { total, account in
                total + dataStore.currencyConversion.convertedBalance(account.initialBalance, currency: account.currency)
            }
            let ov = FinancialMetricsEngine.computeOverview(trades: tradesForCurr, timeZone: env.currentTimeZone, initialBalance: initBal)
            return (curr, ov.metrics, initBal)
        }
    }
    
    // MARK: - Calendar Widget Helpers
    
    var calendarWeeks: [[Date?]] {
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
    
    var monthName: String {
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
        
        ScrollView {
            LazyVStack(spacing: 12) {
                syncNotificationSection
                
                if isEditingLayout {
                    reorderBanner
                }
                
                if isMultiCurrencyNoticeActive {
                    // Multi-currency notice & account breakdown matching page.tsx lines 153-188
                    multiCurrencySection
                } else if metrics.totalTrades == 0 {
                    if dataStore.selectedTimeRange != .all {
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
                
                // Bottom dashboard controls (Overview Presets & Customize)
                dashboardActions
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 88)
        }
        .refreshable {
            await dataStore.performGlobalSync()
        }
        .background(AppColors.background)
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
                .lineLimit(1)
            
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
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
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
    
    // MARK: - Secondary Dashboard Actions (Integrated into FilterBarView)
    
    private var dashboardActions: some View {
        HStack(spacing: 10) {
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
                HStack(spacing: 6) {
                    Image(systemName: activePreset.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    Text(activePreset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            
            // Customize button (Sheet)
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showCustomizerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Customize")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
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
    
    func moveCard(cardId: String, direction: Int) {
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
    
    func hideCard(cardId: String) {
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
                    
                    Text("These accounts use \(dataStore.availableCurrencies.joined(separator: ", ")). Balances are converted to \(dataStore.currencyConversion.reportingCurrency) with the rates configured under Settings; every P&L figure below is already expressed in \(dataStore.currencyConversion.reportingCurrency).")
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
                    Text("ALL ACCOUNTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Text("\(totalClosed) closed trades · \(combinedWinRate.map { String(format: "%.1f%%", $0 * 100) } ?? "–") trade win rate")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            // Per-Currency Account Cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(currencyGroups, id: \.currency) { group in
                    cardContainer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.currency) ACCOUNTS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .tracking(0.5)
                            
                            AppMonetaryText(
                                Formatters.formatPnL(group.metrics.netPnl, currency: dataStore.currencyConversion.reportingCurrency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 20, weight: .bold),
                                color: group.metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                            )
                            
                            Text("\(group.metrics.closedTrades) closed · \(group.metrics.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "–") win")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Text("Balance \(Formatters.formatCurrency(group.balance, currency: dataStore.currencyConversion.reportingCurrency))")
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
                        dataStore.selectedTimeRange = .all
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
                
                HStack(spacing: 8) {
                    AppButton("Sync Center", icon: "arrow.triangle.2.circlepath", style: .primary) {
                        env.showSyncCenter = true
                    }
                    
                    AppButton("Import file", icon: "square.and.arrow.down", style: .secondary) {
                        env.selectedTab = .importTrades
                    }
                    
                    AppButton("Demo data", icon: "sparkles", style: .secondary) {
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
}
