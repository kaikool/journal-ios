import SwiftUI

/// Risk & Return (R:R) Metrics Card for Trade Detail View
public struct TradeDetailRiskCard: View {
    public let trade: Trade
    public let riskAmount: Decimal?
    public let realizedR: Decimal?
    public let plannedR: Decimal?
    public let reportingCurrency: String
    public var onEditTargets: () -> Void
    
    public init(
        trade: Trade,
        riskAmount: Decimal?,
        realizedR: Decimal?,
        plannedR: Decimal?,
        reportingCurrency: String,
        onEditTargets: @escaping () -> Void
    ) {
        self.trade = trade
        self.riskAmount = riskAmount
        self.realizedR = realizedR
        self.plannedR = plannedR
        self.reportingCurrency = reportingCurrency
        self.onEditTargets = onEditTargets
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                // Header with Action Button
                AppSectionHeader(
                    "Risk & return (R:R)",
                    actionTitle: "Edit Targets",
                    actionIcon: "shield.lefthalf.filled",
                    onAction: onEditTargets
                )
                
                // 2x2 Grid of Risk Metrics
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    AppMetricTile(
                        "Stop Loss",
                        value: trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                        color: trade.stopLoss != nil ? AppColors.primaryText : AppColors.secondaryText,
                        alignment: .leading
                    )
                    
                    AppMetricTile(
                        "Profit Target",
                        value: trade.profitTarget.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                        color: trade.profitTarget != nil ? AppColors.primaryText : AppColors.secondaryText,
                        alignment: .leading
                    )
                    
                    AppMetricTile(
                        "Risk at Stake (1R)",
                        value: riskAmount.map { Formatters.formatCurrency($0, currency: reportingCurrency) } ?? "–",
                        color: riskAmount != nil ? AppColors.loss : AppColors.secondaryText,
                        alignment: .leading
                    )
                    
                    AppMetricTile(
                        "Realized Return",
                        value: realizedR.map { Formatters.formatRMultiple(($0 as NSDecimalNumber).doubleValue) } ??
                               (plannedR.map { "Planned \(Formatters.formatRMultiple(($0 as NSDecimalNumber).doubleValue))" } ?? "–"),
                        color: (realizedR ?? 0) >= 0 ? AppColors.profit : AppColors.loss,
                        alignment: .leading
                    )
                }
                
                // Visual R:R comparison bar when targets exist
                if let pR = plannedR {
                    let plannedVal = max(0.1, (pR as NSDecimalNumber).doubleValue)
                    VStack(spacing: 4) {
                        HStack {
                            Text("Risk / Reward Ratio")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(String(format: "1 : %.2f R", plannedVal))
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                                .foregroundColor(AppColors.brand)
                        }
                        
                        GeometryReader { geo in
                            HStack(spacing: 3) {
                                Capsule()
                                    .fill(AppColors.loss.opacity(0.8))
                                    .frame(width: max(24, geo.size.width * CGFloat(1.0 / (1.0 + plannedVal))))
                                Capsule()
                                    .fill(AppColors.profit.opacity(0.8))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
