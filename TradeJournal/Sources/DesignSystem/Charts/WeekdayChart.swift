import SwiftUI
import Charts

/// Apple HIG Weekday Breakdown Chart.
/// Aggregates trade performance across days of the week with interactive bar selection and haptics.
public struct WeekdayChart: View {
    public let weekdays: [BucketStats]
    public let currency: String
    
    @State private var selectedDay: String? = nil
    @State private var lastHapticDay: String? = nil
    @State private var animProgress: Double = 0.0
    
    public init(weekdays: [BucketStats], currency: String = "USD") {
        self.weekdays = weekdays
        self.currency = currency
    }
    
    private var activeBucket: BucketStats? {
        guard let day = selectedDay else { return nil }
        return weekdays.first { $0.key == day }
    }
    
    private var totalNetPnl: Decimal {
        weekdays.reduce(Decimal.zero) { $0 + $1.netPnl }
    }
    
    private var yDomainMin: Double {
        let vals = weekdays.map { ($0.netPnl as NSDecimalNumber).doubleValue }
        let minVal = vals.min() ?? 0
        return minVal < 0 ? minVal * 1.15 : 0
    }
    
    private var yDomainMax: Double {
        let vals = weekdays.map { ($0.netPnl as NSDecimalNumber).doubleValue }
        let maxVal = vals.max() ?? 0
        return maxVal > 0 ? maxVal * 1.15 : 100
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header with live active readout
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeBucket.map { $0.key.uppercased() } ?? "PERFORMANCE BY WEEKDAY")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                            .lineLimit(1)
                        
                        Text(activeBucket.map { "\($0.trades) trades · WR \($0.winRate.map(Formatters.formatPercent) ?? "–")" } ?? "Net P&L grouped by trading day")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(height: 36, alignment: .leading)
                    
                    Spacer()
                    
                    let displayPnl = activeBucket?.netPnl ?? totalNetPnl
                    Text(Formatters.formatPnL(displayPnl, currency: currency))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(displayPnl >= 0 ? AppColors.profit : AppColors.loss)
                        .frame(height: 36, alignment: .trailing)
                }
                .frame(height: 38)
                
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
                            let rawVal = (bucket.netPnl as NSDecimalNumber).doubleValue
                            let val = rawVal * animProgress
                            
                            BarMark(
                                x: .value("Day", bucket.key),
                                y: .value("Net P&L", val)
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
                    .chartYScale(domain: yDomainMin...yDomainMax)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.border.opacity(0.3))
                            AxisValueLabel {
                                if let doubleVal = value.as(Double.self) {
                                    Text(Formatters.compactAxisValue(doubleVal, currency: currency))
                                        .font(.system(size: 9.5, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.secondaryText)
                                        .frame(width: 36, alignment: .trailing)
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
                    .animation(.spring(response: 0.85, dampingFraction: 0.82), value: animProgress)
                    .frame(height: 160)
                    .onAppear {
                        guard animProgress == 0.0 else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                                animProgress = 1.0
                            }
                        }
                    }
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
                                    .font(.system(size: 12, weight: .bold))
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
