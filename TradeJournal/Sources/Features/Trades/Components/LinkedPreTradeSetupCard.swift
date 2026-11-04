import SwiftUI

/// Component displaying linked pre-trade parameters and risk commitments.
public struct LinkedPreTradeSetupCard: View {
    public let plan: AdvisorCommitmentRecord
    public let trade: Trade
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init(plan: AdvisorCommitmentRecord, trade: Trade) {
        self.plan = plan
        self.trade = trade
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(AppTypography.cardHeaderUppercase)
                        .foregroundColor(AppColors.secondaryText)
                    Text("LINKED PRE-TRADE SETUP")
                        .font(AppTypography.cardHeaderUppercase)
                        .tracking(0.5)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                AppBadge(plan.bias.uppercased(), style: .neutral)
            }
            
            Divider()
                .background(AppColors.border.opacity(0.35))
            
            // Parsed Setup Parameters (Clean monochrome key-value rows)
            VStack(spacing: 5) {
                preTradeParamRow(label: "Direction:", value: plan.bias.uppercased())
                
                if let bal = resolvedBalance(plan: plan) {
                    preTradeParamRow(label: "Balance:", value: bal)
                }
                
                if let entry = plan.plannedEntry, !entry.isEmpty {
                    preTradeParamRow(label: "Entry:", value: entry)
                }
                
                if let sl = plan.invalidationSL, !sl.isEmpty {
                    preTradeParamRow(label: "Stop loss:", value: sl)
                }
                
                if let tp1 = plan.takeProfit1 ?? plan.targetTP, !tp1.isEmpty {
                    preTradeParamRow(label: "Take profit 1:", value: tp1)
                }
                
                if let tp2 = plan.takeProfit2, !tp2.isEmpty {
                    preTradeParamRow(label: "Take profit 2:", value: tp2)
                }
                
                if let rr = plan.riskRewardRatio, !rr.isEmpty {
                    preTradeParamRow(label: "R:R Ratio:", value: rr)
                }
                
                if let vol = resolvedVolume(plan: plan) {
                    preTradeParamRow(label: "Volume:", value: vol)
                }
                
                let tz = TimeZone(identifier: dataStore.generalSettings.displayTimeZone) ?? .current
                preTradeParamRow(label: "Date time:", value: Formatters.isoDateTime(plan.timestamp, timeZone: tz))
            }
        }
        .appCardStyle(cornerRadius: 10, padding: 10)
    }
    
    private func preTradeParamRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(AppTypography.statLabel)
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 85, alignment: .leading)
            
            Text(value)
                .font(AppTypography.statValueMedium)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(2)
            
            Spacer()
        }
    }
    
    private func resolvedBalance(plan: AdvisorCommitmentRecord) -> String? {
        if let b = plan.balance, !b.isEmpty { return b }
        let session = AIAccountContextProvider.captureContext(dataStore: dataStore)
        if let b = session.balance {
            return Formatters.formatCurrency(b, currency: session.accountCurrency)
        }
        if let acc = dataStore.accounts.first(where: { $0.id == trade.accountId }) {
            return Formatters.formatCurrency(acc.initialBalance, currency: acc.currency)
        }
        return nil
    }
    
    private func resolvedVolume(plan: AdvisorCommitmentRecord) -> String? {
        if let v = plan.volume, !v.isEmpty { return v }
        if trade.quantity > 0 {
            return "\(Formatters.formatDecimal(trade.quantity, maxDecimals: 2)) lots"
        }
        return nil
    }
}
