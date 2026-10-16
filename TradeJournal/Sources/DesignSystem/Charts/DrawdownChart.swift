import SwiftUI
import Charts

public struct DrawdownChart: View {
    public let points: [EquityPointItem]
    
    @State private var selectedDateKey: String?
    
    public init(points: [EquityPointItem]) {
        self.points = points
    }
    
    private var selectedPoint: EquityPointItem? {
        guard let key = selectedDateKey else { return nil }
        return points.first { $0.dateKey == key }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected = selectedPoint {
                HStack {
                    Text(selected.dateKey)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text("Drawdown: \(Formatters.formatPercent(selected.drawdown))")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.loss)
                }
                .padding(.horizontal, 4)
            }
            
            if points.isEmpty {
                EmptyStateView(
                    icon: "chart.line.downtrend.xyaxis",
                    title: "No Drawdown Data",
                    message: "Drawdown curve will render when trade equity points are calculated."
                )
                .frame(height: 180)
            } else {
                Chart {
                    RuleMark(y: .value("Peak", 0))
                        .foregroundStyle(AppColors.border)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    
                    ForEach(points) { point in
                        let ddVal = -(point.drawdown as NSDecimalNumber).doubleValue * 100.0
                        
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Drawdown", ddVal)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    AppColors.loss.opacity(0.0),
                                    AppColors.loss.opacity(0.3)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Drawdown", ddVal)
                        )
                        .foregroundStyle(AppColors.loss)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        
                        if let selected = selectedPoint, selected.dateKey == point.dateKey {
                            RuleMark(x: .value("Selected Date", point.date))
                                .foregroundStyle(AppColors.accent.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Drawdown", ddVal)
                            )
                            .foregroundStyle(AppColors.loss)
                            .symbolSize(35)
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
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                        AxisTick().foregroundStyle(AppColors.border)
                        AxisValueLabel {
                            if let doubleVal = value.as(Double.self) {
                                Text(String(format: "%.1f%%", doubleVal))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}
