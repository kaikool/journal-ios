import SwiftUI
import Charts

public struct WeekdayChart: View {
    public let weekdays: [BucketStats]
    public let currency: String
    
    public init(weekdays: [BucketStats], currency: String = "USD") {
        self.weekdays = weekdays
        self.currency = currency
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if weekdays.isEmpty {
                EmptyStateView(
                    icon: "calendar",
                    title: "No Weekday Data",
                    message: "Trades will be aggregated across days of the week."
                )
                .frame(height: 180)
            } else {
                Chart(weekdays) { bucket in
                    BarMark(
                        x: .value("Day", bucket.key),
                        y: .value("Net P&L", (bucket.netPnl as NSDecimalNumber).doubleValue)
                    )
                    .foregroundStyle(Formatters.pnlColor(bucket.netPnl))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                        AxisTick().foregroundStyle(AppColors.border)
                        AxisValueLabel {
                            if let doubleVal = value.as(Double.self) {
                                Text(Formatters.formatCurrency(Decimal(doubleVal), currency: currency))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(AppColors.primaryText)
                            .font(AppTypography.caption)
                    }
                }
                .frame(height: 180)
                
                // Detailed breakdown table
                VStack(spacing: 6) {
                    ForEach(weekdays) { bucket in
                        HStack {
                            Text(bucket.key)
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                                .frame(width: 60, alignment: .leading)
                            
                            Text("\(bucket.trades) trds")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            Spacer()
                            
                            if let wr = bucket.winRate {
                                Text("WR \(Formatters.formatPercent(wr))")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .padding(.trailing, 8)
                            }
                            
                            Text(Formatters.formatPnL(bucket.netPnl, currency: currency))
                                .font(AppTypography.captionBold)
                                .foregroundColor(Formatters.pnlColor(bucket.netPnl))
                        }
                        .padding(.vertical, 2)
                        Divider().background(AppColors.border.opacity(0.4))
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
