import SwiftUI

public enum TradeStatusFilter: String, CaseIterable, Identifiable {
    case all = "All Status"
    case win = "Win"
    case loss = "Loss"
    case open = "Open"
    
    public var id: String { rawValue }
}

public struct TradesListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var selectedRange: JournalTimeRange = .all
    @State private var showAddTradeSheet: Bool = false
    @State private var searchText: String = ""
    @State private var statusFilter: TradeStatusFilter = .all
    
    public init() {}
    
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
    
    private var filteredTrades: [Trade] {
        var list = scopedTrades
        
        switch statusFilter {
        case .all:
            break
        case .win:
            list = list.filter { $0.status == .win }
        case .loss:
            list = list.filter { $0.status == .loss }
        case .open:
            list = list.filter { $0.status == .open }
        }
        
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.symbol.lowercased().contains(q) ||
                $0.tags.contains(where: { $0.lowercased().contains(q) }) ||
                ($0.notes?.lowercased().contains(q) ?? false)
            }
        }
        
        return list.sorted { $0.openedAt > $1.openedAt }
    }
    
    private var overviewMetrics: TradeMetrics {
        FinancialMetricsEngine.computeMetrics(
            trades: scopedTrades,
            timeZone: env.currentTimeZone
        )
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // FilterBar matching web filter-bar.tsx
                FilterBarView(
                    title: "Trades",
                    selectedRange: $selectedRange,
                    showFilters: true
                ) {
                    HStack(spacing: 6) {
                        AppButton("Add trade", icon: "plus", style: .primary) {
                            showAddTradeSheet = true
                        }
                    }
                }
                
                ScrollView {
                    VStack(spacing: 12) {
                        summaryCardsGrid
                        searchAndStatusFilter
                        tradesListContent
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
            .sheet(isPresented: $showAddTradeSheet) {
                AddTradeSheet()
            }
        }
    }
    
    @ViewBuilder
    private var summaryCardsGrid: some View {
        let isProfit = overviewMetrics.netPnl >= 0
        let pnlColor = isProfit ? AppColors.profit : AppColors.loss
        let pfStr = overviewMetrics.profitFactorIsInfinite ? "∞" : (overviewMetrics.profitFactor != nil ? String(format: "%.2f", overviewMetrics.profitFactor!) : "–")
        let winRateStr = overviewMetrics.winRate != nil ? String(format: "%.1f%%", overviewMetrics.winRate! * 100) : "–"
        let avgWlStr = overviewMetrics.avgWinLossRatio != nil ? String(format: "%.2f", overviewMetrics.avgWinLossRatio!) : "–"
        
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Net cumulative P&L")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        AppMonetaryText(
                            Formatters.formatPnL(overviewMetrics.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 20, weight: .semibold),
                            color: pnlColor
                        )
                        Text("\(overviewMetrics.closedTrades) trades")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Profit factor")
                    Text(pfStr)
                        .font(AppTypography.financialNumber(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                }
            }
            
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Trade win %")
                    Text(winRateStr)
                        .font(AppTypography.financialNumber(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                }
            }
            
            AppCard {
                VStack(alignment: .leading, spacing: 4) {
                    AppCardHeader("Avg win / loss")
                    Text(avgWlStr)
                        .font(AppTypography.financialNumber(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchAndStatusFilter: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText)
                TextField("Search symbol, tag...", text: $searchText)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppColors.cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            
            Picker("Status", selection: $statusFilter) {
                ForEach(TradeStatusFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppColors.cardBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private var tradesListContent: some View {
        if filteredTrades.isEmpty {
            AppCard {
                VStack(spacing: 12) {
                    Text("No trades match these filters.")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(filteredTrades) { trade in
                    NavigationLink(destination: TradeDetailView(trade: trade)) {
                        TradeTerminalRow(trade: trade)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct TradeTerminalRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let trade: Trade
    
    var body: some View {
        AppCard {
            HStack(alignment: .center, spacing: 10) {
                // Status badge
                AppBadge(
                    trade.status.rawValue.uppercased(),
                    color: Formatters.statusColor(trade.status)
                )
                
                // Position badge
                AppBadge(
                    trade.direction == .long ? "Long" : "Short",
                    variant: .secondary
                )
                
                // Symbol & Entry Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(trade.symbol)
                        .font(AppTypography.bodyBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    HStack(spacing: 4) {
                        Text(trade.closedAt != nil ? Formatters.dateOnly(trade.closedAt!, timeZone: env.currentTimeZone) : "open")
                        Text("·")
                        Text("Vol: \(Formatters.formatNumber(trade.quantity))")
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                }
                
                Spacer()
                
                // Financials P&L and prices
                VStack(alignment: .trailing, spacing: 2) {
                    AppMonetaryText(
                        Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 14, weight: .semibold),
                        color: trade.netPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    Text("Entry \(Formatters.price(trade.avgEntry))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }
}
