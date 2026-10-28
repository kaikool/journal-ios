import SwiftUI

/// Wrapper view for Trade Replay allowing selection of any filtered trade in the account
public struct TradeReplayHubView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @State private var selectedTradeId: String = ""
    
    public init() {}
    
    private var trades: [Trade] {
        dataStore.filteredTrades
    }
    
    private var activeTrade: Trade? {
        if let found = trades.first(where: { $0.id == selectedTradeId }) {
            return found
        }
        return trades.first
    }
    
    private var tradeExecutions: [Execution] {
        guard let t = activeTrade else { return [] }
        return dataStore.executions.filter { t.executionIds.contains($0.id) }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if trades.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.secondaryText.opacity(0.6))
                    Text("No Trades to Replay")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Text("Import trades or sync your account to view candle replays.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            } else {
                // Select Trade Card
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.brand)
                            Text("Select Trade to Replay")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        AppDropdownField(
                            selection: Binding(
                                get: { activeTrade?.id ?? "" },
                                set: { selectedTradeId = $0 }
                            ),
                            options: trades.map { $0.id },
                            titleFor: { id in
                                if let t = trades.first(where: { $0.id == id }) {
                                    let sign = t.netPnl >= 0 ? "+" : ""
                                    return "\(t.symbol) - \(t.direction.rawValue.uppercased()) (\(sign)\(Formatters.currency(t.netPnl)))"
                                }
                                return id
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                if let trade = activeTrade {
                    TradeReplayView(trade: trade, executions: tradeExecutions)
                        .id(trade.id)
                }
            }
        }
        .background(AppColors.background)
    }
}
