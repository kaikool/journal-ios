import SwiftUI
import Charts

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
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(areaFillGradient)
                                .alignsMarkStylesWithPlotArea()
                                
                                LineMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", pt.val)
                                )
                                .interpolationMethod(.stepEnd)
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
                                        Text(Formatters.formatCurrency(Decimal(d), currency: displayCurrency))
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .monospacedDigit()
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
    
    // MARK: - 2. Accounts Tab
    
    internal func accountCashSummary(account: PropAccountItem) -> CashSummaryResult {
        let accClean = account.id.cleanAccountId
        let accCurr = account.currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let accMovements = movements.filter { mov in
            let movCurr = mov.currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard movCurr == accCurr || (movCurr.isEmpty && (accCurr == "USD" || accCurr.isEmpty)) else { return false }
            
            if let mAccId = mov.accountId, !mAccId.isEmpty {
                return mAccId == account.id ||
                       mAccId == account.journalAccountId ||
                       TradeDataStore.isSameAccountId(mAccId, account.id) ||
                       (account.journalAccountId.map { TradeDataStore.isSameAccountId(mAccId, $0) } ?? false) ||
                       mAccId.cleanAccountId == accClean
            }
            return false
        }
        return (try? PropFirmEngine.cashSummary(rows: accMovements)) ?? CashSummaryResult(
            spentMinor: 0, refundsMinor: 0, netSpendMinor: 0, receivedMinor: 0, netMinor: 0, roi: nil
        )
    }
    
    internal var accountsListView: some View {
        VStack(spacing: 12) {
            if filteredAccounts.isEmpty {
                EmptyStateView(
                    icon: "building.columns",
                    title: selectedAccountStatus == .all ? "No prop accounts" : "No \(selectedAccountStatus.rawValue.lowercased()) prop accounts",
                    message: "Tap 'Track account' above to add your Topstep, FTMO, The5ers accounts."
                )
            } else {
                ForEach(filteredAccounts) { acc in
                    cardContainer(isActive: acc.status == .active) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "building.columns")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text(acc.firm)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                }
                                
                                if acc.archived {
                                    Text("Archived")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(Capsule())
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                AppBadge(
                                    text: acc.status.label,
                                    color: acc.status == .active || acc.status == .passed ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Text(Formatters.cleanAccountName(acc.name, balance: acc.sizeMinor.map { Decimal($0) / 100 }))
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if let parentId = acc.parentId, let parentAcc = dataStore.propAccounts.first(where: { $0.id == parentId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.brand)
                                    Text("Next phase of: \(Formatters.cleanAccountName(parentAcc.name))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppColors.brand)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            
                            HStack {
                                if let size = acc.sizeMinor {
                                    Text("Initial Size: \(Formatters.formatCurrency(Decimal(size) / 100, currency: acc.currency))")
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(acc.currentStepName ?? acc.program.label)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            // 3-Column Account Balance, Equity & Net P&L (Authoritative MCP Account State)
                            let balMinor = acc.balanceMinor ?? acc.sizeMinor ?? 0
                            let eqMinor = acc.equityMinor ?? balMinor
                            let pnlMinor: Int64 = {
                                if let np = acc.netPnlMinor { return np }
                                if let b = acc.balanceMinor, let s = acc.sizeMinor, s > 0 { return b - s }
                                return 0
                            }()
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Balance")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(balMinor) / 100, currency: acc.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Equity")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(eqMinor) / 100, currency: acc.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Net P&L")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    let isNetPos = pnlMinor >= 0
                                    Text("\(isNetPos ? "+" : "")\(Formatters.formatCurrency(Decimal(pnlMinor) / 100, currency: acc.currency))")
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(pnlMinor == 0 ? AppColors.primaryText : (isNetPos ? AppColors.profit : AppColors.loss))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(AppColors.secondaryBackground.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            // Program Rules, Stop Loss & Progression (Visual Objective Charts & Risk Shields)
                            let hasProgramDetails = acc.profitTargetMinor != nil || acc.maxLossMinor != nil || acc.maxDailyLossMinor != nil || acc.winningDays != nil || acc.minTradingDays != nil || acc.currentStepName != nil || acc.totalTrades != nil
                            if acc.status == .active || hasProgramDetails {
                                PropAccountObjectivesChartCard(acc: acc)
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            // 2-row footer layout: prevents button text wrapping on small screens
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("Opened: \(acc.openedOn)")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    if let closed = acc.closedOn {
                                        Text("• Closed: \(closed)")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                
                                HStack(spacing: 8) {
                                    Spacer()
                                    
                                    if acc.status == .passed || acc.status == .breached || acc.status == .closed {
                                        Button {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            selectedAccountForNextPhase = acc
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.right.circle")
                                                Text("Next phase")
                                            }
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(AppColors.brand.opacity(0.12))
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                        }
                                        .buttonStyle(ApplePressableButtonStyle())
                                    }
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        selectedAccountForEdit = acc
                                    } label: {
                                        Text("Edit")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(AppColors.secondaryBackground)
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                        }
                                    .buttonStyle(ApplePressableButtonStyle())
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        dataStore.archivePropAccount(id: acc.id, archived: !acc.archived, reason: "User toggle archive")
                                    } label: {
                                        Text(acc.archived ? "Restore" : "Archive")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(AppColors.secondaryText)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(AppColors.secondaryBackground)
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Payouts Tab
    
    internal var payoutsProgressView: some View {
        VStack(spacing: 12) {
            if payoutItems.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "No payout requests",
                    message: "Track approval status, receipts and transfer fee variance for each prop firm payout."
                )
            } else {
                ForEach(payoutItems) { p in
                    cardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "banknote")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text("\(p.entry.firm) Payout")
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                Spacer()
                                if p.isOverdue {
                                    AppBadge(text: "Overdue", color: AppColors.loss)
                                } else if p.isPartial {
                                    AppBadge(text: "Partially received", color: AppColors.brand)
                                }
                                AppBadge(
                                    text: p.entry.status.label,
                                    color: p.entry.status == .completed ? AppColors.profit : AppColors.brand
                                )
                            }
                            
                            // Subtitle matching web prop-firm-tracker.tsx:980
                            Text("Requested \(p.entry.occurredOn) • Trader split \(p.entry.splitBps / 100)% • Gross \(Formatters.formatCurrency(Decimal(p.entry.amountMinor) / 100, currency: p.entry.currency))\(p.entry.dueOn.map { " • Expected \($0)" } ?? "")")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            // Primary Headline Amount (Received if receipts exist, or Expected Net)
                            let hasReceipt = p.actualMinor > 0
                            HStack(alignment: .firstTextBaseline) {
                                Text(hasReceipt ? "Received:" : "Expected net:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Text(Formatters.formatCurrency(Decimal(hasReceipt ? p.actualMinor : p.expectedMinor) / 100, currency: p.entry.currency))
                                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                                    .foregroundColor(hasReceipt ? AppColors.profit : AppColors.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer()
                                if hasReceipt && p.remainingMinor > 0 {
                                    Text("Remaining \(Formatters.formatCurrency(Decimal(p.remainingMinor) / 100, currency: p.entry.currency))")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.loss)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            
                            // 4-Column Metric Details matching web prop-firm-tracker.tsx:1024-1041
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gross profit")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(p.entry.amountMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Trader split")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text("\(p.entry.splitBps / 100)%")
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Expected net")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(p.expectedMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Actual received")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(p.actualMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.profit)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(AppColors.secondaryBackground.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            if p.varianceMinor != 0 && p.entry.status == .completed {
                                HStack {
                                    Text("Settlement variance:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(Formatters.formatCurrency(Decimal(p.varianceMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(p.varianceMinor >= 0 ? AppColors.profit : AppColors.loss)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack {
                                Text("Requested: \(p.entry.occurredOn)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    selectedPayoutForReceipt = p.entry
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                        Text("Record receipt")
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(AppColors.brand)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.brand.opacity(0.12))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                                    .fixedSize()
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 4. Transactions Tab
    
    internal var transactionsListView: some View {
        VStack(spacing: 12) {
            if movements.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right",
                    title: "No cash movements",
                    message: "Evaluation fees, refunds, and payout receipts will appear here."
                )
            } else {
                ForEach(movements) { m in
                    cardContainer {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(m.firm)
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    let badgeLabel: String = {
                                        if m.kind == "refund" { return "Fee Refund" }
                                        if m.kind == "receipt" || m.kind == "payout" { return "Payout" }
                                        switch m.category.lowercased() {
                                        case "evaluation", "program": return "Evaluation Fee"
                                        case "reset": return "Reset Fee"
                                        case "activation": return "Activation Fee"
                                        case "subscription": return "Subscription"
                                        default: return "Evaluation Fee"
                                        }
                                    }()
                                    let badgeColor: Color = {
                                        if m.kind == "refund" { return AppColors.brand }
                                        if m.kind == "receipt" || m.kind == "payout" { return AppColors.profit }
                                        switch m.category.lowercased() {
                                        case "evaluation", "program", "activation": return AppColors.brand
                                        case "reset": return AppColors.warning
                                        default: return AppColors.secondaryText
                                        }
                                    }()
                                    AppBadge(text: badgeLabel, color: badgeColor)
                                }
                                
                                if m.kind == "refund" {
                                    Text("Refund of evaluation fee from prop firm")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                } else if let entry = dataStore.propEntries.first(where: { $0.id == m.entryId }), !entry.notes.isEmpty {
                                    let cleanNote = Formatters.cleanTransactionNote(entry.notes.components(separatedBy: "\n").first ?? entry.notes)
                                    if !cleanNote.isEmpty {
                                        Text(cleanNote)
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.primaryText)
                                            .lineLimit(1)
                                    }
                                }
                                
                                HStack(spacing: 6) {
                                    Text(Formatters.formatDisplayDate(m.date))
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    
                                    if !m.reference.isEmpty {
                                        Text("•")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText.opacity(0.5))
                                        Text(Formatters.formatReference(m.reference))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 6) {
                                let isIncoming = m.kind == "receipt" || m.kind == "refund"
                                let amountDecimal = Decimal(m.amountMinor) / 100
                                Text("\(isIncoming ? "+" : "-")\(Formatters.formatCurrency(amountDecimal, currency: m.currency))")
                                    .font(AppTypography.subheadlineBold)
                                    .monospacedDigit()
                                    .foregroundColor(isIncoming ? AppColors.profit : AppColors.loss)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                HStack(spacing: 8) {
                                    if m.kind == "expense" {
                                        Button {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            if let entry = dataStore.propEntries.first(where: { $0.id == m.entryId }) {
                                                selectedExpenseForRefund = entry
                                            }
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "arrow.counterclockwise")
                                                    .font(.system(size: 10))
                                                Text("Fee refund")
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(AppColors.brand.opacity(0.12))
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                        }
                                        .buttonStyle(ApplePressableButtonStyle())
                                    }
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        itemToVoid = (id: m.entryId, isEntry: true)
                                        showVoidAlert = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.loss.opacity(0.8))
                                            .padding(6)
                                            .background(AppColors.secondaryBackground)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Active Prop Account Visual Objectives & Risk Charts

internal struct PropAccountObjectivesChartCard: View {
    let acc: PropAccountItem
    
    private var balMinor: Int64 { acc.balanceMinor ?? acc.sizeMinor ?? 0 }
    private var eqMinor: Int64 { acc.equityMinor ?? balMinor }
    private var sizeMinor: Int64 { acc.sizeMinor ?? 0 }
    private var netPnlMinor: Int64 {
        if let np = acc.netPnlMinor { return np }
        if sizeMinor > 0 { return balMinor - sizeMinor }
        return 0
    }
    
    private var maxDrawdownUsedMinor: Int64 {
        if sizeMinor > 0 {
            return max(0, sizeMinor - eqMinor)
        }
        return netPnlMinor < 0 ? abs(netPnlMinor) : 0
    }
    
    private var maxLossMinor: Int64 { acc.maxLossMinor ?? 0 }
    private var dailyLossMinor: Int64 { acc.maxDailyLossMinor ?? 0 }
    private var targetMinor: Int64 { acc.profitTargetMinor ?? 0 }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Step Name + subtle milestone info
            HStack {
                Text(acc.currentStepName ?? "Program Objectives")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                if let winDays = acc.winningDays {
                    let minDays = acc.minTradingDays ?? 3
                    Text("Winning Days: \(winDays)/\(minDays)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(winDays >= minDays ? AppColors.profit : AppColors.secondaryText)
                }
            }
            
            // 3-Column Objective Metrics
            HStack(alignment: .top, spacing: 8) {
                // 1. Profit Target
                if targetMinor > 0 {
                    let targetDec = Decimal(targetMinor) / 100
                    let pnlDec = Decimal(netPnlMinor) / 100
                    let isProfit = netPnlMinor > 0
                    let progressRatio = isProfit ? min(1.0, Double(netPnlMinor) / Double(targetMinor)) : 0.0
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TARGET")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        
                        Text("+\(Formatters.formatCurrency(targetDec, currency: acc.currency))")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                        
                        // Thin 3pt progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppColors.secondaryBackground)
                                    .frame(height: 3)
                                if progressRatio > 0 {
                                    Capsule()
                                        .fill(AppColors.profit)
                                        .frame(width: max(3, geo.size.width * CGFloat(progressRatio)), height: 3)
                                }
                            }
                        }
                        .frame(height: 3)
                        
                        Text(isProfit ? "+\(Formatters.formatCurrency(pnlDec, currency: acc.currency)) (\(Int(progressRatio * 100))%)" : "$0.00 (0%)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(isProfit ? AppColors.profit : AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 2. Daily Loss Limit
                if dailyLossMinor > 0 {
                    let dailyLimitDec = Decimal(dailyLossMinor) / 100
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DAILY LOSS")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        
                        Text("-\(Formatters.formatCurrency(dailyLimitDec, currency: acc.currency))")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                        
                        // Thin 3pt bar
                        Capsule()
                            .fill(AppColors.brand.opacity(0.6))
                            .frame(height: 3)
                        
                        Text("\(Formatters.formatCurrency(dailyLimitDec, currency: acc.currency)) left")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 3. Max Drawdown Limit
                if maxLossMinor > 0 {
                    let maxLossDec = Decimal(maxLossMinor) / 100
                    let usedDec = Decimal(maxDrawdownUsedMinor) / 100
                    let remainingDec = max(Decimal.zero, maxLossDec - usedDec)
                    let usedRatio = min(1.0, Double(maxDrawdownUsedMinor) / Double(maxLossMinor))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MAX LOSS")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                        
                        Text("-\(Formatters.formatCurrency(maxLossDec, currency: acc.currency))")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.primaryText)
                        
                        // Thin 3pt bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppColors.secondaryBackground)
                                    .frame(height: 3)
                                if usedRatio > 0 {
                                    Capsule()
                                        .fill(usedRatio > 0.7 ? AppColors.loss : AppColors.brand)
                                        .frame(width: max(3, geo.size.width * CGFloat(usedRatio)), height: 3)
                                }
                            }
                        }
                        .frame(height: 3)
                        
                        Text("\(Formatters.formatCurrency(remainingDec, currency: acc.currency)) left")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColors.secondaryBackground.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
