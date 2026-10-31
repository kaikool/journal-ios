import SwiftUI
import Charts

// MARK: - DailyJournalDetailView Cards & Visual Sections
extension DailyJournalDetailView {
    // MARK: - Subviews
    
    internal var dayHeaderSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date)
                    .font(AppTypography.title2)
                    .foregroundColor(AppColors.primaryText)
                Text(weekdayLabel)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            
            Spacer()
            
            // Quick P&L summary badge
            VStack(alignment: .trailing, spacing: 2) {
                Text(metrics.netPnl >= 0 ? "+\(Formatters.currency(metrics.netPnl))" : Formatters.currency(metrics.netPnl))
                    .font(AppTypography.title3)
                    .foregroundColor(metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                Text("\(metrics.closedTrades) closed trade\(metrics.closedTrades == 1 ? "" : "s")")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var weekdayLabel: String {
        Self.detailIsoFormatter.timeZone = env.currentTimeZone
        guard let d = Self.detailIsoFormatter.date(from: date) else { return "" }
        return Self.detailLongDateFormatter.string(from: d)
    }
    
    internal var dayStatsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Day stats", badge: "\(metrics.closedTrades)")
                
                if metrics.closedTrades > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        // 1. Hero Net P&L with Winrate & Profit Factor status badges
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Net P&L")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                AppMonetaryText(
                                    Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled),
                                    isPrivate: env.isPrivacyModeEnabled,
                                    font: AppTypography.financialNumber(size: 24, weight: .bold),
                                    color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                if let wr = metrics.winRate {
                                    AppBadge(Formatters.percent(wr), variant: wr >= 0.5 ? .profit : .loss)
                                }
                                if metrics.profitFactorIsInfinite {
                                    AppBadge("PF ∞", variant: .profit)
                                } else if let pf = metrics.profitFactor {
                                    AppBadge(String(format: "PF %.2f", pf), variant: pf >= 1.5 ? .profit : .secondary)
                                }
                            }
                        }
                        
                        Divider().background(AppColors.border.opacity(0.35))
                        
                        // 2. Structured, balanced financial summary rows
                        VStack(spacing: 10) {
                            HStack {
                                statItem(label: "Trades", value: "\(metrics.closedTrades) (\(metrics.wins)W · \(metrics.losses)L)")
                                Spacer()
                                statItem(label: "Gross P&L", value: Formatters.currency(metrics.grossPnl ?? 0, currencyCode: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled), alignment: .trailing)
                            }
                            
                            HStack {
                                statItem(label: "Fees & Comm", value: Formatters.currency(metrics.fees ?? 0, currencyCode: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled))
                                Spacer()
                                statItem(label: "Volume", value: "\(metrics.totalVolume.formatted()) lots", alignment: .trailing)
                            }
                            
                            HStack {
                                statItem(label: "Expectancy", value: metrics.expectancy.map { Formatters.currency($0, currencyCode: env.currentCurrency, isPrivate: env.isPrivacyModeEnabled) } ?? "–")
                                Spacer()
                                statItem(label: "Profit Factor", value: metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor.map { String(format: "%.2f", $0) } ?? "–"), alignment: .trailing)
                            }
                        }
                    }
                } else {
                    Text("No closed trades this day.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func statItem(label: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(AppTypography.captionBold)
                .monospacedDigit()
                .foregroundColor(AppColors.primaryText)
        }
    }
    
    internal var intradayChartCard: some View {
        let activePoint = intradayPoints.first { $0.timeStr == selectedTime } ?? intradayPoints.last
        let isPositive = (activePoint?.cumPnl ?? metrics.netPnl) >= 0
        let chartColor = isPositive ? AppColors.brand : AppColors.loss
        
        return AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTime.map { "At \($0)" } ?? "Intraday Cumulative Net P&L")
                            .font(AppTypography.cardHeaderUppercase)
                            .foregroundColor(AppColors.secondaryText)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .lineLimit(1)
                            .frame(height: 14, alignment: .leading)
                        
                        Text(Formatters.formatPnL(activePoint?.cumPnl ?? metrics.netPnl, currency: env.currentCurrency))
                            .font(AppTypography.displayMajor)
                            .monospacedDigit()
                            .foregroundColor(chartColor)
                            .lineLimit(1)
                            .frame(height: 28, alignment: .leading)
                    }
                    .frame(height: 44, alignment: .leading)
                    
                    Spacer()
                }
                .frame(height: 46)
                
                Chart {
                    RuleMark(y: .value("Zero", 0.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(AppColors.border.opacity(0.85))
                    
                    ForEach(Array(intradayPoints.enumerated()), id: \.offset) { _, point in
                        let val = NSDecimalNumber(decimal: point.cumPnl).doubleValue
                        
                        // Single area fill anchored strictly to 0.0 baseline with locked sub-pixel gradient
                        AreaMark(
                            x: .value("Time", point.timeStr),
                            yStart: .value("Baseline", 0.0),
                            yEnd: .value("P&L", val)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(intradayAreaGradient)
                        .alignsMarkStylesWithPlotArea()
                        
                        LineMark(
                            x: .value("Time", point.timeStr),
                            y: .value("P&L", val)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(intradayLineGradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .alignsMarkStylesWithPlotArea()
                    }
                    
                    if intradayPoints.count == 1, let single = intradayPoints.first {
                        let singleVal = NSDecimalNumber(decimal: single.cumPnl).doubleValue
                        PointMark(
                            x: .value("Time", single.timeStr),
                            y: .value("P&L", singleVal)
                        )
                        .foregroundStyle(singleVal >= 0 ? AppColors.brand : AppColors.loss)
                        .symbolSize(36)
                    }
                    
                    if let time = selectedTime, let p = activePoint {
                        let activeVal = NSDecimalNumber(decimal: p.cumPnl).doubleValue
                        
                        RuleMark(x: .value("Cursor", time))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(AppColors.primaryText.opacity(0.45))
                        
                        PointMark(
                            x: .value("Time", time),
                            y: .value("P&L", activeVal)
                        )
                        .foregroundStyle(activeVal >= 0 ? AppColors.brand : AppColors.loss)
                        .symbolSize(36)
                    }
                }
                .chartXSelection(value: $selectedTime)
                .chartYScale(domain: intradayYDomainMin...intradayYDomainMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(Formatters.compactAxisValue(d, currency: env.currentCurrency))
                                    .font(AppTypography.number(10, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: strideTimeStrings) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.border.opacity(0.3))
                        AxisValueLabel {
                            if let str = value.as(String.self) {
                                Text(str)
                                    .font(AppTypography.numberMicro)
                                    .foregroundStyle(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(.horizontal, 16)
    }
    
    internal var dayTradesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppSectionHeader("Trades", badge: "\(dayTrades.count)")
                
                VStack(spacing: 8) {
                    ForEach(dayTrades) { trade in
                        HStack(spacing: 8) {
                            AppBadge(
                                trade.status.rawValue.uppercased(),
                                variant: trade.netPnl > 0 ? .profit : (trade.netPnl < 0 ? .loss : .secondary)
                            )
                            
                            Text(trade.symbol)
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            
                            AppBadge(
                                trade.direction.rawValue.uppercased(),
                                variant: trade.direction == .long ? .brand : .warning
                            )
                            
                            Spacer(minLength: 4)
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(trade.netPnl >= 0 ? "+" + Formatters.currency(trade.netPnl) : Formatters.currency(trade.netPnl))
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                    .lineLimit(1)
                                
                                Text("\(Formatters.formatNumber(trade.quantity)) lots @ \(Formatters.price(trade.avgEntry))")
                                    .font(AppTypography.captionMicro)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(AppTypography.captionMicro)
                                .foregroundColor(AppColors.secondaryText.opacity(0.4))
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTradeForDetail = trade
                        }
                        
                        if trade.id != dayTrades.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    internal var dayNoteCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    AppSectionHeader(
                        "Day note",
                        actionTitle: "AI Recap",
                        actionIcon: "sparkles",
                        onAction: {
                            guard !isGeneratingAiRecap && !dayTrades.isEmpty else { return }
                            generateAiRecap()
                        }
                    )
                }
                
                if let err = aiErrorMessage {
                    Text(err)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.loss)
                }
                
                Text("Notes are saved locally and synced automatically. Write your reflections, market observations, or generate an AI recap.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // Rich Note Editor with Office-style formatting and AI-style Markdown preview
                RichNoteEditor(
                    text: $noteText,
                    placeholder: "Write your review for \(date)...",
                    minHeight: 130,
                    allowPreviewToggle: true,
                    onSave: {
                        scheduleSaveNote(noteText)
                    }
                )
                
                HStack(spacing: 12) {
                    if !saveStatusMessage.isEmpty {
                        Text(saveStatusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if !noteText.isEmpty {
                        AppSecondaryButton("Clear", height: 28) {
                            noteText = ""
                            dataStore.deleteCalendarNote(for: date)
                            saveStatusMessage = "Cleared"
                        }
                    }
                    
                    AppPrimaryButton("Save now", icon: "checkmark", height: 28) {
                        saveNoteImmediately(force: true)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
}
