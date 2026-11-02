import SwiftUI

// MARK: - Dedicated Pre-Trade Setup Specification Card
// Displays the authoritative execution parameters parsed from AI in an immediate 3-second glanceable card
public struct PreTradeSetupCard: View {
    public let plan: AdvisorCommitmentRecord
    public let timeZone: String
    
    public init(plan: AdvisorCommitmentRecord, timeZone: String = "UTC") {
        self.plan = plan
        self.timeZone = timeZone
    }
    
    private var badgeVariant: AppBadge.Variant {
        let b = plan.bias.uppercased()
        if b.contains("BUY") || b.contains("LONG") {
            return .profit
        } else if b.contains("SELL") || b.contains("SHORT") {
            return .loss
        }
        return .neutral
    }
    
    private var formattedDateTime: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.timeZone = TimeZone(identifier: timeZone) ?? .current
        return df.string(from: plan.timestamp)
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("PRE-TRADE SETUP SPECIFICATION")
                        .font(AppTypography.cardHeaderUppercase)
                        .tracking(0.5)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    AppBadge(plan.bias.uppercased(), variant: badgeVariant)
                }
                
                Divider()
                    .background(AppColors.border.opacity(0.35))
                
                // Key-Value Specification Rows
                VStack(spacing: 5) {
                    paramRow(label: "Direction:", value: plan.bias.uppercased())
                    
                    if let bal = plan.balance, !bal.isEmpty {
                        paramRow(label: "Balance:", value: bal)
                    }
                    
                    if let entry = plan.plannedEntry, !entry.isEmpty {
                        paramRow(label: "Entry:", value: entry)
                    }
                    
                    if let sl = plan.invalidationSL, !sl.isEmpty {
                        paramRow(label: "Stop loss:", value: sl)
                    }
                    
                    if let tp1 = plan.takeProfit1 ?? plan.targetTP, !tp1.isEmpty {
                        paramRow(label: "Take profit 1:", value: tp1)
                    }
                    
                    if let tp2 = plan.takeProfit2, !tp2.isEmpty, !tp2.lowercased().contains("khong"), !tp2.lowercased().contains("none") {
                        paramRow(label: "Take profit 2:", value: tp2)
                    }
                    
                    if let rr = plan.riskRewardRatio, !rr.isEmpty {
                        paramRow(label: "R:R Ratio:", value: rr)
                    }
                    
                    if let vol = plan.volume, !vol.isEmpty {
                        paramRow(label: "Volume:", value: vol)
                    }
                    
                    if let trigger = plan.triggerCondition, !trigger.isEmpty {
                        paramRow(label: "Trigger:", value: trigger)
                    }
                    
                    paramRow(label: "Date time:", value: formattedDateTime)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private func paramRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(AppTypography.statLabel)
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 90, alignment: .leading)
            
            Text(value)
                .font(AppTypography.statValueMedium)
                .foregroundColor(AppColors.primaryText)
                .lineLimit(2)
            
            Spacer()
        }
    }
}
