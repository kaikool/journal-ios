import SwiftUI
import Charts

/// Apple HIG Weekday Breakdown Chart.
/// Aggregates trade performance across days of the week with interactive bar selection and haptics.
public struct WeekdayChart: View {
    public let weekdays: [BucketStats]
    public let currency: String
    
    @State private var selectedDay: String? = nil
    @State private var lastHapticDay: String? = nil
    
    public init(weekdays: [BucketStats], currency: String = "USD") {
        self.weekdays = weekdays
        self.currency = currency
    }
    
    private var activeBucket: BucketStats? {
        guard let day = selectedDay else { return nil }
        return weekdays.first { $0.key == day }
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header with live active readout
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeBucket != nil ? activeBucket!.key : "Performance by Weekday")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(activeBucket != nil ? "\(activeBucket!.trades) trades · WR \(activeBucket!.winRate != nil ? Formatters.formatPercent(activeBucket!.winRate!) : "–")" : "Net P&L grouped by trading day")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if let active = activeBucket {
                        Text(Formatters.formatPnL(active.netPnl, currency: currency))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    }
                }
                
                if weekdays.isEmpty {
                    EmptyStateView(
                        icon: "calendar",
                        title: "No Weekday Data",
                        message: "Trades will be aggregated across days of the week."
                    )
                    .frame(height: 160)
                } else {
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(AppColors.border.opacity(0.8))
                        
                        ForEach(weekdays) { bucket in
                            BarMark(
                                x: .value("Day", bucket.key),
                                y: .value("Net P&L", (bucket.netPnl as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(
                                bucket.netPnl >= 0 ?
                                LinearGradient(
                                    colors: [AppColors.profit, AppColors.profit.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ) :
                                LinearGradient(
                                    colors: [AppColors.loss.opacity(0.75), AppColors.loss],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(4)
                            .opacity(selectedDay == nil || selectedDay == bucket.key ? 1.0 : 0.45)
                        }
                        
                        if let day = selectedDay {
                            RuleMark(x: .value("Selected", day))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(AppColors.primaryText.opacity(0.35))
                        }
                    }
                    .chartXSelection(value: $selectedDay)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.border.opacity(0.3))
                            AxisValueLabel {
                                if let doubleVal = value.as(Double.self) {
                                    Text(Formatters.formatCurrency(Decimal(doubleVal), currency: currency))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColors.primaryText)
                        }
                    }
                    .frame(height: 160)
                    .onChange(of: selectedDay) { newDay in
                        if let d = newDay, d != lastHapticDay {
                            lastHapticDay = d
                            triggerHapticFeedback()
                        } else if newDay == nil {
                            lastHapticDay = nil
                        }
                    }
                    
                    Divider().background(AppColors.border.opacity(0.5))
                    
                    // Detailed breakdown table
                    VStack(spacing: 6) {
                        ForEach(weekdays) { bucket in
                            HStack {
                                Text(bucket.key)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                                    .frame(width: 50, alignment: .leading)
                                
                                Text("\(bucket.trades) trades")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                Spacer()
                                
                                if let wr = bucket.winRate {
                                    Text("WR \(Formatters.formatPercent(wr))")
                                        .font(.system(size: 10, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.border.opacity(0.4))
                                        .clipShape(Capsule())
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                
                                Text(Formatters.formatPnL(bucket.netPnl, currency: currency))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(bucket.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    .frame(minWidth: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }
    
    private func triggerHapticFeedback() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}
