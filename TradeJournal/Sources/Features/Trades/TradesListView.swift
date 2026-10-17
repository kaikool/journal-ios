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
                    VStack(spacing: 14) {
                        summaryCardsGrid
                        searchAndStatusFilter
                        tradesListContent
                    }
                    .padding(16)
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
        let pfStr = overviewMetrics.profitFactorIsInfinite ? "∞" : (overviewMetrics.profitFactor != nil ? String(format: "%.2f", overviewMetrics.profitFactor!) : "–")
        let winRateStr = overviewMetrics.winRate != nil ? String(format: "%.1f%%", overviewMetrics.winRate! * 100) : "–"
        let avgWlStr = overviewMetrics.avgWinLossRatio != nil ? String(format: "%.2f", overviewMetrics.avgWinLossRatio!) : "–"
        
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net cumulative P&L")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    AppMonetaryText(
                        Formatters.formatPnL(overviewMetrics.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 19, weight: .bold),
                        color: pnlColor
                    )
                    
                    Text("\(overviewMetrics.closedTrades) closed trades")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profit factor")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
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
                    Text("Trade win %")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
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
                    Text("Avg win / loss")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
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
                    .font(AppTypography.body)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
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
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
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
                    NavigationLink(destination: TradeDetailView(trade: trade)) {
                        TradeTerminalRow(trade: trade)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
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
                    Text(trade.closedAt != nil ? Formatters.dateOnly(trade.closedAt!, timeZone: env.currentTimeZone) : "Open")
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
                
                Text("Entry \(Formatters.price(trade.avgEntry))")
                    .font(AppTypography.caption)
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
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
