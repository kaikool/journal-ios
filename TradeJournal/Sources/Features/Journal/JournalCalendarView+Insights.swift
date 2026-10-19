import SwiftUI
import Charts

extension JournalCalendarView {
    // MARK: - Performance Insights Section matching calendar-insights.tsx
    
    @ViewBuilder
    var performanceInsightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Performance insights")
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.primaryText)
                
                Text("Visible month × active filters · Closed trades, after fees")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 2)
            
            if insights.tradingDays == 0 {
                AppCard {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 26))
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("No closed trades in this view")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Choose another month or adjust your account and filters. Open positions and days without trades aren't included in performance insights.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                // 4 Metric cards matching calendar-insights.tsx lines 136-168
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricCard(
                        title: "Net P&L",
                        value: Formatters.formatPnL(insights.netPnl, currency: env.currentCurrency),
                        detail: "\(insights.tradingDays) trading day\(insights.tradingDays == 1 ? "" : "s") · \(env.currentCurrency)",
                        valueColor: insights.netPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    metricCard(
                        title: "Average daily P&L",
                        value: Formatters.formatPnL(insights.avgDailyPnl ?? .zero, currency: env.currentCurrency),
                        detail: "Per day with closed trades",
                        valueColor: (insights.avgDailyPnl ?? .zero) >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    metricCard(
                        title: "Trade win rate",
                        value: String(format: "%.1f%%", (insights.winRate ?? 0) * 100),
                        detail: "\(insights.wins) wins · \(insights.losses) losses · \(insights.breakevens) break-even",
                        valueColor: AppColors.primaryText
                    )
                    
                    metricCard(
                        title: "Total closed trades",
                        value: "\(insights.trades)",
                        detail: "Round-trip trades, not executions",
                        valueColor: AppColors.primaryText
                    )
                }
                
                // Extrema & Consistency Cards matching calendar-insights.tsx lines 171-218
                VStack(spacing: 10) {
                    // Best & Worst Day
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Best & worst day")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                Text("Best day")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                if let best = insights.bestDay {
                                    HStack(spacing: 6) {
                                        AppMonetaryText(
                                            Formatters.formatPnL(best.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: AppColors.profit
                                        )
                                        Text(dateLabel(for: best.date))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                } else {
                                    Text("—").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                                }
                            }
                            
                            HStack {
                                Text("Worst day")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                if let worst = insights.worstDay {
                                    HStack(spacing: 6) {
                                        AppMonetaryText(
                                            Formatters.formatPnL(worst.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: AppColors.loss
                                        )
                                        Text(dateLabel(for: worst.date))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                } else {
                                    Text("—").font(AppTypography.caption).foregroundColor(AppColors.secondaryText)
                                }
                            }
                            
                            Text(insights.tradingDays == 1 ? "One trading day; both extrema are the same." : "Highest and lowest daily net P&L.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.mutedText)
                        }
                    }
                    
                    // Average green & red day
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Average green & red day")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack {
                                Text("\(insights.greenDays) profitable days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                AppMonetaryText(
                                    Formatters.formatPnL(insights.avgGreenDay ?? .zero, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.profit
                                )
                            }
                            
                            HStack {
                                Text("\(insights.redDays) losing days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                AppMonetaryText(
                                    Formatters.formatPnL(insights.avgRedDay ?? .zero, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.loss
                                )
                            }
                            
                            Text("Each average uses only its own group.")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.mutedText)
                        }
                    }
                    
                    // Day consistency
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Day consistency")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                Text("\(insights.greenDays) positive · \(insights.redDays) negative · \(insights.flatDays) flat days")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Spacer()
                            
                            let rate = (insights.profitableDayRate ?? 0) * 100
                            Text(String(format: "%.1f%%", rate))
                                .font(AppTypography.financialNumber(size: 18, weight: .semibold))
                                .foregroundColor(rate >= 50 ? AppColors.profit : AppColors.secondaryText)
                        }
                    }
                }
                
                // Detailed Charts: Daily Performance & Weekday Performance
                dailyPerformanceCard
                weekdayPerformanceCard
                
                if insights.tradingDays < 5 {
                    Text("Small sample: \(insights.tradingDays) trading day\(insights.tradingDays == 1 ? "" : "s"). Weekday results and consistency describe this selection only.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.mutedText)
                        .padding(.horizontal, 2)
                }
            }
        }
    }
    
    // MARK: - Daily Performance Chart Card matching calendar-insights.tsx lines 220-289
    
    @ViewBuilder
    var dailyPerformanceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily performance")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Net P&L by closing day · \(env.currentCurrency)\(insights.tradingDays >= 8 ? " · Dashed line: 5-trading-day average" : "")")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                if insights.tradingDays >= 2 {
                    let activeTrend = insights.trend.first { dateLabel(for: $0.date) == selectedTrendDate }
                    let trendLabels = insights.trend.map { dateLabel(for: $0.date) }
                    let visibleTrendMarks: [String] = {
                        guard !trendLabels.isEmpty else { return [] }
                        let count = trendLabels.count
                        if count <= 5 { return trendLabels }
                        let target = 5
                        let step = Double(count - 1) / Double(target - 1)
                        var indices = [Int]()
                        for i in 0..<target {
                            let idx = min(count - 1, max(0, Int(round(Double(i) * step))))
                            if !indices.contains(idx) {
                                indices.append(idx)
                            }
                        }
                        return indices.map { trendLabels[$0] }
                    }()
                    
                    if let active = activeTrend {
                        HStack {
                            Text(dateLabel(for: active.date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(Formatters.formatPnL(active.netPnl, currency: env.currentCurrency))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(active.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        }
                        .padding(.horizontal, 2)
                    }
                    
                    Chart {
                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(AppColors.border.opacity(0.8))
                        
                        ForEach(insights.trend) { pt in
                            let label = dateLabel(for: pt.date)
                            BarMark(
                                x: .value("Day", label),
                                y: .value("Net P&L", (pt.netPnl as NSDecimalNumber).doubleValue)
                            )
                            .foregroundStyle(
                                pt.netPnl >= 0 ?
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
                            .opacity(selectedTrendDate == nil || selectedTrendDate == label ? 1.0 : 0.45)
                        }
                        
                        if insights.tradingDays >= 8 {
                            ForEach(insights.trend.filter { $0.average != nil }) { pt in
                                LineMark(
                                    x: .value("Day", dateLabel(for: pt.date)),
                                    y: .value("5-Day Avg", ((pt.average ?? .zero) as NSDecimalNumber).doubleValue)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                .foregroundStyle(AppColors.brand)
                            }
                        }
                        
                        if let sel = selectedTrendDate {
                            RuleMark(x: .value("Selected", sel))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .foregroundStyle(AppColors.primaryText.opacity(0.4))
                        }
                    }
                    .chartXSelection(value: $selectedTrendDate)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.border.opacity(0.3))
                            AxisValueLabel {
                                if let d = value.as(Double.self) {
                                    Text(Formatters.formatCurrency(Decimal(d), currency: env.currentCurrency))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: visibleTrendMarks) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(AppColors.border.opacity(0.25))
                            AxisValueLabel()
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    .frame(height: 160)
                } else {
                    VStack(spacing: 4) {
                        Text("A trend needs more than one day")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        if let first = insights.days.first {
                            Text("\(dateLabel(for: first.date)) · \(Formatters.formatPnL(first.netPnl, currency: env.currentCurrency)) · \(first.trades) closed trades")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        Text("Explore an earlier month with more trading history.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(AppColors.secondaryBackground.opacity(0.3))
                    .cornerRadius(6)
                }
                
                // Collapsible Daily Values Table matching calendar-insights.tsx line 247-287
                DisclosureGroup(
                    isExpanded: $showDailyTable,
                    content: {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Closing day").font(.system(size: 10, weight: .medium)).foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("Trades").font(.system(size: 10, weight: .medium)).foregroundColor(AppColors.secondaryText)
                                    .frame(width: 50, alignment: .trailing)
                                Text("Net P&L").font(.system(size: 10, weight: .medium)).foregroundColor(AppColors.secondaryText)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.top, 4)
                            
                            Divider().background(AppColors.border)
                            
                            ForEach(insights.days) { day in
                                Button(action: {
                                    openDayDetail(for: day.date)
                                }) {
                                    HStack {
                                        Text(dateLabel(for: day.date))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.brand)
                                        Spacer()
                                        Text("\(day.trades)")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.primaryText)
                                            .frame(width: 50, alignment: .trailing)
                                        AppMonetaryText(
                                            Formatters.formatPnL(day.netPnl, currency: env.currentCurrency),
                                            isPrivate: env.isPrivacyModeEnabled,
                                            font: AppTypography.captionBold,
                                            color: day.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                        )
                                        .frame(width: 80, alignment: .trailing)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    },
                    label: {
                        Text("Daily values & trade links (\(insights.tradingDays))")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                )
            }
        }
    }
    
    // MARK: - Weekday Performance Card matching calendar-insights.tsx lines 290-384
    
    @ViewBuilder
    var weekdayPerformanceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance by weekday")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Text("Closing-day net P&L · \(env.currentCurrency) · Select a row")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                // Highlight box: Most profitable weekday
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Most profitable weekday")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(AppColors.mutedText)
                        
                        if let bestWd = insights.mostProfitableWeekday {
                            HStack(spacing: 8) {
                                Text(bestWd.label)
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.primaryText)
                                
                                AppMonetaryText(
                                    Formatters.formatPnL(bestWd.netPnl, currency: env.currentCurrency),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.captionBold,
                                    color: AppColors.profit
                                )
                            }
                        } else {
                            Text("No profitable weekday yet")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .background(AppColors.secondaryBackground.opacity(0.4))
                .cornerRadius(6)
                
                // 7 Weekday rows with bidirectional progress bar matching calendar-insights.tsx lines 314-360
                VStack(spacing: 4) {
                    ForEach(insights.weekdays) { wd in
                        weekdayRowView(wd: wd)
                    }
                }
                
                // Selected weekday detailed closing days matching calendar-insights.tsx lines 362-381
                if let selectedIndex = selectedWeekdayIndex,
                   let selected = insights.weekdays.first(where: { $0.index == selectedIndex }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider().background(AppColors.border)
                        
                        Text("\(selected.label) · \(selected.trades) trades across \(selected.days.count) days")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.primaryText)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(selected.days) { day in
                                    Button(action: {
                                        openDayDetail(for: day.date)
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(dateLabel(for: day.date))
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.primaryText)
                                            Text("· \(day.trades)t")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppColors.cardBackground)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(AppColors.border, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Weekday Row View with Bidirectional Bar
    
    @ViewBuilder
    func weekdayRowView(wd: WeekdayPerformance) -> some View {
        let isSelected = selectedWeekdayIndex == wd.index
        let hasTrades = wd.trades > 0
        let pnlDouble = (wd.netPnl as NSDecimalNumber).doubleValue
        let ratio = peakWeekdayAbsPnl > 0 ? (abs(pnlDouble) / peakWeekdayAbsPnl) : 0
        let isProfit = wd.netPnl >= 0
        
        Button(action: {
            guard hasTrades else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedWeekdayIndex = (selectedWeekdayIndex == wd.index) ? nil : wd.index
            }
        }) {
            HStack(spacing: 8) {
                Text(String(wd.label.prefix(3)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(hasTrades ? AppColors.primaryText : AppColors.mutedText)
                    .frame(width: 28, alignment: .leading)
                
                // Bidirectional horizontal bar centered at 50%
                GeometryReader { geo in
                    let halfWidth = geo.size.width / 2
                    let barWidth = max(2.0, halfWidth * CGFloat(min(1.0, ratio)))
                    
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.secondaryBackground.opacity(0.3))
                            .frame(height: 6)
                        
                        // Center axis mark
                        Rectangle()
                            .fill(AppColors.border)
                            .frame(width: 1, height: 12)
                            .offset(x: halfWidth)
                        
                        if hasTrades {
                            if isProfit {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.profit)
                                    .frame(width: barWidth, height: 6)
                                    .offset(x: halfWidth)
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.loss)
                                    .frame(width: barWidth, height: 6)
                                    .offset(x: halfWidth - barWidth)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)
                
                // Formatted P&L on right
                if hasTrades {
                    AppMonetaryText(
                        Formatters.formatPnL(wd.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: .system(size: 11, weight: .semibold, design: .monospaced),
                        color: isProfit ? AppColors.profit : AppColors.loss
                    )
                    .frame(width: 76, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(AppColors.mutedText)
                        .frame(width: 76, alignment: .trailing)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isSelected ? AppColors.cardBackground : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? AppColors.border : Color.clear, lineWidth: 1)
            )
        }
        .disabled(!hasTrades)
    }
    
    // MARK: - Metric Card Component
    
    func metricCard(title: String, value: String, detail: String, valueColor: Color) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                AppMonetaryText(
                    value,
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 17, weight: .semibold),
                    color: valueColor
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
}
