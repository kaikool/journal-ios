import SwiftUI

// MARK: - Dashboard Risk & Performance Widgets (5: Edge Score, 10: Max Drawdown, 12: Expectancy)
extension DashboardView {
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
    
}
