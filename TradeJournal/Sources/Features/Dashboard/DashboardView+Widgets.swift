import SwiftUI
import Charts

// MARK: - Dashboard Card Wrapper with Interactive Reorder Bar

internal struct DashboardCardWrapper<Content: View>: View {
    let cardId: String
    let isEditing: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onHide: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing, let item = DashboardCardRegistry.item(for: cardId) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text(item.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Move Up Button
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(.plain)
                    
                    // Move Down Button
                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(.plain)
                    
                    // Hide Button
                    Button {
                        onHide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.loss)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 6)
            }
            
            content()
        }
        .overlay(
            isEditing ?
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.brand.opacity(0.4), lineWidth: 1.5)
                : nil
        )
    }
}

extension DashboardView {
    
    // MARK: - Universal Widget Dispatcher & Reorder Wrapper
    
    @ViewBuilder
    internal func renderWidget(id: String, snap: DashboardSnapshot, isCompact: Bool) -> some View {
        DashboardCardWrapper(
            cardId: id,
            isEditing: isEditingLayout,
            onMoveUp: { moveCard(cardId: id, direction: -1) },
            onMoveDown: { moveCard(cardId: id, direction: 1) },
            onHide: { hideCard(cardId: id) }
        ) {
            switch id {
            case "widget-0": widget0NetPnl(snap: snap, isCompact: isCompact)
            case "widget-1": widget1TradeWin(snap: snap, isCompact: isCompact)
            case "widget-2": widget2ProfitFactor(snap: snap, isCompact: isCompact)
            case "widget-3": widget3DayWin(snap: snap, isCompact: isCompact)
            case "widget-4": widget4AvgWinLoss(snap: snap, isCompact: isCompact)
            case "widget-5": widget5EdgeScore(snap: snap)
            case "widget-6": widget6CumulativePnl(snap: snap)
            case "widget-7": widget7DailyPnl(snap: snap)
            case "widget-8": widget8Calendar(snap: snap)
            case "widget-9": widget9Activity(snap: snap)
            case "widget-10": widget10MaxDrawdown(snap: snap, isCompact: isCompact)
            case "widget-11": widget11Streaks(snap: snap, isCompact: isCompact)
            case "widget-12": widget12Expectancy(snap: snap, isCompact: isCompact)
            case "widget-13": widget13AvgDuration(snap: snap, isCompact: isCompact)
            case "widget-14": widget14BestWorstDay(snap: snap, isCompact: isCompact)
            case "widget-15": widget15TradeTimePerformance(snap: snap)
            default: EmptyView()
            }
        }
    }
    
    // MARK: - 16 Canonical Widgets (1:1 port from apps/web/src/app/page.tsx)
    
    // Widget 0: Net P&L (CircleDollarSign)
    @ViewBuilder
    internal func widget0NetPnl(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Net P&L",
                    icon: "dollarsign.circle",
                    hint: "Realized net profit (Gross P&L minus fees). Sum of all trade net results; fees are already accounted for."
                )
                
                if isCompact {
                    Spacer(minLength: 2)
                    AppMonetaryText(
                        Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                        isPrivate: env.isPrivacyModeEnabled,
                        font: AppTypography.financialNumber(size: 20, weight: .bold),
                        color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                    )
                    
                    if let delta = snap.weekDelta {
                        HStack(spacing: 3) {
                            Text(delta >= 0 ? "▲" : "▼")
                                .font(.system(size: 9, weight: .bold))
                            Text(Formatters.formatCurrency(abs(delta), currency: env.currentCurrency))
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                            Text("vs 7d")
                                .font(AppTypography.caption)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(delta >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                        .foregroundColor(delta >= 0 ? AppColors.profit : AppColors.loss)
                        .clipShape(Capsule())
                    }
                    
                    Text("\(metrics.closedTrades) closed · Gross: \(Formatters.formatPnL(metrics.grossPnl ?? metrics.netPnl, currency: env.currentCurrency)) · Fees: \(Formatters.formatCurrency(metrics.fees ?? 0, currency: env.currentCurrency))")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        AppMonetaryText(
                            Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 28, weight: .bold),
                            color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                        
                        Spacer()
                        
                        if let delta = snap.weekDelta {
                            HStack(spacing: 3) {
                                Text(delta >= 0 ? "▲" : "▼")
                                    .font(.system(size: 9, weight: .bold))
                                Text(Formatters.formatCurrency(abs(delta), currency: env.currentCurrency))
                                    .font(AppTypography.captionBold)
                                    .monospacedDigit()
                                Text("vs prior 7d")
                                    .font(AppTypography.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(delta >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                            .foregroundColor(delta >= 0 ? AppColors.profit : AppColors.loss)
                            .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text("\(metrics.closedTrades) closed trades")
                        Text("·")
                        Text("Gross: \(Formatters.formatPnL(metrics.grossPnl ?? metrics.netPnl, currency: env.currentCurrency))")
                        Text("·")
                        Text("Fees: \(Formatters.formatCurrency(metrics.fees ?? 0, currency: env.currentCurrency))")
                    }
                    .font(AppTypography.caption)
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 1: Trade win % (Target)
    @ViewBuilder
    internal func widget1TradeWin(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Trade win %",
                    icon: "target",
                    hint: "Winning trades divided by all closed trades, including breakevens."
                )
                
                Spacer(minLength: 2)
                
                HStack(alignment: .center, spacing: 8) {
                    GaugeView(value: metrics.winRate, label: "Trade win rate", size: 68)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(metrics.wins) W")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.profit)
                        Text("\(metrics.breakevens) BE")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(metrics.losses) L")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.loss)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 2: Profit factor (Scale)
    @ViewBuilder
    internal func widget2ProfitFactor(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Profit factor",
                    icon: "scalemass",
                    hint: "Gross profit ÷ gross loss. Above 1 means the wins outweigh the losses."
                )
                
                Spacer(minLength: 4)
                
                Text(metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor.map { String(format: "%.2f", $0) } ?? "–"))
                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                Text("gross profit ÷ gross loss")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 3: Day win % (CalendarCheck2)
    @ViewBuilder
    internal func widget3DayWin(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Day win %",
                    icon: "calendar.badge.clock",
                    hint: "Green trading days ÷ all trading days in the selected range."
                )
                
                Spacer(minLength: 2)
                
                HStack(alignment: .center, spacing: 8) {
                    GaugeView(value: metrics.dayWinRate, label: "Day win rate", size: 68)
                    
                    Spacer()
                    
                    Text("\(metrics.tradingDays) days")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 4: Avg win / loss (ArrowUpDown)
    @ViewBuilder
    internal func widget4AvgWinLoss(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                statHeader(
                    "Avg win / loss",
                    icon: "arrow.up.arrow.down",
                    hint: "Average winning trade ÷ average losing trade. The bar shows the two to scale."
                )
                
                Spacer(minLength: 2)
                
                Text(metrics.avgWinLossRatio.map { String(format: "%.2f", $0) } ?? "–")
                    .font(AppTypography.financialNumber(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                if let w = metrics.avgWin, let l = metrics.avgLoss, (w + l) > 0 {
                    let ratio = (w as NSDecimalNumber).doubleValue / ((w + l) as NSDecimalNumber).doubleValue
                    AppRatioBar(greenRatio: ratio)
                        .padding(.vertical, 1)
                }
                
                HStack(spacing: 2) {
                    Text(Formatters.formatCurrency(metrics.avgWin, currency: env.currentCurrency))
                        .foregroundColor(AppColors.profit)
                        .monospacedDigit()
                    Text(" win · ")
                        .foregroundColor(AppColors.secondaryText)
                    Text(Formatters.formatCurrency(metrics.avgLoss, currency: env.currentCurrency))
                        .foregroundColor(AppColors.loss)
                        .monospacedDigit()
                    Text(" loss")
                        .foregroundColor(AppColors.secondaryText)
                }
                .font(AppTypography.caption)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 5: Edge Score (Gauge)
    @ViewBuilder
    internal func widget5EdgeScore(snap: DashboardSnapshot) -> some View {
        let metrics = snap.metrics
        let edgeResult = snap.edgeResult
        cardContainer {
            VStack(spacing: 10) {
                HStack {
                    statHeader(
                        "Edge Score",
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        hint: "A 0–100 score combining win rate, profit factor, average win/loss, drawdown, recovery, and consistency. Requires at least five closed trades."
                    )
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        Text(edgeResult.score.map { "\(Int($0))" } ?? "–")
                            .font(AppTypography.financialNumber(size: 24, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(AppColors.brand)
                        Text("/100")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                if metrics.closedTrades < 5 {
                    Text("Needs 5+ closed trades. A 0–100 score combining win rate, profit factor, average win/loss, drawdown, recovery, and consistency.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                } else {
                    EdgeRadarView(components: edgeResult.components, height: 210)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation {
                            showEdgeScoreBreakdown.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showEdgeScoreBreakdown ? "Hide component breakdown" : "View component breakdown")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: showEdgeScoreBreakdown ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    .padding(.top, 2)
                    
                    if showEdgeScoreBreakdown, let b = edgeResult.breakdown {
                        Divider().background(AppColors.border.opacity(0.6))
                        
                        VStack(spacing: 5) {
                            scorePillarRow("Win rate", value: b.winRate, max: 15)
                            scorePillarRow("Profit factor", value: b.profitFactor, max: 25)
                            scorePillarRow("Avg win / loss", value: b.avgWinLoss, max: 20)
                            scorePillarRow("Drawdown", value: b.drawdown, max: 15)
                            scorePillarRow("Recovery", value: b.recovery, max: 10)
                            scorePillarRow("Consistency", value: b.consistency, max: 15)
                        }
                    }
                }
            }
        }
    }
    
    // Widget 6: Daily net cumulative P&L
    @ViewBuilder
    internal func widget6CumulativePnl(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Daily net cumulative P&L",
                    icon: "chart.line.uptrend.xyaxis",
                    hint: "Running total of net profit and loss over the selected period. The drawdown bars below show declines from the running equity peak."
                )
                
                EquityCurveChart(points: snap.chartEquityPoints, currency: env.currentCurrency, height: 180)
                
                Divider().background(AppColors.border.opacity(0.6))
                
                DrawdownChart(points: snap.chartEquityPoints, height: 75)
            }
        }
    }
    
    // Widget 7: Net daily P&L
    @ViewBuilder
    internal func widget7DailyPnl(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Net daily P&L",
                    icon: "chart.bar.xaxis",
                    hint: "Net profit or loss for each trading day. Bars above zero are profitable; bars below zero are losses."
                )
                
                DailyBarsView(
                    data: snap.days.map { DailyBarDatum(date: $0.date, netPnl: $0.netPnl) },
                    currency: env.currentCurrency,
                    isPrivate: env.isPrivacyModeEnabled,
                    height: 160
                )
            }
        }
    }
    
    // Widget 8: Calendar Mini Widget (8-column layout matching calendar-pnl.tsx)
    @ViewBuilder
    internal func widget8Calendar(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(monthName)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        env.selectedTab = .calendar
                    } label: {
                        Text("Full calendar")
                            .font(AppTypography.captionBold)
                            .underline()
                            .foregroundColor(AppColors.brand)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
                // 8-column header (Sun..Sat + Week)
                let cols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Wk"]
                HStack(spacing: 4) {
                    ForEach(cols, id: \.self) { c in
                        Text(c)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: c == "Wk" ? .trailing : .center)
                    }
                }
                
                let isoFormatter: DateFormatter = {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    return f
                }()
                
                // Calendar Weeks with Week Total Column
                VStack(spacing: 4) {
                    ForEach(0..<calendarWeeks.count, id: \.self) { wIndex in
                        let week = calendarWeeks[wIndex]
                        let weekDays = week.compactMap { $0 }
                        let weekPnl = weekDays.compactMap { d -> Decimal? in
                            let key = isoFormatter.string(from: d)
                            return snap.daysWithTradesMap[key]?.netPnl
                        }.reduce(Decimal.zero, +)
                        
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { dayIdx in
                                if let date = week[dayIdx] {
                                    let key = isoFormatter.string(from: date)
                                    let stats = snap.daysWithTradesMap[key]
                                    let dayNum = Calendar.current.component(.day, from: date)
                                    
                                    Button {
                                        openCalendarDay(dateKey: key, stats: stats)
                                    } label: {
                                        VStack(spacing: 1) {
                                            Text("\(dayNum)")
                                                .font(.system(size: 9, weight: stats != nil ? .bold : .regular))
                                                .foregroundColor(stats != nil ? AppColors.primaryText : AppColors.secondaryText)
                                            
                                            if let s = stats {
                                                Text(s.netPnl >= 0 ? "+" : "-")
                                                    .font(.system(size: 7, weight: .bold))
                                                    .foregroundColor(s.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                            }
                                        }
                                        .frame(height: 26)
                                        .frame(maxWidth: .infinity)
                                        .background(stats.map { $0.netPnl >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12) } ?? Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            stats.map { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke($0.netPnl >= 0 ? AppColors.profit.opacity(0.24) : AppColors.loss.opacity(0.24), lineWidth: 0.5) }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Color.clear
                                        .frame(height: 26)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            
                            // Week total column
                            Text(weekPnl != 0 ? Formatters.formatPnL(weekPnl, currency: env.currentCurrency) : "–")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(weekPnl > 0 ? AppColors.profit : (weekPnl < 0 ? AppColors.loss : AppColors.secondaryText))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.6))
                
                HStack {
                    Text("\(snap.currentMonthStats.tradingDays) trading days · \(snap.currentMonthStats.winningDays) green")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Text("Month: \(Formatters.formatPnL(snap.currentMonthStats.monthPnl, currency: env.currentCurrency))")
                        .font(AppTypography.captionBold)
                        .monospacedDigit()
                        .foregroundColor(snap.currentMonthStats.monthPnl >= 0 ? AppColors.profit : AppColors.loss)
                }
            }
        }
    }
    
    // Widget 9: Activity (Recent trades & Open positions)
    @ViewBuilder
    internal func widget9Activity(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ACTIVITY")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                }
                
                // Apple HIG Sliding Pill Segmented Control
                HStack(spacing: 4) {
                    ForEach(["recent", "open"], id: \.self) { tab in
                        let isSelected = activityTab == tab
                        Button {
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                activityTab = tab
                            }
                        } label: {
                            Text(tab == "recent" ? "Recent trades" : "Open positions")
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    isSelected ? AppColors.cardBackground : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 4, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(AppColors.secondaryBackground.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                if activityTab == "recent" {
                    let recent = Array(scopedTrades.filter { $0.status != .open }.prefix(5))
                    if recent.isEmpty {
                        Text("No closed trades yet")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(recent) { t in
                                HStack {
                                    AppBadge(t.status.rawValue.uppercased(), color: Formatters.statusColor(t.status))
                                    
                                    Text(t.symbol)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(AppColors.primaryText)
                                    
                                    Spacer()
                                    
                                    if let closed = t.closedAt {
                                        Text(Formatters.formatDate(closed))
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    
                                    AppMonetaryText(
                                        Formatters.formatPnL(t.netPnl, currency: env.currentCurrency),
                                        isPrivate: env.isPrivacyModeEnabled,
                                        font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                        color: t.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                    )
                                }
                                .padding(.vertical, 3)
                                
                                if t.id != recent.last?.id {
                                    Divider().background(AppColors.border.opacity(0.5))
                                }
                            }
                        }
                    }
                } else {
                    let openPos = dataStore.trades.filter { $0.status == .open }
                    if openPos.isEmpty {
                        Text("Flat -- no open positions")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(openPos) { p in
                                HStack {
                                    AppBadge(p.direction.rawValue.uppercased(), color: p.direction == .long ? AppColors.profit : AppColors.loss)
                                    
                                    Text(p.symbol)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(AppColors.primaryText)
                                    
                                    Spacer()
                                    
                                    Text("\(p.quantity) @ \(Formatters.formatCurrency(p.avgEntry, currency: env.currentCurrency))")
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .padding(.vertical, 3)
                                
                                if p.id != openPos.last?.id {
                                    Divider().background(AppColors.border.opacity(0.5))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Widget 10: Max drawdown (TrendingDown)
    @ViewBuilder
    internal func widget10MaxDrawdown(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Max drawdown",
                    icon: "chart.line.downtrend.xyaxis",
                    hint: "Largest peak-to-trough drop of the cumulative P&L curve."
                )
                
                Spacer(minLength: 4)
                
                AppMonetaryText(
                    Formatters.formatCurrency(metrics.maxDrawdown, currency: env.currentCurrency),
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 20, weight: .bold),
                    color: AppColors.loss
                )
                
                HStack(spacing: 3) {
                    Text(metrics.maxDrawdownPct.map { String(format: "-%.1f%%", $0 * 100) } ?? "set balance for %")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if let rec = metrics.recoveryFactor {
                        Text("· rec \(String(format: "%.1f", rec))x")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 11: Streaks (Flame)
    @ViewBuilder
    internal func widget11Streaks(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Streaks",
                    icon: "flame",
                    hint: "Current run of consecutive wins (W) or losses (L), with the best and worst runs."
                )
                
                Spacer(minLength: 4)
                
                Text(metrics.currentStreak > 0 ? "\(metrics.currentStreak)W" : (metrics.currentStreak < 0 ? "\(-metrics.currentStreak)L" : "–"))
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(metrics.currentStreak > 0 ? AppColors.profit : (metrics.currentStreak < 0 ? AppColors.loss : AppColors.primaryText))
                
                Text("best \(metrics.maxWinStreak)W · worst \(metrics.maxLossStreak)L")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 12: Expectancy / trade (Sigma)
    @ViewBuilder
    internal func widget12Expectancy(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Expectancy / trade",
                    icon: "sum",
                    hint: "Average net P&L per closed trade: what one more trade is worth on your numbers."
                )
                
                Spacer(minLength: 4)
                
                AppMonetaryText(
                    metrics.expectancy.map { Formatters.formatPnL($0, currency: env.currentCurrency) } ?? "–",
                    isPrivate: env.isPrivacyModeEnabled,
                    font: AppTypography.financialNumber(size: 20, weight: .bold),
                    color: (metrics.expectancy ?? 0) >= 0 ? AppColors.profit : AppColors.loss
                )
                
                Text(metrics.avgRealizedR.map { String(format: "avg %.2fR over %d trades", $0, metrics.tradesWithRisk) } ?? "tag stops for R multiples")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 13: Avg duration (Timer)
    @ViewBuilder
    internal func widget13AvgDuration(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        let metrics = snap.metrics
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Avg duration",
                    icon: "timer",
                    hint: "Average time from first entry fill to final exit."
                )
                
                Spacer(minLength: 4)
                
                Text(Formatters.formatDuration(ms: metrics.avgDurationMs))
                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.primaryText)
                
                Text("winners vs losers in Reports")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 14: Best / worst day (Trophy)
    @ViewBuilder
    internal func widget14BestWorstDay(snap: DashboardSnapshot, isCompact: Bool) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 4) {
                statHeader(
                    "Best / worst day",
                    icon: "trophy",
                    hint: "Highest and lowest single-day net P&L in the selected range."
                )
                
                Spacer(minLength: 4)
                
                if let best = snap.bestDay, let worst = snap.worstDay {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            AppMonetaryText(
                                Formatters.formatPnL(best.netPnl, currency: env.currentCurrency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                color: AppColors.profit
                            )
                            Spacer()
                            Text(String(best.date.suffix(5)))
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        HStack {
                            AppMonetaryText(
                                Formatters.formatPnL(worst.netPnl, currency: env.currentCurrency),
                                isPrivate: env.isPrivacyModeEnabled,
                                font: AppTypography.financialNumber(size: 13, weight: .semibold),
                                color: AppColors.loss
                            )
                            Spacer()
                            Text(String(worst.date.suffix(5)))
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                } else {
                    Text("No closed trades yet")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
    
    // Widget 15: Trade time performance (Clock)
    @ViewBuilder
    internal func widget15TradeTimePerformance(snap: DashboardSnapshot) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(
                    "Trade time performance",
                    icon: "clock",
                    hint: "Trades grouped by their opening hour. The upper chart shows net P&L; the lower chart shows trade count."
                )
                
                if snap.hourlyStats.isEmpty {
                    Text("No hourly trade data available.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    TimeHeatmapView(
                        hours: snap.hourlyStats,
                        currency: env.currentCurrency,
                        isPrivate: env.isPrivacyModeEnabled
                    )
                }
            }
        }
    }
    
    // MARK: - Apple HIG Reusable Card Container & Header
    
    internal func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    internal func statHeader(_ title: String, icon: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
            Spacer()
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                activeTooltip = (title: title, hint: hint)
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(AppColors.secondaryBackground.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
    
    internal func scorePillarRow(_ title: String, value: Double, max: Double) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Text(String(format: "%.1f / %.0f", value, max))
                .font(AppTypography.captionBold)
                .monospacedDigit()
                .foregroundColor(AppColors.primaryText)
        }
    }
    
    // MARK: - Day Selection Action
    
    internal func openCalendarDay(dateKey: String, stats: DayStats?) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let tradesForDay = dataStore.filteredTrades.filter {
            Formatters.isoDayString(from: $0.closedAt ?? $0.openedAt, timeZone: env.currentTimeZone) == dateKey
        }
        let note = dataStore.calendarNotes[dateKey] ?? JournalNote(date: dateKey)
        selectedDayContext = DayDetailContext(
            dateKey: dateKey,
            stats: stats,
            trades: tradesForDay,
            note: note
        )
    }
    
    internal func parseDate(from key: String) -> Date {
        Formatters.date(fromIsoDay: key, timeZone: env.currentTimeZone) ?? Date()
    }
}
