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
            VStack(alignment: .leading, spacing: 12) {
                // Header
                AppSectionHeader("Execution & financials", icon: "dollarsign.circle")
                
                // 2x3 Grid of Clean Text Metrics
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 12) {
                    textMetric(
                        title: "Gross P&L",
                        value: Formatters.formatPnL(trade.grossPnl, currency: reportingCurrency),
                        color: Formatters.pnlColor(trade.grossPnl)
                    )
                    
                    textMetric(
                        title: "Fees & Commissions",
                        value: Formatters.formatCurrency(trade.fees, currency: reportingCurrency),
                        color: trade.fees > 0 ? AppColors.warning : AppColors.primaryText
                    )
                    
                    textMetric(
                        title: "Net Realized P&L",
                        value: Formatters.formatPnL(trade.netPnl, currency: reportingCurrency),
                        color: Formatters.pnlColor(trade.netPnl)
                    )
                    
                    if trade.swapAmount != 0 {
                        textMetric(
                            title: "Overnight Swap",
                            value: Formatters.formatPnL(trade.swapAmount, currency: reportingCurrency),
                            color: trade.swapAmount < 0 ? AppColors.warning : AppColors.profit
                        )
                    } else if let ticket = ticketDisplay {
                        textMetric(
                            title: "Order Ticket",
                            value: "#\(ticket)"
                        )
                    } else {
                        textMetric(
                            title: "Duration",
                            value: durationString ?? "–"
                        )
                    }
                    
                    textMetric(
                        title: "Avg Entry Price",
                        value: Formatters.price(trade.avgEntry, symbol: trade.symbol),
                        subtitle: Formatters.formatDateTime(trade.openedAt, timeZone: timeZone)
                    )
                    
                    exitPriceMetric
                }
            }
        }
    }
    
    private var exitPriceMetric: some View {
        let title = "Avg Exit Price"
        if trade.status.isClosed {
            return textMetric(
                title: title,
                value: trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? "–",
                subtitle: trade.closedAt.map { Formatters.formatDateTime($0, timeZone: timeZone) }
            )
        } else if trade.isPartiallyClosed {
            return textMetric(
                title: title,
                value: trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? "Partial",
                subtitle: "\(Formatters.formatNumber(trade.closedQuantity)) lots closed"
            )
        } else {
            return textMetric(
                title: title,
                value: "Open",
                subtitle: "Active position"
            )
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
