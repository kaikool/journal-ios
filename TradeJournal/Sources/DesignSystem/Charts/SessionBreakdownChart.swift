import SwiftUI
import Charts

/// Apple HIG Trading Session Breakdown Chart.
/// Aggregates trade performance across standard market sessions (Asia, London, New York) with interactive bar selection.
public struct SessionBreakdownChart: View {
    public let sessions: [BucketStats]
    public let currency: String
    
    @State private var selectedSession: String? = nil
    @State private var lastHapticSession: String? = nil
    
    public init(sessions: [BucketStats], currency: String = "USD") {
        self.sessions = sessions
        self.currency = currency
    }
    
    private var activeBucket: BucketStats? {
        guard let name = selectedSession else { return nil }
        return sessions.first { $0.key == name }
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header with live active readout
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeBucket != nil ? activeBucket!.key.uppercased() : "PERFORMANCE BY SESSION")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                        
                        Text(activeBucket != nil ? "\(activeBucket!.trades) trades · WR \(activeBucket!.winRate != nil ? Formatters.formatPercent(activeBucket!.winRate!) : "–")" : "Net P&L grouped by market session")
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
                
                if sessions.isEmpty {
                    EmptyStateView(
                        icon: "clock.badge.checkmark",
                        title: "No Session Data",
                        message: "Trades with execution times will be aggregated into standard trading sessions."
                    )
                    .frame(height: 160)
                } else {
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(AppColors.border.opacity(0.8))
                        
                        ForEach(sessions) { bucket in
                            BarMark(
                                x: .value("Session", bucket.key),
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
                            .opacity(selectedSession == nil || selectedSession == bucket.key ? 1.0 : 0.45)
                        }
                        
                        if let s = selectedSession {
                            RuleMark(x: .value("Selected", s))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(AppColors.primaryText.opacity(0.35))
                        }
                    }
                    .chartXSelection(value: $selectedSession)
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
                    .onChange(of: selectedSession) { newSession in
                        if let s = newSession, s != lastHapticSession {
                            lastHapticSession = s
                            triggerHapticFeedback()
                        } else if newSession == nil {
                            lastHapticSession = nil
                        }
                    }
                    
                    Divider().background(AppColors.border.opacity(0.5))
                    
                    // Detailed breakdown table
                    VStack(spacing: 6) {
                        ForEach(sessions) { bucket in
                            HStack {
                                Text(bucket.key)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.primaryText)
                                    .frame(width: 90, alignment: .leading)
                                
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
