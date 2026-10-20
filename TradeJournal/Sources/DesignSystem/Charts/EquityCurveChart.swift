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

/// Cumulative Net P&L Area Chart ported 1:1 from `components/charts/equity-area.tsx`.
/// Visualizes cumulative profit/loss anchored strictly to the zero baseline:
/// - Positive values (profits) fill upwards from 0 to curve in brand cyan-blue (#1197e2).
/// - Negative values (losses) fill downwards from 0 to curve in loss crimson-red (#d03b3b).
/// - Continuous zero reference line.
/// - Interactive touch scrubbing with HUD display and haptics.
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
        height: CGFloat = 200
    ) {
        self.points = points
        self.currency = currency
        self.showArea = showArea
        self.height = height
    }
    
    private var activePoint: EquityPointItem? {
        guard let target = selectedDate else { return nil }
        return points.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        })
    }
    
    private var lastPoint: EquityPointItem? {
        points.last
    }
    
    private var doubleVals: [Double] {
        points.map { ($0.cumulativePnl as NSDecimalNumber).doubleValue }
    }
    
    private var maxVal: Double {
        max(0.0, doubleVals.max() ?? 0.0)
    }
    
    private var minVal: Double {
        min(0.0, doubleVals.min() ?? 0.0)
    }
    
    private var profitAreaGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.profit.opacity(0.25),
                AppColors.profit.opacity(0.02)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var lossAreaGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppColors.loss.opacity(0.02),
                AppColors.loss.opacity(0.25)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Interactive HUD / Scrub Header
            headerBar
            
            if points.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Data",
                    message: "Execute or import trades to visualize your cumulative P&L curve."
                )
                .frame(height: height)
            } else {
                Chart {
                    // Reference Zero Baseline (Breakeven)
                    RuleMark(y: .value("Zero", 0.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.85))
                    
                    ForEach(points) { point in
                        let val = (point.cumulativePnl as NSDecimalNumber).doubleValue
                        
                        if showArea {
                            // Positive profit area: fills from 0 UP to max(0.0, val) in green
                            AreaMark(
                                x: .value("Date", point.date),
                                yStart: .value("Baseline", 0.0),
                                yEnd: .value("Profit", max(0.0, val))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(profitAreaGradient)
                            
                            // Negative loss area: fills from 0 DOWN to min(0.0, val) in red
                            AreaMark(
                                x: .value("Date", point.date),
                                yStart: .value("Baseline", 0.0),
                                yEnd: .value("Loss", min(0.0, val))
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(lossAreaGradient)
                        }
                        
                        // Cumulative P&L Curve Stroke
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Equity", val)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(AppColors.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Single-point dot fallback
                    if points.count == 1, let single = points.first {
                        let sVal = (single.cumulativePnl as NSDecimalNumber).doubleValue
                        PointMark(
                            x: .value("Date", single.date),
                            y: .value("Equity", sVal)
                        )
                        .foregroundStyle(sVal >= 0 ? AppColors.profit : AppColors.loss)
                        .symbolSize(42)
                    }
                    
                    // Interactive Touch Crosshair & Cursor Node
                    if let active = activePoint {
                        let activeVal = (active.cumulativePnl as NSDecimalNumber).doubleValue
                        let cursorColor = activeVal >= 0 ? AppColors.profit : AppColors.loss
                        
                        RuleMark(x: .value("Cursor", active.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.45))
                        
                        // Halo
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Equity", activeVal)
                        )
                        .foregroundStyle(cursorColor.opacity(0.25))
                        .symbolSize(120)
                        
                        // Glowing bead
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Equity", activeVal)
                        )
                        .foregroundStyle(cursorColor)
                        .symbolSize(36)
                        
                        // Core center
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Equity", activeVal)
                        )
                        .foregroundStyle(Color.white)
                        .symbolSize(10)
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
    
    @ViewBuilder
    private var headerBar: some View {
        if let active = activePoint {
            // Live Scrubbing HUD
            HStack(spacing: 8) {
                Text(formatDate(active.date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                Text(Formatters.formatCurrency(active.cumulativePnl, currency: currency))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(active.cumulativePnl >= 0 ? AppColors.profit : AppColors.loss)
                
                if active.netPnl != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: active.netPnl > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(Formatters.formatPnL(active.netPnl, currency: currency))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((active.netPnl > 0 ? AppColors.profit : AppColors.loss).opacity(0.14))
                    .foregroundColor(active.netPnl > 0 ? AppColors.profit : AppColors.loss)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        } else if let last = lastPoint {
            // Quiet, elegant latest value
            HStack {
                Text("Running Net:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                
                Text(Formatters.formatCurrency(last.cumulativePnl, currency: currency))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(last.cumulativePnl >= 0 ? AppColors.profit : AppColors.loss)
                
                Spacer()
                
                Text("Drag to inspect")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.secondaryText.opacity(0.65))
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
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
