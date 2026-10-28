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
    
    @State private var showAddTradeSheet: Bool = false
    @State private var showPreTradeSheet: Bool = false
    @State private var searchText: String = ""
    @State private var statusFilter: TradeStatusFilter = .all
    @State private var selectedTrade: Trade? = nil
    
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
        dataStore.selectedTimeRange.filterTrades(dataStore.filteredTrades, timeZone: env.currentTimeZone)
    }
    
    private var filteredTrades: [Trade] {
        let key = "\(dataStore.selectedTimeRange.rawValue)_\(statusFilter.rawValue)_\(searchText)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)"
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
        let key = "\(dataStore.selectedTimeRange.rawValue)_\(dataStore.selectedAccountId)_\(dataStore.filteredTrades.count)_\(dataStore.cacheVersion)"
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
        ScrollView {
            VStack(spacing: 14) {
                summaryCardsGrid
                searchAndStatusFilter
                tradesListContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .refreshable {
            await Task {
                await dataStore.performGlobalSync()
            }.value
        }
        .background(AppColors.background)
        .sheet(isPresented: $showAddTradeSheet) {
            AddTradeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showPreTradeSheet) {
            PreTradeAnalysisSheet()
        }
        .sheet(item: $selectedTrade) { trade in
            TradeDetailView(trade: trade, isModal: true)
                .id(trade.key)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
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
                        .lineLimit(1)
                    
                    AppMonetaryText(
                        Formatters.formatPnL(overviewMetrics.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 19, weight: .bold),
                        color: pnlColor
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    
                    HStack(spacing: 4) {
                        Text("\(overviewMetrics.closedTrades) closed")
                        Text("·")
                        Text("Fees \(Formatters.formatCurrency(overviewMetrics.fees ?? 0, currency: env.currentCurrency))")
                    }
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROFIT FACTOR")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                        .lineLimit(1)
                    
                    Text(pfStr)
                        .font(AppTypography.financialNumber(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text("Payoff efficiency")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRADE WIN %")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                        .lineLimit(1)
                    
                    Text(winRateStr)
                        .font(AppTypography.financialNumber(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text("\(overviewMetrics.winningTrades)W · \(overviewMetrics.losingTrades)L")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
            
            cardContainer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AVG WIN / LOSS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                        .lineLimit(1)
                    
                    Text(avgWlStr)
                        .font(AppTypography.financialNumber(size: 19, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text("Expectancy multiple")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
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
            
            Button {
                showPreTradeSheet = true
            } label: {
                Text("Pre-Trade")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(height: 40)
                    .padding(.horizontal, 12)
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
                    Button {
                        selectedTrade = trade
                    } label: {
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
        }
    }
}

private struct TradeTerminalRow: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var dataStore: TradeDataStore
    let trade: Trade
    
    private var durationText: String? {
        if let dur = trade.durationMs, dur > 0 {
            let minutes = dur / 60_000
            if minutes < 60 {
                return "\(minutes)m"
            } else {
                let hours = minutes / 60
                let remMin = minutes % 60
                return remMin > 0 ? "\(hours)h \(remMin)m" : "\(hours)h"
            }
        }
        if let closed = trade.closedAt {
            let diff = Int(closed.timeIntervalSince(trade.openedAt) / 60)
            if diff > 0 {
                if diff < 60 { return "\(diff)m" }
                return "\(diff / 60)h \(diff % 60)m"
            }
        }
        return trade.status == .open ? "Holding" : nil
    }
    
    private var dateDisplay: String {
        let d = trade.closedAt ?? trade.openedAt
        let time = Formatters.formatTime(d)
        let date = Formatters.dateOnly(d, timeZone: env.currentTimeZone)
        return "\(time) · \(date)"
    }
    
    private var rMultiple: Double? {
        TradeAnalysisEngine.tradeR(trade: trade)
    }
    
    private var playbookName: String? {
        guard let id = trade.playbookId, !id.isEmpty else { return nil }
        return dataStore.playbooks.first(where: { $0.id == id })?.name ?? id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topLineView
            Divider().background(AppColors.border.opacity(0.35))
            middleLineView
            bottomLineView
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1.5)
    }
    
    @ViewBuilder
    private var topLineView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Symbol + Direction pill
            HStack(spacing: 6) {
                Text(trade.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Text(trade.direction == .long ? "LONG" : "SHORT")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((trade.direction == .long ? AppColors.brand : AppColors.warning).opacity(0.12))
                    .clipShape(Capsule())
                    .lineLimit(1)
                
                AppBadge(
                    trade.status.rawValue.uppercased(),
                    color: Formatters.statusColor(trade.status)
                )
            }
            
            Spacer(minLength: 4)
            
            // Net PnL (prominent)
            VStack(alignment: .trailing, spacing: 1) {
                AppMonetaryText(
                    Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 16, weight: .bold),
                    color: trade.netPnl >= 0 ? AppColors.profit : AppColors.loss
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                
                if let r = rMultiple {
                    Text("\(r >= 0 ? "+" : "")\(Formatters.formatNumber(r))R")
                        .font(AppTypography.number(11, weight: .semibold))
                        .foregroundColor(r >= 0 ? AppColors.profit : AppColors.loss)
                        .lineLimit(1)
                }
            }
        }
    }
    
    @ViewBuilder
    private var middleLineView: some View {
        HStack(alignment: .center) {
            // Entry -> Exit price path
            HStack(spacing: 4) {
                Text(Formatters.price(trade.avgEntry, symbol: trade.symbol))
                    .font(AppTypography.number(12, weight: .medium))
                    .foregroundColor(AppColors.primaryText)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                
                if let exit = trade.avgExit {
                    Text(Formatters.price(exit, symbol: trade.symbol))
                        .font(AppTypography.number(12, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                } else {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                }
            }
            .lineLimit(1)
            
            Spacer(minLength: 8)
            
            // Volume and Duration
            HStack(spacing: 6) {
                Text("\(Formatters.formatNumber(trade.quantity)) lots")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                
                if let dur = durationText {
                    Text("·")
                        .foregroundColor(AppColors.secondaryText.opacity(0.5))
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(dur)
                    }
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
                }
            }
            .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var bottomLineView: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 4) {
                if let setup = playbookName {
                    HStack(spacing: 3) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9))
                        Text(setup)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.brand.opacity(0.10))
                    .foregroundColor(AppColors.brand)
                    .clipShape(Capsule())
                    .lineLimit(1)
                }
                
                ForEach(trade.tags.prefix(2), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.secondaryBackground)
                        .foregroundColor(AppColors.secondaryText)
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 6)
            
            Text(dateDisplay)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
        }
    }
}
