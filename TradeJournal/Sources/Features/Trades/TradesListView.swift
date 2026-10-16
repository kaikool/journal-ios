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
                // Filter Segmented Bar
                Picker("Lọc trạng thái", selection: $statusFilter) {
                    ForEach(TradeStatusFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                if filteredTrades.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredTrades) { trade in
                            NavigationLink(destination: TradeDetailView(trade: trade)) {
                                TradeRowCard(trade: trade)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .destructive) {
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
            }
            .navigationTitle("Giao Dịch")
            .searchable(text: $searchText, prompt: "Tìm theo mã (symbol), tag hoặc ghi chú...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddTradeSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            .sheet(isPresented: $showAddTradeSheet) {
                AddTradeSheet()
            }
        }
    }
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 30)
                
                Image(systemName: "chart.line.uptrend.xyaxis.circle")
                    .font(.system(size: 56))
                    .foregroundColor(AppColors.accent)
                
                VStack(spacing: 8) {
                    Text("Chưa có giao dịch nào")
                        .font(AppTypography.title)
                    Text("Bắt đầu ghi nhận lệnh giao dịch thủ công, hoặc nạp bộ dữ liệu mẫu thực tế để trải nghiệm toàn bộ hệ thống phân tích.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(spacing: 12) {
                    AppButton("Ghi Nhận Giao Dịch Mới", icon: "plus.circle", style: .primary) {
                        showAddTradeSheet = true
                    }
                    
                    AppButton("Nạp Dữ Liệu Mẫu Thực Tế", icon: "arrow.triangle.2.circlepath", style: .secondary) {
                        dataStore.seedDemoTradingData()
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
                
                Spacer()
                
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
    }
}
