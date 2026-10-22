import SwiftUI
import Charts

/// Apple HIG Hourly Trade Performance Chart ported from `components/charts/time-heatmap.tsx`.
/// Two aligned panes:
/// Upper: Net P&L per opening hour with gradient diverging bars and touch scrubber.
/// Lower: Trade count volume with interactive synchronization.
public struct TimeHeatmapView: View {
    private let hours: [BucketStats]
    private let currency: String
    private let isPrivate: Bool
    
    @State private var selectedHourKey: String? = nil
    @State private var lastHapticHour: String? = nil
    
    public init(hours: [BucketStats], currency: String = "USD", isPrivate: Bool = false) {
        self.hours = hours
        self.currency = currency
        self.isPrivate = isPrivate
    }
    
    private var displayHours: [BucketStats] {
        let existingMap = Dictionary(uniqueKeysWithValues: hours.map { ($0.key, $0) })
        return (0..<24).map { h in
            let key = String(format: "%02d", h)
            if let stat = existingMap[key] {
                return stat
            }
            return BucketStats(key: key, trades: 0, netPnl: 0, winRate: nil, profitFactor: nil, volume: 0)
        }
    }
    
    private var activeBucket: BucketStats? {
        guard let key = selectedHourKey else { return nil }
        return displayHours.first { "\($0.key):00" == key }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Live Scrub Header
            if let active = activeBucket {
                HStack {
                    Text("\(active.key):00")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    Text("\(active.trades) trades")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("·")
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(isPrivate ? "••••" : Formatters.formatPnL(active.netPnl, currency: currency))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.cardBackground.opacity(0.8))
                .clipShape(Capsule())
                .transition(.opacity)
            }
            
            // Upper Pane: Net P&L Diverging Bars
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(isPrivate ? "Net P&L (hidden)" : "Net P&L (\(currency))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.8))
                    
                    ForEach(displayHours) { h in
                        let hourLabel = "\(h.key):00"
                        let pnlVal = isPrivate ? 0 : (h.netPnl as NSDecimalNumber).doubleValue
                        
                        BarMark(
                            x: .value("Hour", hourLabel),
                            y: .value("Net P&L", pnlVal)
                        )
                        .foregroundStyle(
                            h.netPnl >= 0 ?
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
                        .cornerRadius(3.5)
                        .opacity(selectedHourKey == nil || selectedHourKey == hourLabel ? 1.0 : 0.4)
                    }
                    
                    if let activeKey = selectedHourKey {
                        RuleMark(x: .value("Cursor", activeKey))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedHourKey)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel(anchor: .trailing) {
                            if let d = value.as(Double.self) {
                                Text(isPrivate ? "••••" : Formatters.compactCurrency(Decimal(d), currency: currency))
                                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 120)
            }
            
            // Lower Pane: Trade Volume (Line chart with points & area fill)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Trades")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                
                Chart {
                    ForEach(displayHours) { h in
                        let hourLabel = "\(h.key):00"
                        
                        LineMark(
                            x: .value("Hour", hourLabel),
                            y: .value("Trades", h.trades)
                        )
                        .foregroundStyle(AppColors.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                        
                        AreaMark(
                            x: .value("Hour", hourLabel),
                            y: .value("Trades", h.trades)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.brand.opacity(0.20), AppColors.brand.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                        
                        PointMark(
                            x: .value("Hour", hourLabel),
                            y: .value("Trades", h.trades)
                        )
                        .foregroundStyle(AppColors.brand)
                        .symbolSize(selectedHourKey == hourLabel ? 36 : (h.trades > 0 ? 16 : 8))
                    }
                    
                    if let activeKey = selectedHourKey {
                        RuleMark(x: .value("Cursor", activeKey))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedHourKey)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                        AxisValueLabel(anchor: .trailing) {
                            if let intVal = value.as(Int.self) {
                                Text("\(intVal)")
                                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: ["00:00", "04:00", "08:00", "12:00", "16:00", "20:00"]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border)
                        AxisValueLabel(collisionResolution: .disabled) {
                            if let label = value.as(String.self) {
                                let shortLabel: String = {
                                    switch label {
                                    case "00:00": return "0h"
                                    case "04:00": return "4h"
                                    case "08:00": return "8h"
                                    case "12:00": return "12h"
                                    case "16:00": return "16h"
                                    case "20:00": return "20h"
                                    default: return label.replacingOccurrences(of: ":00", with: "h")
                                    }
                                }()
                                Text(shortLabel)
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .frame(height: 75)
                .onChange(of: selectedHourKey) { newHour in
                    if let h = newHour, h != lastHapticHour {
                        lastHapticHour = h
                        triggerHapticFeedback()
                    } else if newHour == nil {
                        lastHapticHour = nil
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
