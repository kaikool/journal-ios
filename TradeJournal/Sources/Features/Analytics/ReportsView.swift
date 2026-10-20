import SwiftUI
import Charts

public enum ReportMode: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case trends = "Performance trends"
    case explorer = "Trade explorer"
    case breakdown = "Breakdowns"
    case cross = "Cross-analysis"
    case compare = "Compare groups"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .overview: return "chart.pie"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .explorer: return "list.bullet.rectangle"
        case .breakdown: return "square.grid.2x2"
        case .cross: return "arrow.triangle.swap"
        case .compare: return "person.2"
        }
    }
}

/// Comprehensive Performance Reports and Deep Analytics view.
/// Ported 1:1 from `source-repo/apps/web/src/app/reports/page.tsx`:
/// - FilterBar with title "Reports", time-range filters, and "Ask AI" action button
/// - Mode Selector: Overview, Performance trends, Trade explorer, Breakdowns, Cross-analysis, Compare groups
/// - Overview: 8-KPI summary grid, Weekday breakdown chart, Session breakdown chart
/// - Performance trends: Cumulative Equity Curve and Drawdown chart
/// - Trade explorer: List of filtered trades with badges, status, and P&L
/// - Breakdowns & Cross-analysis: Multi-dimensional grouping table
/// - Compare groups: Strategy and playbook comparison
public struct ReportsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var selectedRange: JournalTimeRange = .all
    @State private var selectedMode: ReportMode = .overview
    @State private var primaryDimension: Dimension = .symbol
    @State private var secondaryDimension: Dimension = .weekday
    @State private var showAiReflectionSheet: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""
    @Namespace private var reportModeNamespace
    
    public init() {}
    
    @State private var cache = ReportsCache()
    
    @MainActor
    private final class ReportsCache {
        var lastKey: String = ""
        var lastMetrics: TradeMetrics? = nil
        var lastGroupKey: String = ""
        var lastGroupResults: [GroupAnalysisResult] = []
    }
    
    private var trades: [Trade] {
        selectedRange.filterTrades(dataStore.filteredTrades, timeZone: env.currentTimeZone)
    }
    
    private var metrics: TradeMetrics {
        let key = "\(selectedRange.rawValue)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)"
        if cache.lastKey == key, let m = cache.lastMetrics {
            return m
        }
        let fresh = FinancialMetricsEngine.computeMetrics(trades: trades)
        cache.lastKey = key
        cache.lastMetrics = fresh
        return fresh
    }
    
    private var groupResults: [GroupAnalysisResult] {
        let sec: Dimension? = selectedMode == .cross ? secondaryDimension : nil
        let groupKey = "\(selectedRange.rawValue)_\(selectedMode.rawValue)_\(primaryDimension.rawValue)_\(secondaryDimension.rawValue)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)"
        if cache.lastGroupKey == groupKey {
            return cache.lastGroupResults
        }
        let fresh = TradeAnalysisEngine.analyzeGroups(
            trades: trades,
            primary: primaryDimension,
            secondary: sec,
            timeZone: env.currentTimeZone.identifier
        )
        cache.lastGroupKey = groupKey
        cache.lastGroupResults = fresh
        return fresh
    }
    
    private var summaryKPIs: [(label: String, value: String, isNet: Bool)] {
        let s = metrics
        let pfStr: String = s.profitFactorIsInfinite ? "∞" : (s.profitFactor.map { String(format: "%.2f", $0) } ?? "–")
        let netStr = s.netPnl >= 0 ? "+\(Formatters.currency(s.netPnl))" : Formatters.currency(s.netPnl)
        let wrStr = s.winRate != nil ? Formatters.percent(s.winRate) : "–"
        let volStr = "\(s.totalVolume.formatted())"
        
        let summary = TradeAnalysisEngine.summarizeGroup(all: trades)
        let avgRealizedR = summary.avgRealizedR
        let avgPlannedR = summary.avgPlannedR
        let avgRStr = avgRealizedR.map { String(format: "%.2f R", $0) } ?? "–"
        let avgPlanRStr = avgPlannedR.map { String(format: "%.2f R", $0) } ?? "–"
        
        return [
            ("Closed trades", "\(s.closedTrades)", false),
            ("Net P&L", netStr, true),
            ("Win rate", wrStr, false),
            ("Profit factor", pfStr, false),
            ("Entry volume", volStr, false),
            ("Avg duration", s.avgDurationMs != nil ? Formatters.formatDuration(ms: s.avgDurationMs) : "–", false),
            ("Avg planned R", avgPlanRStr, false),
            ("Avg realized R", avgRStr, false)
        ]
    }
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Apple HIG Mode Sliding Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ReportMode.allCases) { mode in
                                let isSelected = selectedMode == mode
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                        selectedMode = mode
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: mode.iconName)
                                            .font(.system(size: 11))
                                        Text(mode.rawValue)
                                            .font(AppTypography.captionBold)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(AppColors.cardBackground)
                                                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
                                                .matchedGeometryEffect(id: "ReportModePill", in: reportModeNamespace)
                                        }
                                    }
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                        .padding(4)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }
                    
                    // Selected Mode Content
                    switch selectedMode {
                    case .overview:
                        overviewSection
                    case .trends:
                        trendsSection
                    case .explorer:
                        explorerSection
                    case .breakdown, .cross:
                        breakdownAndCrossSection
                    case .compare:
                        compareSection
                    }
                }
                .padding(.bottom, 88)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                FilterBarView(
                    title: "",
                    selectedRange: $selectedRange,
                    showAccountSelector: false,
                    showFilters: true
                ) {
                    AppActionPill("Ask AI", icon: "sparkles") {
                        showAiReflectionSheet = true
                    }
                }
            }
            .background(AppColors.background)
        .sheet(isPresented: $showAiReflectionSheet) {
            AIReflectionView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showExportSheet) {
            ReviewExportModal(title: "Trade report", exportText: exportText)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }
    
    // MARK: - Sections
    
    private var overviewSection: some View {
        VStack(spacing: 14) {
            // 8 KPI Summary Grid
            cardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text("Performance Summary")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(summaryKPIs, id: \.label) { kpi in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kpi.label.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText)
                                    .tracking(0.5)
                                    .lineLimit(1)
                                Text(kpi.value)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(kpi.isNet ? (metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss) : AppColors.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Weekday breakdown chart
            let weekdayStats = AggregateEngine.byWeekday(trades: trades, timeZone: env.currentTimeZone)
            WeekdayChart(weekdays: weekdayStats, currency: env.currentCurrency)
                .padding(.horizontal, 16)
            
            // Trading session breakdown chart
            let sessionStats = AggregateEngine.bySession(trades: trades)
            SessionBreakdownChart(sessions: sessionStats, currency: env.currentCurrency)
                .padding(.horizontal, 16)
        }
    }
    
    private var trendsSection: some View {
        VStack(spacing: 14) {
            // Cumulative Net Equity Curve
            let initialBalance: Decimal = {
                if dataStore.selectedAccountId == "all" {
                    return dataStore.visibleAccounts.reduce(Decimal.zero) { $0 + $1.initialBalance }
                }
                return dataStore.selectedAccount?.initialBalance ?? 0
            }()
            let overview = FinancialMetricsEngine.computeOverview(trades: trades, timeZone: env.currentTimeZone, initialBalance: initialBalance)
            let dailyCurve = FinancialMetricsEngine.dailyCumulativeFromDays(days: overview.days)
            let rdCurve = FinancialMetricsEngine.relativeDrawdownCurve(curve: dailyCurve, initialBalance: initialBalance)
            let equityPoints: [EquityPointItem] = zip(dailyCurve, rdCurve).map { dc, rd in
                let dayStat = overview.days.first(where: { $0.date == dc.dateString })
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
            
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text("EQUITY CURVE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                    }
                    
                    EquityCurveChart(points: equityPoints, currency: env.currentCurrency, height: 200)
                }
            }
            .padding(.horizontal, 16)
            
            // Drawdown Chart
            cardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.loss)
                        Text("DRAWDOWN ANALYSIS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                    }
                    
                    DrawdownChart(points: equityPoints, height: 120)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var explorerSection: some View {
        VStack(spacing: 14) {
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text("Trade explorer (\(trades.count))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    if trades.isEmpty {
                        Text("No closed trades match these filters.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(trades.prefix(30)) { t in
                                HStack {
                                    Text(t.status.rawValue.uppercased())
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(t.netPnl >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                                        .foregroundColor(t.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        .clipShape(Capsule())
                                    
                                    Text(t.symbol)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text(t.netPnl >= 0 ? "+\(Formatters.currency(t.netPnl))" : Formatters.currency(t.netPnl))
                                        .font(AppTypography.bodyBold)
                                        .monospacedDigit()
                                        .foregroundColor(t.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                .padding(.vertical, 4)
                                
                                if t.id != trades.prefix(30).last?.id {
                                    Divider().background(AppColors.border.opacity(0.3))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var breakdownAndCrossSection: some View {
        VStack(spacing: 14) {
            // Dimension Pickers matching reports/page.tsx line 320-328
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text("Analysis Dimensions")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Group by")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                            
                            AppleMenuChip(
                                selectionText: primaryDimension.label,
                                icon: "square.grid.2x2"
                            ) {
                                ForEach(Dimension.allCases, id: \.self) { dim in
                                    Button(dim.label) {
                                        primaryDimension = dim
                                    }
                                }
                            }
                        }
                        
                        if selectedMode == .cross {
                            Divider()
                                .frame(height: 36)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Then by")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                
                                AppleMenuChip(
                                    selectionText: secondaryDimension.label,
                                    icon: "arrow.triangle.swap"
                                ) {
                                    ForEach(Dimension.allCases, id: \.self) { dim in
                                        Button(dim.label) {
                                            secondaryDimension = dim
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Detailed breakdown results table matching reports/page.tsx line 200-250
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "tablecells")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text(selectedMode == .cross ? "\(primaryDimension.label) × \(secondaryDimension.label)" : "\(primaryDimension.label) Performance")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    
                    if groupResults.isEmpty {
                        Text("No closed trades match these filters.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(groupResults, id: \.row) { g in
                                HStack(alignment: .center, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(g.column.isEmpty ? g.row : "\(g.row) / \(g.column)")
                                            .font(AppTypography.bodyBold)
                                            .foregroundColor(AppColors.primaryText)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
                                        HStack(spacing: 6) {
                                            Text("\(g.summary.trades) trades")
                                                .font(.system(size: 11))
                                                .monospacedDigit()
                                                .foregroundColor(AppColors.secondaryText)
                                                .lineLimit(1)
                                            
                                            if let wr = g.summary.winRate {
                                                Text("• Win \(Int(wr * 100))%")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppColors.primaryText)
                                                    .lineLimit(1)
                                            }
                                            
                                            if let r = g.summary.avgRealizedR {
                                                Text("• \(String(format: "%.1f", r))R")
                                                    .font(.system(size: 11))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppColors.secondaryText)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text(g.summary.netPnl >= 0 ? "+\(Formatters.currency(g.summary.netPnl))" : Formatters.currency(g.summary.netPnl))
                                        .font(AppTypography.bodyBold)
                                        .monospacedDigit()
                                        .foregroundColor(g.summary.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                
                                if g.row != groupResults.last?.row {
                                    Divider().background(AppColors.border.opacity(0.3))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var compareSection: some View {
        VStack(spacing: 14) {
            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.2")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text("Playbooks Comparison")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    let pResults = TradeAnalysisEngine.analyzeGroups(trades: trades, primary: .playbook)
                    if pResults.isEmpty {
                        Text("No playbooks assigned to closed trades.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    } else {
                        ForEach(pResults, id: \.row) { item in
                            HStack {
                                Text(item.row.isEmpty ? "No playbook" : item.row)
                                    .font(AppTypography.bodyBold)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(item.summary.netPnl >= 0 ? "+\(Formatters.currency(item.summary.netPnl))" : Formatters.currency(item.summary.netPnl))
                                    .font(AppTypography.bodyBold)
                                    .monospacedDigit()
                                    .foregroundColor(item.summary.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            
                            if item.row != pResults.last?.row {
                                Divider().background(AppColors.border.opacity(0.3))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
