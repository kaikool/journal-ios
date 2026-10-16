import SwiftUI

public struct TradesListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    private var trades: [Trade] {
        dataStore.filteredTrades
    }
    
    public var body: some View {
        NavigationStack {
            List {
                ForEach(trades) { trade in
                    NavigationLink(destination: TradeDetailView(trade: trade)) {
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
                                    
                                    Text("Vào: \(Formatters.price(trade.avgEntry)) • Khối lượng: \(trade.quantity)")
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(Formatters.pnl(trade.netPnl, currencyCode: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled))
                                        .font(AppTypography.financialNumber(size: 16, weight: .bold))
                                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    
                                    Text(Formatters.dateOnly(trade.openedAt, timeZone: env.currentTimeZone))
                                        .font(AppTypography.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Giao Dịch")
        }
    }
}
