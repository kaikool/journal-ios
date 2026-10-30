import SwiftUI
import Charts

/// Apple HIG Relative Drawdown Chart ported from `components/charts/relative-drawdown-bars.tsx`.
/// Visualizes peak-to-trough decline over time with interactive touch scrubbing and haptics.
public struct DrawdownChart: View {
    public let points: [EquityPointItem]
    public let height: CGFloat
    
    @State private var selectedDate: Date? = nil
    @State private var lastHapticPointId: String? = nil
    @State private var animProgress: Double = 0.0
    
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
    
    private var barWidth: CGFloat {
        if points.count <= 2 { return 16 }
        if points.count <= 5 { return 12 }
        if points.count <= 15 { return 8 }
        if points.count <= 30 { return 5 }
        return 3
    }
    
    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else {
            return Date().addingTimeInterval(-86400 * 2)...Date().addingTimeInterval(86400 * 2)
        }
        let diff = max(0, last.timeIntervalSince(first))
        // Always provide at least 1.5 - 2 days margin on both sides so bars near edges don't overflow the chart area
        let margin = max(86400.0 * 2, diff * 0.15)
        return first.addingTimeInterval(-margin)...last.addingTimeInterval(margin)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Relative Drawdown and Max / Active Value
            HStack(alignment: .center) {
                Text(activePoint.map { formatDate($0.date) } ?? "Relative Drawdown")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .lineLimit(1)
                
                Spacer()
                
                if let active = activePoint {
                    let activeVal = (active.drawdown as NSDecimalNumber).doubleValue * 100.0
                    Text(String(format: "-%.1f%%", activeVal))
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.loss)
                        .lineLimit(1)
                } else {
                    Text(String(format: "Max -%.1f%%", maxDrawdownPct))
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.loss)
                        .lineLimit(1)
                }
            }
            .frame(height: 18)
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
                        let rawDdVal = -(point.drawdown as NSDecimalNumber).doubleValue * 100.0
                        let ddVal = rawDdVal * animProgress
                        
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Drawdown", ddVal),
                            width: .fixed(barWidth)
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
                .chartXScale(domain: xDomain)
                .chartXAxis(.hidden)
                .chartYScale(domain: -max(maxDrawdownPct * 1.15, 5.0)...0)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let doubleVal = value.as(Double.self) {
                                Text(String(format: "%.0f%%", doubleVal))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(AppColors.secondaryText)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .animation(.spring(response: 0.85, dampingFraction: 0.82), value: animProgress)
                .frame(height: height)
                .onAppear {
                    guard animProgress == 0.0 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                            animProgress = 1.0
                        }
                    }
                }
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
