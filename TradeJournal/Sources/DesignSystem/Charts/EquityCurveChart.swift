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

public enum EquityChartMode: String, CaseIterable, Identifiable {
    case pnl = "P&L"
    case drawdown = "Underwater"
    
    public var id: String { rawValue }
}

private struct BeaconHeartbeatDotView: View {
    let color: Color
    
    var body: some View {
        ZStack {
            // Radiant aura ring
            Circle()
                .stroke(color.opacity(0.40), lineWidth: 1.5)
                .frame(width: 15, height: 15)
            
            // Soft radiant aura
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 14, height: 14)
            
            // Solid beacon dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.85), radius: 3)
            
            // Crisp white center core
            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
        }
    }
}

/// Cumulative Net P&L & Underwater Drawdown Chart conforming to Apple HIG & Professional Trading Standards.
/// Features:
/// - Smooth monotone interpolated curve with bipolar profit/loss area fills
/// - Live Pulsing Beacon on the latest point giving the chart a vibrant, active heartbeat
/// - High-Water Mark (ATH / All-Time High) horizontal dashed line with golden crown badge
/// - Mode Switcher: Instant toggle between Cumulative P&L ($) and Underwater Drawdown (%)
/// - Interactive touch scrubbing with floating HUD readout, ATH distance badge, and Apple haptics
public struct EquityCurveChart: View {
    public let points: [EquityPointItem]
    public let currency: String
    public let showArea: Bool
    public let height: CGFloat
    
    // Precomputed bounds & peak for instant 120 FPS scrubbing
    public let peakPoint: EquityPointItem?
    public let pnlDomainMin: Double
    public let pnlDomainMax: Double
    public let ddDomainMin: Double
    public let ddDomainMax: Double
    
    @State private var selectedDate: Date? = nil
    @State private var lastHapticPointId: String? = nil
    @State private var chartMode: EquityChartMode = .pnl
    @State private var animProgress: Double = 0.0
    
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
        
        var peak: EquityPointItem? = nil
        var maxPnl = -Double.infinity
        var minPnl = Double.infinity
        var minDd = 0.0
        
        for p in points {
            let pnlDouble = (p.cumulativePnl as NSDecimalNumber).doubleValue
            let ddDouble = -((p.drawdown as NSDecimalNumber).doubleValue * 100.0)
            if pnlDouble > maxPnl {
                maxPnl = pnlDouble
                peak = p
            }
            if pnlDouble < minPnl {
                minPnl = pnlDouble
            }
            if ddDouble < minDd {
                minDd = ddDouble
            }
        }
        self.peakPoint = peak
        
        if points.isEmpty {
            self.pnlDomainMin = 0.0
            self.pnlDomainMax = 100.0
            self.ddDomainMin = -5.0
            self.ddDomainMax = 0.5
        } else {
            // P&L bounds
            if maxPnl <= 0 && minPnl < 0 {
                self.pnlDomainMax = 0.0
            } else {
                let top = max(0.0, maxPnl)
                let span = max(1.0, top - min(0.0, minPnl))
                self.pnlDomainMax = top + (span * 0.08)
            }
            
            if minPnl >= 0 && maxPnl > 0 {
                self.pnlDomainMin = 0.0
            } else {
                let bottom = min(0.0, minPnl)
                let span = max(1.0, max(0.0, maxPnl) - bottom)
                self.pnlDomainMin = bottom - (span * 0.08)
            }
            
            // Drawdown bounds
            self.ddDomainMax = 0.5
            self.ddDomainMin = min(-1.0, minDd * 1.15)
        }
    }
    
    private var activePoint: EquityPointItem? {
        guard let target = selectedDate, !points.isEmpty else { return nil }
        var low = 0
        var high = points.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midDate = points[mid].date
            if midDate < target {
                low = mid + 1
            } else if midDate > target {
                high = mid - 1
            } else {
                return points[mid]
            }
        }
        if high < 0 { return points[0] }
        if low >= points.count { return points[points.count - 1] }
        let diffLow = abs(points[low].date.timeIntervalSince(target))
        let diffHigh = abs(points[high].date.timeIntervalSince(target))
        return diffLow < diffHigh ? points[low] : points[high]
    }
    
    private var lastPoint: EquityPointItem? {
        points.last
    }
    
    private var yDomainMax: Double {
        chartMode == .drawdown ? ddDomainMax : pnlDomainMax
    }
    
    private var yDomainMin: Double {
        chartMode == .drawdown ? ddDomainMin : pnlDomainMin
    }
    
    private var areaFillGradient: LinearGradient {
        if chartMode == .drawdown {
            return LinearGradient(
                colors: [
                    AppColors.loss.opacity(0.02),
                    AppColors.loss.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let top = yDomainMax
        let bottom = yDomainMin
        if bottom >= 0 {
            return LinearGradient(
                colors: [
                    AppColors.brand.opacity(0.28),
                    AppColors.brand.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if top <= 0 {
            return LinearGradient(
                colors: [
                    AppColors.loss.opacity(0.02),
                    AppColors.loss.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            let zeroFraction = CGFloat(top / (top - bottom))
            return LinearGradient(
                stops: [
                    .init(color: AppColors.brand.opacity(0.28), location: 0.0),
                    .init(color: AppColors.brand.opacity(0.02), location: max(0.0, zeroFraction - 0.001)),
                    .init(color: AppColors.loss.opacity(0.02), location: min(1.0, zeroFraction + 0.001)),
                    .init(color: AppColors.loss.opacity(0.28), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var lineStrokeGradient: LinearGradient {
        if chartMode == .drawdown {
            return LinearGradient(colors: [AppColors.loss, AppColors.loss], startPoint: .top, endPoint: .bottom)
        }
        let top = yDomainMax
        let bottom = yDomainMin
        if bottom >= 0 {
            return LinearGradient(colors: [AppColors.brand, AppColors.brand], startPoint: .top, endPoint: .bottom)
        } else if top <= 0 {
            return LinearGradient(colors: [AppColors.loss, AppColors.loss], startPoint: .top, endPoint: .bottom)
        } else {
            let zeroFraction = CGFloat(top / (top - bottom))
            return LinearGradient(
                stops: [
                    .init(color: AppColors.brand, location: 0.0),
                    .init(color: AppColors.brand, location: max(0.0, zeroFraction - 0.002)),
                    .init(color: AppColors.loss, location: min(1.0, zeroFraction + 0.002)),
                    .init(color: AppColors.loss, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private static let hudDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else {
            return Date()...Date().addingTimeInterval(86400)
        }
        if first == last {
            return first.addingTimeInterval(-86400)...last.addingTimeInterval(86400)
        }
        return first...last
    }
    
    private var visibleDateMarks: [Date] {
        guard points.count >= 2 else { return points.map { $0.date } }
        let count = points.count
        if count <= 5 {
            return points.map { $0.date }
        }
        let target = 4
        let step = Double(count - 1) / Double(target - 1)
        var marks: [Date] = []
        for i in 0..<target {
            let idx = min(count - 1, max(0, Int(round(Double(i) * step))))
            marks.append(points[idx].date)
        }
        return marks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Interactive HUD & Mode Toggle Header
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
                    // Reference Zero Baseline
                    RuleMark(y: .value("Zero", 0.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.85))
                    
                    // High-Water Mark (ATH / All-Time High) dashed line in P&L mode
                    if chartMode == .pnl, let peak = peakPoint, peak.cumulativePnl > 0, points.count >= 3, animProgress > 0.8 {
                        let peakVal = (peak.cumulativePnl as NSDecimalNumber).doubleValue
                        RuleMark(y: .value("ATH", peakVal))
                            .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [4, 4]))
                            .foregroundStyle(Color.yellow.opacity(0.40))
                            .annotation(position: .top, alignment: .leading) {
                                HStack(spacing: 3) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 9))
                                    Text("ATH \(Formatters.formatCurrency(peak.cumulativePnl, currency: currency))")
                                        .font(AppTypography.number(9, weight: .bold))
                                }
                                .foregroundColor(Color.yellow.opacity(0.92))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.12))
                                .clipShape(Capsule())
                            }
                    }
                    
                    ForEach(points) { point in
                        let targetVal: Double = {
                            if chartMode == .drawdown {
                                return -((point.drawdown as NSDecimalNumber).doubleValue * 100.0)
                            }
                            return (point.cumulativePnl as NSDecimalNumber).doubleValue
                        }()
                        let val: Double = targetVal * animProgress
                        
                        if showArea {
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Value", val)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(areaFillGradient)
                            .alignsMarkStylesWithPlotArea()
                        }
                        
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", val)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(lineStrokeGradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .alignsMarkStylesWithPlotArea()
                    }
                    
                    // Live Beacon Heartbeat Dot on latest point when not scrubbing
                    if activePoint == nil, let last = lastPoint, animProgress > 0.8 {
                        let lastVal: Double = {
                            if chartMode == .drawdown {
                                return -((last.drawdown as NSDecimalNumber).doubleValue * 100.0)
                            }
                            return (last.cumulativePnl as NSDecimalNumber).doubleValue
                        }()
                        let beaconColor = (chartMode == .drawdown) ? AppColors.loss : (lastVal >= 0 ? AppColors.brand : AppColors.loss)
                        
                        PointMark(
                            x: .value("Date", last.date),
                            y: .value("Value", lastVal)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .overlay) {
                            BeaconHeartbeatDotView(color: beaconColor)
                        }
                    }
                    
                    // Interactive Touch Crosshair & Cursor Node
                    if let active = activePoint {
                        let activeVal: Double = {
                            if chartMode == .drawdown {
                                return -((active.drawdown as NSDecimalNumber).doubleValue * 100.0)
                            }
                            return (active.cumulativePnl as NSDecimalNumber).doubleValue
                        }()
                        let cursorColor = (chartMode == .drawdown) ? AppColors.loss : (activeVal >= 0 ? AppColors.brand : AppColors.loss)
                        
                        RuleMark(x: .value("Cursor", active.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.45))
                        
                        // Halo
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Value", activeVal)
                        )
                        .foregroundStyle(cursorColor.opacity(0.25))
                        .symbolSize(64)
                        
                        // Glowing bead
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Value", activeVal)
                        )
                        .foregroundStyle(cursorColor)
                        .symbolSize(36)
                        
                        // Core center
                        PointMark(
                            x: .value("Date", active.date),
                            y: .value("Value", activeVal)
                        )
                        .foregroundStyle(Color.white)
                        .symbolSize(10)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    AxisMarks(values: visibleDateMarks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .chartYScale(domain: yDomainMin...yDomainMax)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let doubleVal = value.as(Double.self) {
                                if chartMode == .drawdown {
                                    Text(String(format: "%.0f%%", doubleVal))
                                        .font(AppTypography.number(10, weight: .medium))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .frame(width: 36, alignment: .trailing)
                                } else {
                                    Text(Formatters.compactAxisValue(doubleVal, currency: currency))
                                        .font(AppTypography.number(10, weight: .medium))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .frame(width: 36, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.90, dampingFraction: 0.82), value: animProgress)
                .frame(height: height)
                .onAppear {
                    guard animProgress == 0.0 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.90, dampingFraction: 0.82)) {
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
    
    @ViewBuilder
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // Left Column: Date & Values
            VStack(alignment: .leading, spacing: 2) {
                if let active = activePoint {
                    // Top sub-row: Date
                    Text(Self.hudDateFormatter.string(from: active.date))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .frame(height: 14, alignment: .leading)
                    
                    // Bottom sub-row: Main Value + Delta Chip
                    HStack(spacing: 5) {
                        if chartMode == .drawdown {
                            let ddPct = (active.drawdown as NSDecimalNumber).doubleValue * 100.0
                            Text(String(format: "-%.1f%% DD", ddPct))
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(AppColors.loss)
                                .lineLimit(1)
                        } else {
                            Text(Formatters.formatPnL(active.cumulativePnl, currency: currency))
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(active.cumulativePnl >= 0 ? AppColors.brand : AppColors.loss)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            if let peak = peakPoint, active.id == peak.id, peak.cumulativePnl > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 9))
                                    Text("ATH")
                                        .font(AppTypography.badgeMicro)
                                }
                                .foregroundColor(Color.yellow)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.yellow.opacity(0.14))
                                .clipShape(Capsule())
                                .lineLimit(1)
                            } else if active.netPnl != 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: active.netPnl > 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(Formatters.formatPnL(active.netPnl, currency: currency))
                                        .font(AppTypography.number(10, weight: .bold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background((active.netPnl > 0 ? AppColors.profit : AppColors.loss).opacity(0.14))
                                .foregroundColor(active.netPnl > 0 ? AppColors.profit : AppColors.loss)
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    .frame(height: 20, alignment: .leading)
                    .lineLimit(1)
                } else if let last = lastPoint {
                    // When not scrubbing: Status label & running total
                    if chartMode == .drawdown {
                        let lastDdPct = (last.drawdown as NSDecimalNumber).doubleValue * 100.0
                        Text("Current Drawdown")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                            .frame(height: 14, alignment: .leading)
                        
                        Text(String(format: "-%.1f%%", lastDdPct))
                            .font(AppTypography.number(13, weight: .bold))
                            .foregroundColor(lastDdPct > 0.05 ? AppColors.loss : AppColors.profit)
                            .lineLimit(1)
                            .frame(height: 20, alignment: .leading)
                    } else {
                        Text("Running Equity")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                            .frame(height: 14, alignment: .leading)
                        
                        Text(Formatters.formatPnL(last.cumulativePnl, currency: currency))
                            .font(AppTypography.number(13, weight: .bold))
                            .foregroundColor(last.cumulativePnl >= 0 ? AppColors.brand : AppColors.loss)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(height: 20, alignment: .leading)
                    }
                }
            }
            .frame(height: 36, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Mode Switcher Capsule: [ P&L | Underwater ]
            HStack(spacing: 2) {
                ForEach(EquityChartMode.allCases) { mode in
                    Button {
                        #if os(iOS)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            chartMode = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: chartMode == mode ? .bold : .medium))
                            .foregroundColor(chartMode == mode ? AppColors.primaryText : AppColors.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                chartMode == mode ?
                                Capsule().fill(AppColors.cardBackground).shadow(color: Color.black.opacity(0.14), radius: 2) :
                                nil
                            )
                    }
                }
            }
            .padding(2)
            .background(AppColors.border.opacity(0.35))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: 38)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
    
    private func triggerHapticFeedback() {
        NativeHaptics.selection()
    }
}
