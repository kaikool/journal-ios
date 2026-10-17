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

/// Apple HIG Stocks-tier Interactive Equity Curve Chart.
/// Features:
/// - Smooth Catmull-Rom spline interpolation (no jagged polygonal steps)
/// - Multi-stop ambient luminous gradient fill
/// - Interactive touch scrubbing with vertical tracking line and haloed cursor node
/// - Real-time live header updating with monospaced digits and haptic feedback
/// - Clean minimal zero-baseline and quiet typographic axes
public struct EquityCurveChart: View {
    public let points: [EquityPointItem]
    public let currency: String
    public let showArea: Bool
    public let height: CGFloat
    
    @State private var selectedDate: Date? = nil
    @State private var lastHapticPointId: String? = nil
    
    public init(
        points: [EquityPointItem],
        currency: String = "USD",
        showArea: Bool = true,
        height: CGFloat = 220
    ) {
        self.points = points
        self.currency = currency
        self.showArea = showArea
        self.height = height
    }
    
    private var activePoint: EquityPointItem? {
        guard let target = selectedDate else { return points.last }
        return points.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }) ?? points.last
    }
    
    private var isNetPositive: Bool {
        (activePoint?.cumulativePnl ?? points.last?.cumulativePnl ?? 0) >= 0
    }
    
    private var chartColor: Color {
        isNetPositive ? AppColors.profit : AppColors.loss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Apple HIG Live Header
            if let active = activePoint {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedDate != nil ? formatDate(active.date) : "Cumulative Equity")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Text(Formatters.formatCurrency(active.cumulativePnl, currency: currency))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(active.cumulativePnl >= 0 ? AppColors.profit : AppColors.loss)
                    }
                    
                    Spacer()
                    
                    // Day P&L Pill
                    HStack(spacing: 3) {
                        Image(systemName: active.netPnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(Formatters.formatPnL(active.netPnl, currency: currency))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                            .opacity(0.12)
                    )
                    .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 2)
            }
            
            if points.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Equity Data",
                    message: "Import trades or execute orders to see your cumulative equity curve."
                )
                .frame(height: height)
            } else {
                Chart {
                    // Crisp Zero Baseline
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.8))
                    
                    ForEach(points) { point in
                        let val = (point.cumulativePnl as NSDecimalNumber).doubleValue
                        
                        if showArea {
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Equity", val)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    stops: [
                                        .init(color: chartColor.opacity(0.32), location: 0.0),
                                        .init(color: chartColor.opacity(0.08), location: 0.6),
                                        .init(color: chartColor.opacity(0.0), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Equity", val)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(chartColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Interactive Touch Cursor & Glowing Node
                    if let active = activePoint, selectedDate != nil {
                        let activeVal = (active.cumulativePnl as NSDecimalNumber).doubleValue
                        
                        RuleMark(x: .value("Cursor", active.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.4))
                        
                        // Outer Halo
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Equity", activeVal)
                        )
                        .foregroundStyle(chartColor.opacity(0.25))
                        .symbolSize(140)
                        
                        // Inner Glowing Bead
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Equity", activeVal)
                        )
                        .foregroundStyle(chartColor)
                        .symbolSize(36)
                        
                        // Core White Point
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Equity", activeVal)
                        )
                        .foregroundStyle(Color.white)
                        .symbolSize(12)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let doubleVal = value.as(Double.self) {
                                Text(Formatters.formatCurrency(Decimal(doubleVal), currency: currency))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
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
