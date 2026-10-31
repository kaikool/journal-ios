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
                
                // 2x3 Grid of Metrics
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    AppMetricTile(
                        "Gross P&L",
                        value: Formatters.formatPnL(trade.grossPnl, currency: reportingCurrency),
                        color: Formatters.pnlColor(trade.grossPnl),
                        alignment: .leading
                    )
                    
                    AppMetricTile(
                        "Fees & Commissions",
                        value: Formatters.formatCurrency(trade.fees, currency: reportingCurrency),
                        color: trade.fees > 0 ? AppColors.warning : AppColors.primaryText,
                        alignment: .leading
                    )
                    
                    AppMetricTile(
                        "Net Realized P&L",
                        value: Formatters.formatPnL(trade.netPnl, currency: reportingCurrency),
                        color: Formatters.pnlColor(trade.netPnl),
                        alignment: .leading
                    )
                    
                    if trade.swapAmount != 0 {
                        AppMetricTile(
                            "Overnight Swap",
                            value: Formatters.formatPnL(trade.swapAmount, currency: reportingCurrency),
                            color: trade.swapAmount < 0 ? AppColors.warning : AppColors.profit,
                            alignment: .leading
                        )
                    } else if let ticket = ticketDisplay {
                        AppMetricTile(
                            "Order Ticket",
                            value: "#\(ticket)",
                            alignment: .leading
                        )
                    } else {
                        AppMetricTile(
                            "Duration",
                            value: durationString ?? "–",
                            alignment: .leading
                        )
                    }
                    
                    AppMetricTile(
                        "Avg Entry Price",
                        value: Formatters.price(trade.avgEntry, symbol: trade.symbol),
                        subtitle: Formatters.formatDateTime(trade.openedAt, timeZone: timeZone),
                        alignment: .leading
                    )
                    
                    AppMetricTile(
                        "Avg Exit Price",
                        value: trade.avgExit.map { Formatters.price($0, symbol: trade.symbol) } ?? "Open",
                        subtitle: trade.closedAt.map { Formatters.formatDateTime($0, timeZone: timeZone) },
                        alignment: .leading
                    )
                }
            }
        }
    }
}
