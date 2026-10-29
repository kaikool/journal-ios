import SwiftUI

/// Financial and Execution Metrics Card for Trade Detail View
public struct TradeDetailMetricsCard: View {
    public let trade: Trade
    public let durationString: String?
    public let ticketDisplay: String?
    public let reportingCurrency: String
    public let timeZone: TimeZone
    
    public init(
        trade: Trade,
        durationString: String?,
        ticketDisplay: String?,
        reportingCurrency: String,
        timeZone: TimeZone
    ) {
        self.trade = trade
        self.durationString = durationString
        self.ticketDisplay = ticketDisplay
        self.reportingCurrency = reportingCurrency
        self.timeZone = timeZone
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .center) {
                    Text("EXECUTION & FINANCIALS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(AppColors.secondaryBackground.opacity(0.5))
                        .clipShape(Circle())
                }
                
                // 2x3 Grid of Metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricTile(
                        label: "Gross P&L",
                        value: Formatters.formatPnL(trade.grossPnl, currency: reportingCurrency),
                        color: Formatters.pnlColor(trade.grossPnl)
                    )
                    
                    metricTile(
                        label: "Fees & Commissions",
                        value: Formatters.formatCurrency(trade.fees, currency: reportingCurrency),
                        color: trade.fees > 0 ? AppColors.warning : AppColors.primaryText
                    )
                    
                    metricTile(
                        label: "Net Realized P&L",
                        value: Formatters.formatPnL(trade.netPnl, currency: reportingCurrency),
                        color: Formatters.pnlColor(trade.netPnl)
                    )
                    
                    if trade.swapAmount != 0 {
                        metricTile(
                            label: "Overnight Swap",
                            value: Formatters.formatPnL(trade.swapAmount, currency: reportingCurrency),
                            color: trade.swapAmount < 0 ? AppColors.warning : AppColors.profit
                        )
                    } else if let ticket = ticketDisplay {
                        metricTile(
                            label: "Order Ticket",
                            value: "#\(ticket)"
                        )
                    } else {
                        metricTile(
                            label: "Duration",
                            value: durationString ?? "–"
                        )
                    }
                    
                    metricTile(
                        label: "Avg Entry Price",
                        value: Formatters.price(trade.avgEntry, symbol: trade.symbol),
                        subtext: Formatters.formatDateTime(trade.openedAt, timeZone: timeZone)
                    )
                    
                    metricTile(
                        label: "Avg Exit Price",
                        value: trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? "Open",
                        subtext: trade.closedAt != nil ? Formatters.formatDateTime(trade.closedAt!, timeZone: timeZone) : nil
                    )
                }
            }
        }
    }
    
    private func metricTile(
        label: String,
        value: String,
        color: Color = AppColors.primaryText,
        subtext: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            Text(value)
                .font(AppTypography.bodyBold)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            if let sub = subtext, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
