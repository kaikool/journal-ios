import SwiftUI
import Charts

public struct EquityPointItem: Identifiable, Sendable {
    public var id: String { dateKey }
    public let date: Date
    public let dateKey: String
    public let netPnl: Decimal
    public let cumulativePnl: Decimal
    public let drawdown: Decimal
    
    public init(date: Date, dateKey: String, netPnl: Decimal, cumulativePnl: Decimal, drawdown: Decimal) {
        self.date = date
        self.dateKey = dateKey
        self.netPnl = netPnl
        self.cumulativePnl = cumulativePnl
        self.drawdown = drawdown
    }
}

public struct EquityCurveChart: View {
    public let points: [EquityPointItem]
    public let currency: String
    public let showArea: Bool
    
    @State private var selectedDateKey: String?
    
    public init(points: [EquityPointItem], currency: String = "USD", showArea: Bool = true) {
        self.points = points
        self.currency = currency
        self.showArea = showArea
    }
    
    private var selectedPoint: EquityPointItem? {
        guard let key = selectedDateKey else { return nil }
        return points.first { $0.dateKey == key }
    }
    
    private var isNetPositive: Bool {
        (points.last?.cumulativePnl ?? 0) >= 0
    }
    
    private var chartColor: Color {
        isNetPositive ? AppColors.profit : AppColors.loss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Selected tooltip header
            if let selected = selectedPoint {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.dateKey)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatCurrency(selected.cumulativePnl, currency: currency))
                            .font(AppTypography.subheadlineBold)
                            .foregroundColor(selected.cumulativePnl >= 0 ? AppColors.profit : AppColors.loss)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Day P&L")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(selected.netPnl, currency: currency))
                            .font(AppTypography.captionBold)
                            .foregroundColor(Formatters.pnlColor(selected.netPnl))
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
            
            if points.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Equity Data",
                    message: "Import trades or execute orders to see your cumulative equity curve."
                )
                .frame(height: 220)
            } else {
                Chart {
                    // Zero baseline
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border)
                    
                    ForEach(points) { point in
                        if showArea {
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Equity", (point.cumulativePnl as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        chartColor.opacity(0.3),
                                        chartColor.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Equity", (point.cumulativePnl as NSDecimalNumber).doubleValue)
                        )
                        .foregroundStyle(chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                        
                        // Selected rule & dot
                        if let selected = selectedPoint, selected.dateKey == point.dateKey {
                            RuleMark(x: .value("Selected Date", point.date))
                                .foregroundStyle(AppColors.accent.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Equity", (point.cumulativePnl as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(AppColors.accent)
                            .symbolSize(40)
                        }
                    }
                }
                .chartXSelection(value: $selectedDateKey)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                        AxisTick().foregroundStyle(AppColors.border)
                        AxisValueLabel(format: .dateTime.month().day())
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
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
                .frame(height: 220)
            }
        }
    }
}
