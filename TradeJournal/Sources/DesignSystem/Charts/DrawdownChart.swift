import SwiftUI
import Charts

/// Apple HIG Relative Drawdown Chart ported from `components/charts/relative-drawdown-bars.tsx`.
/// Visualizes peak-to-trough decline over time with interactive touch scrubbing and haptics.
public struct DrawdownChart: View {
    public let points: [EquityPointItem]
    public let height: CGFloat
    
    @State private var selectedDate: Date? = nil
    @State private var lastHapticPointId: String? = nil
    
    public init(points: [EquityPointItem], height: CGFloat = 88) {
        self.points = points
        self.height = height
    }
    
    private var activePoint: EquityPointItem? {
        guard let target = selectedDate else { return nil }
        return points.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        })
    }
    
    private var maxDrawdownPct: Double {
        let maxVal = points.map { ($0.drawdown as NSDecimalNumber).doubleValue }.max() ?? 0
        return maxVal * 100.0
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Relative Drawdown and Max / Active Value
            HStack {
                Text(activePoint != nil ? formatDate(activePoint!.date) : "Relative Drawdown")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.6)
                
                Spacer()
                
                if let active = activePoint {
                    let activeVal = (active.drawdown as NSDecimalNumber).doubleValue * 100.0
                    Text(String(format: "-%.1f%%", activeVal))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColors.loss)
                } else {
                    Text(String(format: "Max -%.1f%%", maxDrawdownPct))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColors.loss)
                }
            }
            .padding(.horizontal, 2)
            
            if points.isEmpty {
                Text("No drawdown data available")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: height)
            } else {
                Chart {
                    // Peak Zero Rule
                    RuleMark(y: .value("Peak", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(AppColors.border.opacity(0.8))
                    
                    ForEach(points) { point in
                        let ddVal = -(point.drawdown as NSDecimalNumber).doubleValue * 100.0
                        
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Drawdown", ddVal)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    AppColors.loss.opacity(0.85),
                                    AppColors.loss.opacity(0.4)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(2)
                    }
                    
                    // Touch Cursor
                    if let active = activePoint, selectedDate != nil {
                        RuleMark(x: .value("Cursor", active.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let doubleVal = value.as(Double.self) {
                                Text(String(format: "%.0f%%", doubleVal))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }
                }
                .frame(height: height)
                .onChange(of: selectedDate) { newDate in
                    if let target = newDate,
                       let match = points.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }),
                       match.id != lastHapticPointId {
                        lastHapticPointId = match.id
                        triggerHapticFeedback()
                    } else if newDate == nil {
                        lastHapticPointId = nil
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func triggerHapticFeedback() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}
