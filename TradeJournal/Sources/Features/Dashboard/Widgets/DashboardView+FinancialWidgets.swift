import SwiftUI

// MARK: - Dashboard Financial Widgets (0: Net PnL, 1: Win Rate, 2: Profit Factor, 3: Day Win, 4: Avg Win/Loss)
extension DashboardView {
    
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
                                .lineLimit(1)
                            Text("vs 7d")
                                .font(AppTypography.caption)
                                .lineLimit(1)
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(delta >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                        .foregroundColor(delta >= 0 ? AppColors.profit : AppColors.loss)
                        .clipShape(Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    HStack(spacing: 4) {
                        Text("\(metrics.closedTrades) closed")
                        Text("·")
                        Text("Fees \(Formatters.formatCurrency(metrics.fees ?? 0, currency: env.currentCurrency))")
                    }
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        AppMonetaryText(
                            Formatters.formatPnL(metrics.netPnl, currency: env.currentCurrency),
                            isPrivate: env.isPrivacyModeEnabled,
                            font: AppTypography.financialNumber(size: 28, weight: .bold),
                            color: metrics.netPnl >= 0 ? AppColors.profit : AppColors.loss
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        
                        Spacer(minLength: 6)
                        
                        if let delta = snap.weekDelta {
                            HStack(spacing: 3) {
                                Text(delta >= 0 ? "▲" : "▼")
                                    .font(.system(size: 9, weight: .bold))
                                Text(Formatters.formatCurrency(abs(delta), currency: env.currentCurrency))
                                    .font(AppTypography.captionBold)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text("vs 7d")
                                    .font(AppTypography.caption)
                                    .lineLimit(1)
                            }
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(delta >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                            .foregroundColor(delta >= 0 ? AppColors.profit : AppColors.loss)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
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
                .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 98 : nil, alignment: .topLeading)
        }
    }
}
