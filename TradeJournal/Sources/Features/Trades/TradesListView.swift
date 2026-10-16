import SwiftUI

public enum TradeStatusFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case win = "Lãi"
    case loss = "Lỗ"
    case open = "Đang mở"
    
    public var id: String { rawValue }
}

public struct TradesListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showAddTradeSheet: Bool = false
    @State private var searchText: String = ""
    @State private var statusFilter: TradeStatusFilter = .all
    
    public init() {}
    
    private var filteredTrades: [Trade] {
        var list = dataStore.filteredTrades
        
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
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterPicker
                
                if let summary = dataStore.lastSyncSummary {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.profit)
                        Text(summary)
                            .font(AppTypography.caption)
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
                    .padding(.vertical, 6)
                    .background(AppColors.profit.opacity(0.12))
                    .cornerRadius(6)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                
                if let err = dataStore.lastSyncError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.loss)
                        Text(err)
                            .font(AppTypography.caption)
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
                    .padding(.vertical, 6)
                    .background(AppColors.loss.opacity(0.12))
                    .cornerRadius(6)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                
                if filteredTrades.isEmpty {
                    emptyState
                } else {
                    tradesList
                }
            }
            .navigationTitle("Giao Dịch")
            .searchable(text: $searchText, prompt: "Tìm theo mã (symbol), tag hoặc ghi chú...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("Tất cả tài khoản") {
                            dataStore.selectedAccountId = "all"
                        }
                        ForEach(dataStore.accounts) { acc in
                            Button(acc.name.isEmpty ? acc.id : acc.name) {
                                dataStore.selectedAccountId = acc.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle")
                            Text(dataStore.selectedAccountId == "all" ? "Tất cả" : (dataStore.selectedAccount?.name ?? "Tài khoản"))
                                .font(AppTypography.caption)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            Task { await dataStore.syncWithSupabase() }
                        } label: {
                            Image(systemName: dataStore.isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                        }
                        
                        Button(action: { showAddTradeSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddTradeSheet) {
                AddTradeSheet()
            }
        }
    }
    
    private var filterPicker: some View {
        Picker("Lọc trạng thái", selection: $statusFilter) {
            ForEach(TradeStatusFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var tradesList: some View {
        List {
            ForEach(filteredTrades) { trade in
                NavigationLink(destination: TradeDetailView(trade: trade)) {
                    TradeRowCard(trade: trade)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        dataStore.deleteTrade(key: trade.key)
                    } label: {
                        Label("Xóa", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 30)
                
                Image(systemName: "chart.line.uptrend.xyaxis.circle")
                    .font(.system(size: 56))
                    .foregroundColor(AppColors.accent)
                
                VStack(spacing: 8) {
                    Text("Chưa Có Giao Dịch Nào")
                        .font(AppTypography.title)
                    Text("Đồng bộ trực tiếp từ Supabase hoặc The5ers MCP Hub, hoặc nhập file sao kê CSV của bạn.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(spacing: 12) {
                    AppButton("Đồng Bộ Supabase", icon: "arrow.triangle.2.circlepath", style: .primary) {
                        Task { await dataStore.syncWithSupabase() }
                    }
                    
                    AppButton("Đồng Bộ The5ers MCP", icon: "network", style: .secondary) {
                        Task { _ = try? await dataStore.syncWithThe5ers() }
                    }
                    
                    AppButton("Ghi Nhận Giao Dịch Mới", icon: "plus.circle", style: .secondary) {
                        showAddTradeSheet = true
                    }
                    
                    AppButton("Nhập File CSV Sao Kê", icon: "doc.text", style: .secondary) {
                        env.selectedTab = .importStatement
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TradeRowCard: View {
    @EnvironmentObject private var env: AppEnvironment
    let trade: Trade
    
    var body: some View {
        AppCard {
            HStack(alignment: .center) {
                tradeInfoColumn
                Spacer()
                tradeFinancialColumn
            }
        }
    }
    
    private var tradeInfoColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(trade.symbol)
                    .font(AppTypography.headline)
                AppBadge(
                    trade.direction == .long ? "LONG" : "SHORT",
                    color: trade.direction == .long ? AppColors.accent : AppColors.warning
                )
                AppBadge(
                    trade.status.rawValue.uppercased(),
                    color: trade.status == .win ? AppColors.profit : (trade.status == .loss ? AppColors.loss : AppColors.breakeven)
                )
            }
            
            Text("Vào: \(Formatters.price(trade.avgEntry)) • KL: \(trade.quantity)")
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
            
            if !trade.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(trade.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
        }
    }
    
    private var tradeFinancialColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(Formatters.pnl(trade.netPnl, currencyCode: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled))
                .font(AppTypography.financialNumber(size: 16, weight: .bold))
                .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
            
            Text(Formatters.dateOnly(trade.openedAt, timeZone: env.currentTimeZone))
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
            
            if let r = trade.rating, r > 0 {
                HStack(spacing: 2) {
                    ForEach(1...r, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
    }
}
