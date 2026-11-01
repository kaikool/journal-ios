import SwiftUI
import Charts

/// Apple HIG Trading Session Breakdown Chart.
/// Aggregates trade performance across standard market sessions (Asia, London, New York) with interactive bar selection.
public struct SessionBreakdownChart: View {
    public let sessions: [BucketStats]
    public let currency: String
    
    @State private var selectedSession: String? = nil
    @State private var lastHapticSession: String? = nil
    @State private var animProgress: Double = 0.0
    
    public init(sessions: [BucketStats], currency: String = "USD") {
        self.sessions = sessions
        self.currency = currency
    }
    
    private var displaySessions: [BucketStats] {
        sessions.filter { $0.key != TradingSession.offHours.rawValue && $0.key.lowercased() != "off-hours" }
    }
    
    private var activeBucket: BucketStats? {
        guard let name = selectedSession else { return nil }
        return displaySessions.first { $0.key == name }
    }
    
    private var totalNetPnl: Decimal {
        displaySessions.reduce(Decimal.zero) { $0 + $1.netPnl }
    }
    
    private var yDomainMin: Double {
        let vals = displaySessions.map { ($0.netPnl as NSDecimalNumber).doubleValue }
        let minVal = vals.min() ?? 0
        return minVal < 0 ? minVal * 1.15 : 0
    }
    
    private var yDomainMax: Double {
        let vals = displaySessions.map { ($0.netPnl as NSDecimalNumber).doubleValue }
        let maxVal = vals.max() ?? 0
        return maxVal > 0 ? maxVal * 1.15 : 100
    }
    
    private func axisLabel(for key: String) -> String {
        switch key {
        case "London/NY Overlap", "London / NY Overlap", "London/NY":
            return "Overlap"
        default:
            return key
        }
    }
    
    public var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header with live active readout
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeBucket.map { $0.key.uppercased() } ?? "PERFORMANCE BY SESSION")
                            .font(AppTypography.cardHeaderUppercase)
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                            .lineLimit(1)
                        
                        Text(activeBucket.map { "\($0.trades) trades · WR \($0.winRate.map(Formatters.formatPercent) ?? "–")" } ?? "Net P&L grouped by market session")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(height: 36, alignment: .leading)
                    
                    Spacer()
                    
                    let displayPnl = activeBucket?.netPnl ?? totalNetPnl
                    Text(Formatters.formatPnL(displayPnl, currency: currency))
                        .font(AppTypography.displayMedium)
                        .monospacedDigit()
                        .foregroundColor(displayPnl >= 0 ? AppColors.profit : AppColors.loss)
                        .frame(height: 36, alignment: .trailing)
                }
                .frame(height: 38)
                
                if displaySessions.isEmpty {
                    AppEmptyState(
                        icon: "clock.badge.checkmark",
                        title: "No Session Data",
                        message: "Trades with execution times will be aggregated into standard trading sessions.",
                        isInCard: true
                    )
                    .frame(height: 160)
                } else {
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(AppColors.border.opacity(0.8))
                        
                        ForEach(displaySessions) { bucket in
                            let rawVal = (bucket.netPnl as NSDecimalNumber).doubleValue
                            let val = rawVal * animProgress
                            
                            BarMark(
                                x: .value("Session", bucket.key),
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
                            .opacity(selectedSession == nil || selectedSession == bucket.key ? 1.0 : 0.45)
                        }
                        
                        if let s = selectedSession {
                            RuleMark(x: .value("Selected", s))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(AppColors.primaryText.opacity(0.35))
                        }
                    }
                    .chartXSelection(value: $selectedSession)
                    .chartYScale(domain: yDomainMin...yDomainMax)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.border.opacity(0.3))
                            AxisValueLabel {
                                if let doubleVal = value.as(Double.self) {
                                    Text(Formatters.compactAxisValue(doubleVal, currency: currency))
                                        .font(AppTypography.numberMicro)
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let key = value.as(String.self) {
                                    Text(axisLabel(for: key))
                                        .font(AppTypography.captionBold)
                                        .foregroundStyle(AppColors.primaryText)
                                }
                            }
                        }
                    }
                    .animation(AppAnimations.chartEntrance, value: animProgress)
                    .frame(height: 160)
                    .onAppear {
                        guard animProgress == 0.0 else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(AppAnimations.chartEntrance) {
                                animProgress = 1.0
                            }
                        }
                    }
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
                    VStack(spacing: 8) {
                        ForEach(displaySessions) { bucket in
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bucket.key)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                    
                                    Text("\(bucket.trades) trades")
                                        .font(AppTypography.captionMicro)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }
                                
                                Spacer(minLength: 12)
                                
                                if let wr = bucket.winRate {
                                    Text("WR \(Formatters.formatPercent(wr))")
                                        .font(AppTypography.badgeMicro)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.border.opacity(0.4))
                                        .clipShape(Capsule())
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }
                                
                                Text(Formatters.formatPnL(bucket.netPnl, currency: currency))
                                    .font(AppTypography.statValue)
                                    .monospacedDigit()
                                    .foregroundColor(bucket.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }
    
    private func triggerHapticFeedback() {
        NativeHaptics.selection()
    }
}
