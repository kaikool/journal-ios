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
    
    @State private var cache = TradesListCache()
    
    @MainActor
    private final class TradesListCache {
        var lastMetricsKey: String = ""
        var lastMetrics: TradeMetrics? = nil
        var lastFilterKey: String = ""
        var lastFilteredTrades: [Trade] = []
    }
    
    private var scopedTrades: [Trade] {
        selectedRange.filterTrades(dataStore.filteredTrades, timeZone: env.currentTimeZone)
    }
    
    private var filteredTrades: [Trade] {
        let key = "\(selectedRange.rawValue)_\(statusFilter.rawValue)_\(searchText)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)"
        if cache.lastFilterKey == key {
            return cache.lastFilteredTrades
        }
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
        
        let sorted = list.sorted { $0.openedAt > $1.openedAt }
        cache.lastFilterKey = key
        cache.lastFilteredTrades = sorted
        return sorted
    }
    
    private var overviewMetrics: TradeMetrics {
        let key = "\(selectedRange.rawValue)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)"
        if cache.lastMetricsKey == key, let m = cache.lastMetrics {
            return m
        }
        let fresh = FinancialMetricsEngine.computeMetrics(
            trades: scopedTrades,
            timeZone: env.currentTimeZone
        )
        cache.lastMetricsKey = key
        cache.lastMetrics = fresh
        return fresh
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact time-range filter strip sitting flush under ShellHeaderView
                FilterBarView(
                    title: "",
                    selectedRange: $selectedRange,
                    showAccountSelector: false,
                    showFilters: true
                )
                
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCardsGrid
                        searchAndStatusFilter
                        tradesListContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 88)
                }
                .refreshable {
                    await dataStore.performGlobalSync()
                }
                .background(AppColors.background)
            }
            .sheet(isPresented: $showAddTradeSheet) {
                AddTradeSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    @ViewBuilder
    private var summaryCardsGrid: some View {
        let isProfit = overviewMetrics.netPnl >= 0
        let pnlColor = isProfit ? AppColors.profit : AppColors.loss
        let pfStr = overviewMetrics.profitFactorIsInfinite ? "∞" : (overviewMetrics.profitFactor.map { String(format: "%.2f", $0) } ?? "–")
        let winRateStr = overviewMetrics.winRate.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
        let avgWlStr = overviewMetrics.avgWinLossRatio.map { String(format: "%.2f", $0) } ?? "–"
        
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NET CUMULATIVE P&L")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    AppMonetaryText(
                        Formatters.formatPnL(overviewMetrics.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 19, weight: .bold),
                        color: pnlColor
                    )
                    
                    Text("\(overviewMetrics.closedTrades) closed · Gross \(Formatters.formatPnL(overviewMetrics.grossPnl ?? overviewMetrics.netPnl, currency: env.currentCurrency)) · Fees \(Formatters.formatCurrency(overviewMetrics.fees ?? 0, currency: env.currentCurrency))")
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROFIT FACTOR")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Text(pfStr)
                        .font(AppTypography.financialNumber(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Payoff efficiency")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRADE WIN %")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Text(winRateStr)
                        .font(AppTypography.financialNumber(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("\(overviewMetrics.winningTrades)W · \(overviewMetrics.losingTrades)L")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AVG WIN / LOSS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Text(avgWlStr)
                        .font(AppTypography.financialNumber(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Expectancy multiple")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchAndStatusFilter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.secondaryText)
                TextField("Search symbol, tag, notes...", text: $searchText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(AppColors.primaryText)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 12)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            
            Menu {
                ForEach(TradeStatusFilter.allCases) { f in
                    Button(f.rawValue) {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        statusFilter = f
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(statusFilter.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(height: 40)
                .padding(.horizontal, 14)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }
    
    @ViewBuilder
    private var tradesListContent: some View {
        if filteredTrades.isEmpty {
            cardContainer {
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.secondaryText)
                    Text("No trades match these filters")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Text("Try clearing your search query or selecting a broader range.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filteredTrades) { trade in
                    NavigationLink(value: trade) {
                        TradeTerminalRow(trade: trade)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            dataStore.deleteTrade(key: trade.key)
                        } label: {
                            Label("Delete Trade", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationDestination(for: Trade.self) { trade in
                TradeDetailView(trade: trade)
            }
        }
    }
}

private struct TradeTerminalRow: View {
    @EnvironmentObject private var env: AppEnvironment
    let trade: Trade
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Status and direction capsule indicators
            VStack(spacing: 4) {
                AppBadge(
                    trade.status.rawValue.uppercased(),
                    color: Formatters.statusColor(trade.status)
                )
                
                Text(trade.direction == .long ? "LONG" : "SHORT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (trade.direction == .long ? AppColors.brand : AppColors.secondaryText).opacity(0.12)
                    )
                    .clipShape(Capsule())
            }
            
            // Symbol & Entry Info
            VStack(alignment: .leading, spacing: 3) {
                Text(trade.symbol)
                    .font(AppTypography.bodyBold)
                    .foregroundColor(AppColors.primaryText)
                
                HStack(spacing: 4) {
                    Text(trade.closedAt.map { Formatters.dateOnly($0, timeZone: env.currentTimeZone) } ?? "Open")
                    Text("·")
                    Text("Vol: \(Formatters.formatNumber(trade.quantity))")
                        .monospacedDigit()
                }
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            // Financials P&L and prices
            VStack(alignment: .trailing, spacing: 3) {
                AppMonetaryText(
                    Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 15, weight: .bold),
                    color: trade.netPnl >= 0 ? AppColors.profit : AppColors.loss
                )
                
                HStack(spacing: 3) {
                    if trade.fees > 0 {
                        Text("Fee \(Formatters.formatCurrency(trade.fees, currency: env.currentCurrency))")
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        Text("·")
                            .foregroundColor(AppColors.secondaryText.opacity(0.5))
                    }
                    Text("Entry \(Formatters.price(trade.avgEntry))")
                        .foregroundColor(AppColors.secondaryText)
                }
                .font(AppTypography.caption)
                .monospacedDigit()
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.secondaryText.opacity(0.4))
                .padding(.leading, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1.5)
    }
}
