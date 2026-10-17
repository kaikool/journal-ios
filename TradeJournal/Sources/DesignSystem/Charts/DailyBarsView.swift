import SwiftUI
import Charts

public struct DailyBarDatum: Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let netPnl: Decimal
    
    public init(date: String, netPnl: Decimal) {
        self.date = date
        self.netPnl = netPnl
    }
}

/// Apple HIG Daily Net P&L Chart ported from `components/charts/daily-bars.tsx`.
/// Features:
/// - Bars growing upward (profit) or downward (loss) from zero baseline
/// - Rounded caps at data ends with subtle gradient fills
/// - Interactive touch scrubbing with floating HUD readout and haptic feedback
public struct DailyBarsView: View {
    public let data: [DailyBarDatum]
    public let currency: String
    public let isPrivate: Bool
    public let height: CGFloat
    
    @State private var selectedDate: String? = nil
    @State private var lastHapticDate: String? = nil
    
    public init(
        data: [DailyBarDatum],
        currency: String = "USD",
        isPrivate: Bool = false,
        height: CGFloat = 180
    ) {
        self.data = data
        self.currency = currency
        self.isPrivate = isPrivate
        self.height = height
    }
    
    private var activeDatum: DailyBarDatum? {
        guard let d = selectedDate else { return nil }
        return data.first { $0.date == d }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Scrub Readout Header
            if let active = activeDatum {
                HStack {
                    Text(formatDate(active.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    Text(isPrivate ? "••••" : Formatters.formatPnL(active.netPnl, currency: currency))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
            
            if data.isEmpty {
                Text("No trading day data available.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: height)
            } else {
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.8))
                    
                    ForEach(data) { entry in
                        let val = isPrivate ? 0 : (entry.netPnl as NSDecimalNumber).doubleValue
                        
                        BarMark(
                            x: .value("Date", entry.date),
                            y: .value("Net P&L", val)
                        )
                        .foregroundStyle(
                            entry.netPnl >= 0 ?
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
                        .opacity(selectedDate == nil || selectedDate == entry.date ? 1.0 : 0.45)
                    }
                    
                    if let activeKey = selectedDate {
                        RuleMark(x: .value("Cursor", activeKey))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(isPrivate ? "••••" : Formatters.formatCurrency(Decimal(d), currency: currency))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let dateStr = value.as(String.self) {
                                Text(String(dateStr.suffix(5)))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }
                }
                .frame(height: height)
                .onChange(of: selectedDate) { newDate in
                    if let d = newDate, d != lastHapticDate {
                        lastHapticDate = d
                        triggerHapticFeedback()
                    } else if newDate == nil {
                        lastHapticDate = nil
                    }
                }
            }
        }
    }
    
    private func formatDate(_ dateStr: String) -> String {
        return dateStr
    }
    
    private func triggerHapticFeedback() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}
