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
                Text("Day stats")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                if metrics.closedTrades > 0 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        statItem(label: "Net P&L", value: metrics.netPnl >= 0 ? "+\(Formatters.currency(metrics.netPnl))" : Formatters.currency(metrics.netPnl), color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                        statItem(label: "Trades", value: "\(metrics.closedTrades)")
                        statItem(label: "Winrate", value: Formatters.percent(metrics.winRate))
                        
                        statItem(label: "Winners", value: "\(metrics.wins)", color: AppColors.profit)
                        statItem(label: "Losers", value: "\(metrics.losses)", color: AppColors.loss)
                        statItem(label: "Gross", value: Formatters.currency(metrics.grossPnl ?? 0))
                        
                        statItem(label: "Fees", value: Formatters.currency(metrics.fees ?? 0))
                        statItem(label: "Volume", value: "\(metrics.totalVolume.formatted())")
                        statItem(label: "Profit Factor", value: metrics.profitFactorIsInfinite ? "∞" : (metrics.profitFactor.map { String(format: "%.2f", $0) } ?? "–"))
                        
                        statItem(label: "Expectancy", value: metrics.expectancy.map { Formatters.currency($0) } ?? "–")
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
    private func statItem(label: String, value: String, color: Color = AppColors.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .lineLimit(1)
                            .frame(height: 14, alignment: .leading)
                        
                        Text(Formatters.formatPnL(activePoint?.cumPnl ?? metrics.netPnl, currency: env.currentCurrency))
                            .font(.system(size: 22, weight: .bold))
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
                                    .font(.system(size: 9, weight: .medium))
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
                HStack {
                    Text("Trades (\(dayTrades.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    ForEach(dayTrades) { trade in
                        Button {
                            selectedTradeForDetail = trade
                        } label: {
                            HStack(spacing: 8) {
                                // Status badge WIN / LOSS / BE
                                Text(trade.status.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        trade.netPnl > 0 ? AppColors.profit.opacity(0.15) :
                                        (trade.netPnl < 0 ? AppColors.loss.opacity(0.15) : AppColors.secondaryBackground)
                                    )
                                    .foregroundColor(
                                        trade.netPnl > 0 ? AppColors.profit :
                                        (trade.netPnl < 0 ? AppColors.loss : AppColors.secondaryText)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .lineLimit(1)
                                
                                Text(trade.symbol)
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                                
                                Text(trade.direction.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(trade.direction == .long ? AppColors.brand : AppColors.warning)
                                    .lineLimit(1)
                                
                                Spacer(minLength: 4)
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(trade.netPnl >= 0 ? "+\(Formatters.currency(trade.netPnl))" : Formatters.currency(trade.netPnl))
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(trade.netPnl >= 0 ? AppColors.profit : AppColors.loss)
                                        .lineLimit(1)
                                    
                                    Text("\(Formatters.formatNumber(trade.quantity)) lots @ \(Formatters.price(trade.avgEntry))")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                        
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
                HStack {
                    Text("Day note")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    if !noteText.isEmpty {
                        Button {
                            showDeleteNoteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.loss.opacity(0.75))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // AI Recap button
                    Button {
                        generateAiRecap()
                    } label: {
                        HStack(spacing: 4) {
                            if isGeneratingAiRecap {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("AI Recap")
                        }
                        .font(AppTypography.captionBold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.accent.opacity(0.12))
                        .foregroundColor(AppColors.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(isGeneratingAiRecap || dayTrades.isEmpty)
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
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    if !noteText.isEmpty {
                        Button("Clear") {
                            noteText = ""
                            dataStore.deleteCalendarNote(for: date)
                            saveStatusMessage = "Cleared"
                        }
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Button("Save now") {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        saveNoteImmediately(force: true)
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.accent)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
}
