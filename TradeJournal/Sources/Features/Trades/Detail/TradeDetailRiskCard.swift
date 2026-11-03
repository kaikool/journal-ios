import SwiftUI

/// Risk & Return (R:R) Metrics Card for Trade Detail View
public struct TradeDetailRiskCard: View {
    public let trade: Trade
    public let riskAmount: Decimal?
    public let lockedProfit: Decimal?
    public let targetAmount: Decimal?
    public let realizedR: Decimal?
    public let plannedR: Decimal?
    public let reportingCurrency: String
    public var onEditTargets: () -> Void
    
    public init(
        trade: Trade,
        riskAmount: Decimal?,
        lockedProfit: Decimal? = nil,
        targetAmount: Decimal? = nil,
        realizedR: Decimal?,
        plannedR: Decimal?,
        reportingCurrency: String,
        onEditTargets: @escaping () -> Void
    ) {
        self.trade = trade
        self.riskAmount = riskAmount
        self.lockedProfit = lockedProfit
        self.targetAmount = targetAmount
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
                    onAction: onEditTargets
                )
                
                // 2x2 Grid of Clean Text Risk Metrics
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 12) {
                    // Tile 1: Stop Loss
                    stopLossTile
                    
                    // Tile 2: Profit Target
                    profitTargetTile
                    
                    // Tile 3: Risk at Stake / Capital Protection
                    riskProtectionTile
                    
                    // Tile 4: Return Performance
                    returnPerformanceTile
                }
                
                // Visual R:R comparison bar
                visualRiskRewardBar
            }
        }
    }
    
    // MARK: - Subviews
    
    private var stopLossTile: some View {
        let title = "Stop Loss"
        if trade.isStopLossInProfit {
            let subtitle = trade.lockedProfitPoints.map { "Trailing (+\(Formatters.formatDecimal($0, maxDecimals: 2)) pts)" } ?? "Trailing Stop"
            return textMetric(
                title: title,
                value: trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                subtitle: subtitle,
                color: AppColors.profit
            )
        } else if trade.isStopLossAtBreakeven {
            return textMetric(
                title: title,
                value: trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                subtitle: "Breakeven Stop",
                color: AppColors.brand
            )
        } else {
            return textMetric(
                title: title,
                value: trade.stopLoss.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
                color: trade.stopLoss != nil ? AppColors.primaryText : AppColors.secondaryText
            )
        }
    }
    
    private var profitTargetTile: some View {
        let subtitle: String? = targetAmount.map { "Potential: +\(Formatters.formatCurrency($0, currency: reportingCurrency))" }
        return textMetric(
            title: "Profit Target",
            value: trade.profitTarget.map { Formatters.price($0, symbol: trade.symbol) } ?? "Not set",
            subtitle: subtitle,
            color: trade.profitTarget != nil ? AppColors.profit : AppColors.secondaryText
        )
    }
    
    private var riskProtectionTile: some View {
        if trade.isStopLossInProfit {
            let totalLocked = (lockedProfit ?? 0) + (trade.isPartiallyClosed ? trade.netPnl : 0)
            let sub = "Locked +\(Formatters.formatCurrency(totalLocked, currency: reportingCurrency))"
            return textMetric(
                title: "Capital at Risk",
                value: "$0.00 (Risk-Free)",
                subtitle: sub,
                color: AppColors.profit
            )
        } else if trade.isStopLossAtBreakeven {
            let sub = trade.isPartiallyClosed
                ? "Banked: +\(Formatters.formatCurrency(trade.netPnl, currency: reportingCurrency))"
                : "Protected at Breakeven"
            return textMetric(
                title: "Capital at Risk",
                value: "$0.00 (Risk-Free)",
                subtitle: sub,
                color: AppColors.profit
            )
        } else if trade.isPartiallyClosed && trade.status == .open {
            if let risk = riskAmount {
                if trade.netPnl >= risk {
                    let netOutcome = trade.netPnl - risk
                    return textMetric(
                        title: "Capital at Risk",
                        value: "$0.00 (Risk-Free)",
                        subtitle: "Net on SL: +\(Formatters.formatCurrency(netOutcome, currency: reportingCurrency))",
                        color: AppColors.profit
                    )
                } else {
                    let netRisk = risk - trade.netPnl
                    return textMetric(
                        title: "Net Risk at Stake",
                        value: "-\(Formatters.formatCurrency(netRisk, currency: reportingCurrency))",
                        subtitle: "Active: -\(Formatters.formatCurrency(risk, currency: reportingCurrency)) | Banked: +\(Formatters.formatCurrency(trade.netPnl, currency: reportingCurrency))",
                        color: AppColors.loss
                    )
                }
            } else {
                return textMetric(
                    title: "Capital at Risk",
                    value: "–",
                    color: AppColors.secondaryText
                )
            }
        } else {
            return textMetric(
                title: "Risk at Stake (1R)",
                value: riskAmount.map { "-\(Formatters.formatCurrency($0, currency: reportingCurrency))" } ?? "–",
                color: riskAmount != nil ? AppColors.loss : AppColors.secondaryText
            )
        }
    }
    
    private var returnPerformanceTile: some View {
        if trade.isStopLossInProfit {
            let isClosed = trade.status.isClosed
            let val = isClosed
                ? (realizedR.map { Formatters.formatRMultiple(($0 as NSDecimalNumber).doubleValue) } ?? Formatters.formatPnL(trade.netPnl, currency: reportingCurrency))
                : (targetAmount.map { "+\(Formatters.formatCurrency($0 + (trade.isPartiallyClosed ? trade.netPnl : 0), currency: reportingCurrency))" } ?? "Risk-Free Runner")
            let sub: String? = isClosed ? nil : (lockedProfit.map { "Guaranteed +\(Formatters.formatCurrency($0 + (trade.isPartiallyClosed ? trade.netPnl : 0), currency: reportingCurrency))" })
            return textMetric(
                title: isClosed ? "Realized Return" : "Runner Status",
                value: val,
                subtitle: sub,
                color: AppColors.profit
            )
        } else if trade.isStopLossAtBreakeven {
            let isClosed = trade.status.isClosed
            let totalReturn = (targetAmount ?? 0) + (trade.isPartiallyClosed ? trade.netPnl : 0)
            let val = isClosed
                ? Formatters.formatPnL(trade.netPnl, currency: reportingCurrency)
                : (targetAmount != nil ? "+\(Formatters.formatCurrency(totalReturn, currency: reportingCurrency))" : "Risk-Free BE")
            return textMetric(
                title: isClosed ? "Realized Return" : "Runner Status",
                value: val,
                color: isClosed ? Formatters.pnlColor(trade.netPnl) : AppColors.profit
            )
        } else if trade.isPartiallyClosed && trade.status == .open {
            if let tAmt = targetAmount {
                let totalTarget = trade.netPnl + tAmt
                let sub = "Active: +\(Formatters.formatCurrency(tAmt, currency: reportingCurrency)) | Banked: +\(Formatters.formatCurrency(trade.netPnl, currency: reportingCurrency))"
                return textMetric(
                    title: "Total Potential",
                    value: "+\(Formatters.formatCurrency(totalTarget, currency: reportingCurrency))",
                    subtitle: sub,
                    color: AppColors.profit
                )
            } else {
                return textMetric(
                    title: "Banked Return",
                    value: Formatters.formatPnL(trade.netPnl, currency: reportingCurrency),
                    color: Formatters.pnlColor(trade.netPnl)
                )
            }
        } else {
            let isClosed = trade.status.isClosed
            let val = realizedR.map { Formatters.formatRMultiple(($0 as NSDecimalNumber).doubleValue) } ??
                   (plannedR.map { "Planned \(Formatters.formatRMultiple(($0 as NSDecimalNumber).doubleValue))" } ?? "–")
            let sub: String? = (realizedR != nil && plannedR != nil) ? plannedR.map { "Planned \(Formatters.formatRMultiple(($0 as NSDecimalNumber).doubleValue))" } : nil
            return textMetric(
                title: isClosed ? "Realized Return" : "Planned Return",
                value: val,
                subtitle: sub,
                color: (realizedR ?? plannedR ?? 0) >= 0 ? AppColors.profit : AppColors.loss
            )
        }
    }
    
    @ViewBuilder
    private var visualRiskRewardBar: some View {
        if trade.isStopLossInProfit || trade.isStopLossAtBreakeven {
            VStack(spacing: 4) {
                HStack {
                    Text("Downside Risk: $0.00 (Risk-Free)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text(trade.isStopLossInProfit ? "Locked Profit Runner" : "Breakeven Protected")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.profit)
                }
                
                Capsule()
                    .fill(AppColors.profit.opacity(0.85))
                    .frame(height: 4)
            }
            .padding(.top, 4)
        } else if trade.isPartiallyClosed && trade.status == .open && (trade.netPnl >= (riskAmount ?? 0)) {
            VStack(spacing: 4) {
                HStack {
                    Text("Downside Risk: $0.00 (Banked profit covers SL)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text("Risk-Free (Partial TP)")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.profit)
                }
                
                Capsule()
                    .fill(AppColors.profit.opacity(0.85))
                    .frame(height: 4)
            }
            .padding(.top, 4)
        } else if let pR = plannedR {
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
    
    private func textMetric(
        title: String,
        value: String,
        subtitle: String? = nil,
        color: Color = AppColors.primaryText
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
            Text(value)
                .font(AppTypography.statValue)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let s = subtitle {
                Text(s)
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
