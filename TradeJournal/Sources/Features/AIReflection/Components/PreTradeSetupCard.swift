import SwiftUI

// MARK: - Dedicated Pre-Trade Setup Specification Card
// Displays the authoritative execution parameters parsed from AI in an immediate glanceable card
public struct PreTradeSetupCard: View {
    public let plan: AdvisorCommitmentRecord
    public let timeZone: String
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }()
    
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
        let df = Self.dateFormatter
        df.timeZone = TimeZone(identifier: timeZone) ?? .current
        return df.string(from: plan.timestamp)
    }
    
    private func isValidValue(_ val: String?) -> Bool {
        guard let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return false }
        let lower = v.lowercased()
        return lower != "<null>" && lower != "null" && lower != "none" && lower != "n/a" && lower != "nil" && lower != "không" && lower != "khong"
    }
    
    @ViewBuilder
    public var body: some View {
        if plan.hasActionableSetup {
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
                        
                        if let bal = plan.balance, isValidValue(bal) {
                            paramRow(label: "Balance:", value: bal)
                        }
                        
                        if let entry = plan.plannedEntry, isValidValue(entry) {
                            paramRow(label: "Entry:", value: entry)
                        }
                        
                        if let sl = plan.invalidationSL, isValidValue(sl) {
                            paramRow(label: "Stop loss:", value: sl)
                        }
                        
                        if let tp1 = plan.takeProfit1 ?? plan.targetTP, isValidValue(tp1) {
                            paramRow(label: "Take profit 1:", value: tp1)
                        }
                        
                        if let tp2 = plan.takeProfit2, isValidValue(tp2) {
                            paramRow(label: "Take profit 2:", value: tp2)
                        }
                        
                        if let rr = plan.riskRewardRatio, isValidValue(rr) {
                            paramRow(label: "R:R Ratio:", value: rr)
                        }
                        
                        if let vol = plan.volume, isValidValue(vol) {
                            paramRow(label: "Volume:", value: vol)
                        }
                        
                        if let trigger = plan.triggerCondition, isValidValue(trigger) {
                            paramRow(label: "Trigger:", value: trigger)
                        }
                        
                        paramRow(label: "Date time:", value: formattedDateTime)
                    }
                }
                .padding(.vertical, 2)
            }
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
