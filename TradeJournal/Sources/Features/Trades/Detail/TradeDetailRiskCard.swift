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
            VStack(alignment: .leading, spacing: 14) {
                // Header with Action Button
                HStack(alignment: .center) {
                    Text("RISK & RETURN (R:R)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button(action: onEditTargets) {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Edit Targets")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.brand.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                // 2x2 Grid of Risk Metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricTile(
                        label: "Stop Loss",
                        value: trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                        color: trade.stopLoss != nil ? AppColors.primaryText : AppColors.secondaryText
                    )
                    
                    metricTile(
                        label: "Profit Target",
                        value: trade.profitTarget.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                        color: trade.profitTarget != nil ? AppColors.primaryText : AppColors.secondaryText
                    )
                    
                    metricTile(
                        label: "Risk at Stake (1R)",
                        value: riskAmount.map { Formatters.formatCurrency($0, currency: reportingCurrency) } ?? "–",
                        color: riskAmount != nil ? AppColors.loss : AppColors.secondaryText
                    )
                    
                    metricTile(
                        label: "Realized Return",
                        value: realizedR.map { String(format: "%+.2f R", ($0 as NSDecimalNumber).doubleValue) } ??
                               (plannedR.map { String(format: "Planned %.2f R", ($0 as NSDecimalNumber).doubleValue) } ?? "–"),
                        color: (realizedR ?? 0) >= 0 ? AppColors.profit : AppColors.loss
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
    
    private func metricTile(
        label: String,
        value: String,
        color: Color = AppColors.primaryText
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
            
            Text(value)
                .font(AppTypography.bodyBold)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
