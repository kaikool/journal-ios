import SwiftUI
import Charts

public struct DailyBarDatum: Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let netPnl: Decimal
    public let dateObj: Date
    
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    public init(date: String, netPnl: Decimal) {
        self.date = date
        self.netPnl = netPnl
        self.dateObj = Self.isoDayFormatter.date(from: date) ?? Date()
    }

    public init(date: String, netPnl: Decimal, dateObj: Date) {
        self.date = date
        self.netPnl = netPnl
        self.dateObj = dateObj
    }
}

private struct HeartbeatStarView: View {
    var body: some View {
        ZStack {
            // Radiant golden halo
            Image(systemName: "star.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.yellow.opacity(0.35))
                .scaleEffect(1.35)
            
            // Core golden star
            Image(systemName: "star.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(Color.yellow)
                .shadow(color: Color.yellow.opacity(0.8), radius: 2.5)
        }
        .frame(width: 18, height: 18)
        .padding(.bottom, 2)
    }
}

private struct HeartbeatWarningView: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundColor(AppColors.loss)
            .shadow(color: AppColors.loss.opacity(0.7), radius: 2.5)
            .frame(width: 18, height: 18)
            .padding(.top, 2)
    }
}

/// Apple HIG Daily Net P&L Chart ported from `components/charts/daily-bars.tsx`.
/// Features:
/// - Bars growing upward (profit) or downward (loss) from zero baseline
/// - Best Day (⭐️) and Worst Day (⚠️) badges & emerald-golden gradients
/// - Rounded caps at data ends with subtle gradient fills
/// - Interactive touch scrubbing with floating HUD readout and haptic feedback
public struct DailyBarsView: View {
    public let data: [DailyBarDatum]
    public let currency: String
    public let isPrivate: Bool
    public let height: CGFloat
    
    // Precomputed metrics & bounds for smooth 120 FPS scrubbing
    public let bestDay: DailyBarDatum?
    public let worstDay: DailyBarDatum?
    public let yDomainMin: Double
    public let yDomainMax: Double
    public let barWidth: CGFloat
    public let xDomain: ClosedRange<Date>
    public let visibleDateObjs: [Date]
    public let visibleDateMarks: [String]
    
    @State private var selectedDateObj: Date? = nil
    @State private var lastHapticDate: String? = nil
    @State private var animProgress: Double = 0.0
    
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
        
        if data.count >= 2 {
            let profitDays = data.filter { $0.netPnl > 0 }
            self.bestDay = profitDays.max(by: { $0.netPnl < $1.netPnl })
            let lossDays = data.filter { $0.netPnl < 0 }
            self.worstDay = lossDays.min(by: { $0.netPnl < $1.netPnl })
        } else {
            self.bestDay = nil
            self.worstDay = nil
        }
        
        let pnlDoubles = data.map { isPrivate ? 0.0 : ($0.netPnl as NSDecimalNumber).doubleValue }
        let minVal = pnlDoubles.min() ?? 0.0
        let maxVal = pnlDoubles.max() ?? 0.0
        self.yDomainMin = minVal < 0 ? (minVal * 1.28) - 15 : 0.0
        self.yDomainMax = maxVal > 0 ? (maxVal * 1.28) + 15 : 100.0
        
        let count = data.count
        if count <= 2 { self.barWidth = 18 }
        else if count <= 5 { self.barWidth = 14 }
        else if count <= 15 { self.barWidth = 10 }
        else if count <= 30 { self.barWidth = 6 }
        else { self.barWidth = 4 }
        
        if let first = data.first?.dateObj, let last = data.last?.dateObj {
            let diff = max(0, last.timeIntervalSince(first))
            let margin = max(86400.0 * 2.0, diff * 0.15)
            self.xDomain = first.addingTimeInterval(-margin)...last.addingTimeInterval(margin)
        } else {
            let now = Date()
            self.xDomain = now.addingTimeInterval(-86400 * 2)...now.addingTimeInterval(86400 * 2)
        }
        
        if count <= 5 {
            self.visibleDateObjs = data.map { $0.dateObj }
            self.visibleDateMarks = data.map { $0.date }
        } else {
            let target = 4
            let step = Double(count - 1) / Double(target - 1)
            var marks: [Date] = []
            for i in 0..<target {
                let idx = min(count - 1, max(0, Int(round(Double(i) * step))))
                marks.append(data[idx].dateObj)
            }
            self.visibleDateObjs = marks
            
            let targetMarks = 5
            let stepMarks = Double(count - 1) / Double(targetMarks - 1)
            var indices = [Int]()
            for i in 0..<targetMarks {
                let idx = min(count - 1, max(0, Int(round(Double(i) * stepMarks))))
                if !indices.contains(idx) {
                    indices.append(idx)
                }
            }
            self.visibleDateMarks = indices.map { data[$0].date }
        }
    }
    
    private var activeDatum: DailyBarDatum? {
        guard let target = selectedDateObj, !data.isEmpty else { return nil }
        var low = 0
        var high = data.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midDate = data[mid].dateObj
            if midDate < target {
                low = mid + 1
            } else if midDate > target {
                high = mid - 1
            } else {
                return data[mid]
            }
        }
        if high < 0 { return data[0] }
        if low >= data.count { return data[data.count - 1] }
        let diffLow = abs(data[low].dateObj.timeIntervalSince(target))
        let diffHigh = abs(data[high].dateObj.timeIntervalSince(target))
        return diffLow < diffHigh ? data[low] : data[high]
    }
    
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    private static let axisDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    private static let hudDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Readout Header (Active HUD or Best/Worst Overview)
            headerView
            
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
                        let rawVal = isPrivate ? 0 : (entry.netPnl as NSDecimalNumber).doubleValue
                        let val = rawVal * animProgress
                        let isBest = (entry.id == bestDay?.id)
                        let isWorst = (entry.id == worstDay?.id)
                        
                        BarMark(
                            x: .value("Date", entry.dateObj, unit: .day),
                            y: .value("Net P&L", val),
                            width: .fixed(barWidth)
                        )
                        .foregroundStyle(
                            isBest ?
                            LinearGradient(
                                colors: [Color(red: 0.25, green: 0.95, blue: 0.55), AppColors.profit],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
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
                        .cornerRadius(2.5)
                        .opacity(activeDatum == nil || activeDatum?.id == entry.id ? 1.0 : 0.40)
                        .annotation(position: entry.netPnl >= 0 ? .top : .bottom, spacing: 3) {
                            if isBest && !isPrivate && animProgress > 0.8 {
                                HeartbeatStarView()
                            } else if isWorst && !isPrivate && animProgress > 0.8 {
                                HeartbeatWarningView()
                            }
                        }
                    }
                    
                    if let active = activeDatum {
                        RuleMark(x: .value("Cursor", active.dateObj, unit: .day))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedDateObj)
                .chartXScale(domain: xDomain)
                .chartYScale(domain: yDomainMin...yDomainMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(isPrivate ? "••••" : Formatters.compactAxisValue(d, currency: currency))
                                    .font(AppTypography.number(10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: visibleDateObjs) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.25))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                    }
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
                .onChange(of: selectedDateObj) { newDate in
                    if let d = activeDatum?.date, d != lastHapticDate {
                        lastHapticDate = d
                        triggerHapticFeedback()
                    } else if newDate == nil {
                        lastHapticDate = nil
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack(spacing: 6) {
            if let active = activeDatum {
                Text(formatDate(active.date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                
                if active.id == bestDay?.id && !isPrivate {
                    HStack(spacing: 3) {
                        HeartbeatStarView()
                        Text("Best Day")
                            .font(AppTypography.badgeMicro)
                    }
                    .foregroundColor(Color.yellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.14))
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                } else if active.id == worstDay?.id && !isPrivate {
                    HStack(spacing: 3) {
                        HeartbeatWarningView()
                        Text("Max Loss")
                            .font(AppTypography.badgeMicro)
                    }
                    .foregroundColor(AppColors.loss)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColors.loss.opacity(0.14))
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                Spacer(minLength: 4)
                
                Text(isPrivate ? "••••" : Formatters.formatPnL(active.netPnl, currency: currency))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if !data.isEmpty {
                if let best = bestDay {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color.yellow)
                        Text("Best:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(isPrivate ? "••••" : Formatters.formatPnL(best.netPnl, currency: currency))
                            .font(AppTypography.number(10, weight: .bold))
                            .foregroundColor(AppColors.profit)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                
                Spacer(minLength: 4)
                
                if let worst = worstDay {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppColors.loss.opacity(0.85))
                        Text("Worst:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(isPrivate ? "••••" : Formatters.formatPnL(worst.netPnl, currency: currency))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(AppColors.loss)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
            }
        }
        .frame(height: 22, alignment: .center)
        .padding(.horizontal, 4)
    }
    
    private func formatAxisDate(_ dateStr: String) -> String {
        if let d = Self.isoDateFormatter.date(from: dateStr) {
            return Self.axisDateFormatter.string(from: d)
        }
        return String(dateStr.suffix(5))
    }
    
    private func formatDate(_ dateStr: String) -> String {
        if let d = Self.isoDateFormatter.date(from: dateStr) {
            return Self.hudDateFormatter.string(from: d)
        }
        return dateStr
    }
    
    private func triggerHapticFeedback() {
        NativeHaptics.selection()
    }
}
