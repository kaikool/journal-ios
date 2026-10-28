import SwiftUI

// MARK: - Dashboard PnL Curves & Distribution Widgets (6: Cumulative PnL, 7: Daily PnL, 14: Best/Worst Day)
extension DashboardView {
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
}
