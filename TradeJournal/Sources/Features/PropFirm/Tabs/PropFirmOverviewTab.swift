import SwiftUI
import Charts

// MARK: - Prop Firm Overview Tab & HIG Card Containers
extension PropFirmLedgerView {
    // MARK: - 1. Overview Tab
    
    internal var overviewView: some View {
        VStack(spacing: 16) {
            // Renewal Reminders Banner
            let upcomingRenewals = dataStore.propAccounts.filter {
                (selectedCurrency == "ALL" || $0.currency == selectedCurrency) && !$0.archived && $0.status == .active && $0.renewalOn != nil && $0.renewalMinor != nil
            }
            if !upcomingRenewals.isEmpty {
                VStack(spacing: 8) {
                    ForEach(upcomingRenewals) { rAcc in
                        cardContainer {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(AppColors.brand)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upcoming renewal: \(rAcc.firm)")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("\(rAcc.name) • Due: \(rAcc.renewalOn ?? "") • Fee: \(Formatters.formatCurrency(Decimal(rAcc.renewalMinor ?? 0) / 100, currency: rAcc.currency))")
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            
            // Summary Hero Card
            cardContainer {
                VStack(spacing: 12) {
                    HStack {
                        Text("NET PROP CASH")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                        Spacer()
                        if let roi = summary.roi {
                            Text(String(format: "ROI %+.1f%%", roi * 100))
                                .font(AppTypography.captionBold)
                                .monospacedDigit()
                                .foregroundColor(roi >= 0 ? AppColors.profit : AppColors.loss)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(roi >= 0 ? AppColors.profit.opacity(0.12) : AppColors.loss.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        let netDecimal = Decimal(summary.netMinor) / 100
                        Text(Formatters.formatPnL(netDecimal, currency: displayCurrency))
                            .font(AppTypography.financialNumber(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(Formatters.pnlColor(netDecimal))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer()
                    }
                    
                    Divider().background(AppColors.border.opacity(0.5))
                    
                    // Spending vs Received Grid
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        GridRow {
                            subMetricBlock(
                                title: "Gross spent",
                                value: Formatters.formatCurrency(Decimal(summary.spentMinor) / 100, currency: displayCurrency),
                                color: AppColors.loss
                            )
                            subMetricBlock(
                                title: "Refunded",
                                value: Formatters.formatCurrency(Decimal(summary.refundsMinor) / 100, currency: displayCurrency),
                                color: AppColors.profit
                            )
                        }
                        GridRow {
                            subMetricBlock(
                                title: "Net spend",
                                value: Formatters.formatCurrency(Decimal(summary.netSpendMinor) / 100, currency: displayCurrency),
                                color: AppColors.primaryText
                            )
                            subMetricBlock(
                                title: "Payouts received",
                                value: Formatters.formatCurrency(Decimal(summary.receivedMinor) / 100, currency: displayCurrency),
                                color: AppColors.profit
                            )
                        }
                    }
                }
            }
            
            // Pass Rate & Account Outcomes Card
            if let pr = passRate {
                cardContainer {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Phase pass rate")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text(String(format: "%.1f%%", pr * 100))
                                .font(AppTypography.headline)
                                .monospacedDigit()
                                .foregroundColor(pr >= 0.5 ? AppColors.profit : AppColors.brand)
                        }
                        Spacer()
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.brand)
                            .frame(width: 44, height: 44)
                            .background(AppColors.brand.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
            }
            
            // Cumulative Net Cash Chart
            if !timelinePoints.isEmpty {
                cardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CUMULATIVE CASH TIMELINE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                        
                        let dateFormatter: DateFormatter = {
                            let df = DateFormatter()
                            df.dateFormat = "yyyy-MM-dd"
                            df.timeZone = TimeZone(identifier: "UTC")
                            return df
                        }()
                        let parsedTimeline = timelinePoints.compactMap { pt -> (id: String, date: Date, val: Double)? in
                            guard let d = dateFormatter.date(from: pt.date) else { return nil }
                            return (id: pt.date, date: d, val: Double(pt.netMinor) / 100.0)
                        }
                        
                        let doubleVals = parsedTimeline.map { $0.val }
                        let maxData = doubleVals.max() ?? 0.0
                        let minData = doubleVals.min() ?? 0.0
                        
                        let yDomainMax: Double = {
                            if maxData <= 0 && minData < 0 {
                                return 0.0
                            }
                            let top = max(0.0, maxData)
                            let span = max(1.0, top - min(0.0, minData))
                            return top + (span * 0.06)
                        }()
                        
                        let yDomainMin: Double = {
                            if minData >= 0 && maxData > 0 {
                                return 0.0
                            }
                            let bottom = min(0.0, minData)
                            let span = max(1.0, max(0.0, maxData) - bottom)
                            return bottom - (span * 0.06)
                        }()
                        
                        let areaFillGradient: LinearGradient = {
                            let top = yDomainMax
                            let bottom = yDomainMin
                            if bottom >= 0 {
                                return LinearGradient(
                                    colors: [AppColors.brand.opacity(0.28), AppColors.brand.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            } else if top <= 0 {
                                return LinearGradient(
                                    colors: [AppColors.loss.opacity(0.02), AppColors.loss.opacity(0.28)],
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
                        }()
                        
                        let lineStrokeGradient: LinearGradient = {
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
                        }()
                        
                        Chart {
                            RuleMark(y: .value("Zero", 0))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(AppColors.border.opacity(0.8))
                            
                            ForEach(parsedTimeline, id: \.id) { pt in
                                AreaMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", pt.val)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(areaFillGradient)
                                .alignsMarkStylesWithPlotArea()
                                
                                LineMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", pt.val)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(lineStrokeGradient)
                                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                .alignsMarkStylesWithPlotArea()
                            }
                        }
                        .chartYScale(domain: yDomainMin...yDomainMax)
                        .chartYAxis {
                            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(AppColors.border.opacity(0.3))
                                AxisValueLabel {
                                    if let d = value.as(Double.self) {
                                        Text(Formatters.compactAxisValue(d, currency: displayCurrency))
                                            .font(AppTypography.number(10, weight: .medium))
                                            .foregroundStyle(AppColors.secondaryText)
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(AppColors.border.opacity(0.3))
                                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(AppColors.border)
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        .frame(height: 180)
                    }
                }
            }
        }
    }
    
    // MARK: - Apple HIG Helper Views
    
    internal func cardContainer<Content: View>(isActive: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.5), lineWidth: isActive ? 1.0 : 0.5)
            )
            .shadow(color: isActive ? AppColors.brand.opacity(0.08) : Color.black.opacity(0.04), radius: isActive ? 10 : 8, x: 0, y: 2)
    }
    
    internal func subMetricBlock(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.5)
                .lineLimit(1)
            Text(value)
                .font(AppTypography.bodyBold)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
    
}
