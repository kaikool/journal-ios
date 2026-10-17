import SwiftUI
import Charts

public enum PropLedgerTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case accounts = "Accounts"
    case payouts = "Payouts"
    case transactions = "Transactions"
    case activity = "Activity"
    
    public var id: String { rawValue }
}

public struct PropFirmLedgerView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var env = AppEnvironment.shared
    
    @State private var selectedTab: PropLedgerTab = .overview
    @State private var selectedCurrency: String = "USD"
    @State private var showArchivedAccounts: Bool = false
    
    @State private var showNewAccountSheet: Bool = false
    @State private var showNewEntrySheet: Bool = false
    @State private var showAddReceiptSheet: Bool = false
    @State private var showRefundSheet: Bool = false
    @State private var showVoidAlert: Bool = false
    @State private var showCsvSheet: Bool = false
    @State private var showAuditSheet: Bool = false
    
    @State private var selectedPayoutForReceipt: PropEntryItem? = nil
    @State private var selectedExpenseForRefund: PropEntryItem? = nil
    @State private var selectedAccountForEdit: PropAccountItem? = nil
    @State private var selectedAccountForNextPhase: PropAccountItem? = nil
    @State private var itemToVoid: (id: String, isEntry: Bool)? = nil
    @State private var voidReason: String = ""
    
    public init() {}
    
    private var availableCurrencies: [String] {
        let set = Set(dataStore.propAccounts.map { $0.currency } + dataStore.propEntries.map { $0.currency })
        return set.isEmpty ? ["USD"] : Array(set).sorted()
    }
    
    private var filteredAccounts: [PropAccountItem] {
        dataStore.propAccounts.filter {
            (showArchivedAccounts || !$0.archived) && ($0.currency == selectedCurrency)
        }
    }
    
    private var filteredEntries: [PropEntryItem] {
        dataStore.propEntries.filter { $0.currency == selectedCurrency }
    }
    
    private var movements: [CashMovementItem] {
        PropFirmEngine.cashMovements(entries: filteredEntries, receipts: dataStore.propReceipts)
            .filter { $0.currency == selectedCurrency }
    }
    
    private var summary: CashSummaryResult {
        (try? PropFirmEngine.cashSummary(rows: movements)) ?? CashSummaryResult(
            spentMinor: 0, refundsMinor: 0, netSpendMinor: 0, receivedMinor: 0, netMinor: 0, roi: nil
        )
    }
    
    private var timelinePoints: [CashTimelinePoint] {
        (try? PropFirmEngine.cashTimeline(rows: movements)) ?? []
    }
    
    private var payoutItems: [PayoutProgressResult] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return PropFirmEngine.payoutProgress(
            entries: filteredEntries,
            receipts: dataStore.propReceipts,
            today: today
        )
    }
    
    private var passRate: Double? {
        PropFirmEngine.resolvedPhasePassRate(accounts: dataStore.propAccounts.filter { $0.currency == selectedCurrency })
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // FilterBar matching web
                FilterBarView(
                    title: "Prop firms",
                    showFilters: false
                ) {
                    Menu {
                        Button {
                            showNewAccountSheet = true
                        } label: {
                            Label("Track Account", systemImage: "briefcase.fill")
                        }
                        Button {
                            showNewEntrySheet = true
                        } label: {
                            Label("Add Expense", systemImage: "arrow.up.right")
                        }
                        Button {
                            showAddReceiptSheet = true
                        } label: {
                            Label("Track Payout", systemImage: "arrow.down.left")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("New")
                                .font(AppTypography.actionPill)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: 32)
                        .background(AppColors.brand)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: AppColors.brand.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
                
            // Universal Apple HIG Sliding Segmented Bar
            AppleSlidingSegmentedBar(
                selection: $selectedTab,
                items: PropLedgerTab.allCases,
                titleFor: { $0.rawValue }
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            
            // Sub-Toolbar: Currency Pill & Archived Toggle
            HStack {
                AppleMenuChip(title: "Currency", selectionText: selectedCurrency, icon: "dollarsign.circle") {
                    ForEach(availableCurrencies, id: \.self) { c in
                        Button(c) {
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            selectedCurrency = c
                        }
                    }
                }
                
                Spacer()
                
                if selectedTab == .accounts {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        showArchivedAccounts.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showArchivedAccounts ? "archivebox.fill" : "archivebox")
                                .font(.system(size: 11))
                            Text("Archived")
                                .font(.system(size: 12, weight: showArchivedAccounts ? .semibold : .medium))
                        }
                        .foregroundColor(showArchivedAccounts ? AppColors.brand : AppColors.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(showArchivedAccounts ? AppColors.brand.opacity(0.12) : AppColors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(showArchivedAccounts ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.6), lineWidth: 0.5))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 2)
            
            // Content Switcher
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .overview:
                            overviewView
                        case .accounts:
                            accountsListView
                        case .payouts:
                            payoutsProgressView
                        case .transactions:
                            transactionsListView
                        case .activity:
                            activityAuditView
                        }
                    }
                    .padding(14)
                }
            }
            .background(AppColors.background)
        .sheet(isPresented: $showNewAccountSheet) {
            NewPropAccountSheet(defaultCurrency: selectedCurrency) { newAcc in
                dataStore.savePropAccount(item: newAcc, reason: "Create new account")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $selectedAccountForNextPhase) { parentAcc in
            NewPropAccountSheet(
                defaultCurrency: parentAcc.currency,
                initialFirm: parentAcc.firm,
                initialProgram: parentAcc.program == .evaluation ? .verification : .funded,
                initialSizeText: "\(parentAcc.sizeMinor.map { $0 / 100 } ?? 50000)",
                parentId: parentAcc.id
            ) { nextAcc in
                dataStore.savePropAccount(item: nextAcc, reason: "Next stage / phase")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $selectedAccountForEdit) { acc in
            EditPropAccountSheet(account: acc) { updatedAcc in
                dataStore.savePropAccount(item: updatedAcc, reason: "Update account details")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showAuditSheet) {
            PropAuditTrailSheet(audits: dataStore.propAudits)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showNewEntrySheet) {
            NewPropEntrySheet(accounts: filteredAccounts, defaultCurrency: selectedCurrency) { newEntry in
                dataStore.savePropEntry(item: newEntry, reason: "Record transaction")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $selectedPayoutForReceipt) { payout in
            AddReceiptSheet(payout: payout) { receipt in
                try? dataStore.addPropReceipt(item: receipt, reason: "Payout receipt settlement")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $selectedExpenseForRefund) { expense in
            AddRefundSheet(expense: expense) { refundEntry in
                dataStore.savePropEntry(item: refundEntry, reason: "Evaluation fee refund")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showCsvSheet) {
            PropCsvImportSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
            .alert("Void transaction", isPresented: $showVoidAlert) {
                TextField("Void reason (required)...", text: $voidReason)
                Button("Cancel", role: .cancel) { itemToVoid = nil; voidReason = "" }
                Button("Confirm void", role: .destructive) {
                    if let target = itemToVoid {
                        if target.isEntry {
                            try? dataStore.voidPropEntry(id: target.id, voided: true, reason: voidReason.isEmpty ? "Void transaction" : voidReason)
                        }
                        itemToVoid = nil
                        voidReason = ""
                    }
                }
            } message: {
                Text("The transaction will be voided and excluded from cash flow totals, but preserved for audit history.")
            }
    }
    
    // MARK: - 1. Overview Tab
    
    private var overviewView: some View {
        VStack(spacing: 16) {
            // Renewal Reminders Banner
            let upcomingRenewals = dataStore.propAccounts.filter {
                $0.currency == selectedCurrency && !$0.archived && $0.status == .active && $0.renewalOn != nil && $0.renewalMinor != nil
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
                        Text("Net Prop Cash")
                            .font(AppTypography.cardTitle)
                            .foregroundColor(AppColors.primaryText)
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
                        Text(Formatters.formatPnL(netDecimal, currency: selectedCurrency))
                            .font(AppTypography.financialNumber(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(Formatters.pnlColor(netDecimal))
                        Spacer()
                    }
                    
                    Divider().background(AppColors.border.opacity(0.5))
                    
                    // Spending vs Received Grid
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        GridRow {
                            subMetricBlock(
                                title: "Gross spent",
                                value: Formatters.formatCurrency(Decimal(summary.spentMinor) / 100, currency: selectedCurrency),
                                color: AppColors.loss
                            )
                            subMetricBlock(
                                title: "Refunded",
                                value: Formatters.formatCurrency(Decimal(summary.refundsMinor) / 100, currency: selectedCurrency),
                                color: AppColors.profit
                            )
                        }
                        GridRow {
                            subMetricBlock(
                                title: "Net spend",
                                value: Formatters.formatCurrency(Decimal(summary.netSpendMinor) / 100, currency: selectedCurrency),
                                color: AppColors.primaryText
                            )
                            subMetricBlock(
                                title: "Payouts received",
                                value: Formatters.formatCurrency(Decimal(summary.receivedMinor) / 100, currency: selectedCurrency),
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
                        Text("Cumulative cash timeline")
                            .font(AppTypography.cardTitle)
                            .foregroundColor(AppColors.primaryText)
                        
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
                        
                        Chart {
                            RuleMark(y: .value("Zero", 0))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(AppColors.border.opacity(0.8))
                            
                            ForEach(parsedTimeline, id: \.id) { pt in
                                AreaMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", pt.val)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        stops: [
                                            .init(color: AppColors.brand.opacity(0.3), location: 0.0),
                                            .init(color: AppColors.brand.opacity(0.06), location: 0.6),
                                            .init(color: Color.clear, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                
                                LineMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", pt.val)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(AppColors.brand)
                                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(AppColors.border.opacity(0.3))
                                AxisValueLabel {
                                    if let d = value.as(Double.self) {
                                        Text(Formatters.formatCurrency(Decimal(d), currency: "USD"))
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(AppColors.secondaryText)
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { value in
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
    
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    private func subMetricBlock(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(AppTypography.bodyBold)
                .monospacedDigit()
                .foregroundColor(color)
        }
    }
    
    // MARK: - 2. Accounts Tab
    
    private var accountsListView: some View {
        VStack(spacing: 12) {
            if filteredAccounts.isEmpty {
                EmptyStateView(
                    icon: "building.columns",
                    title: "No prop accounts in \(selectedCurrency)",
                    message: "Tap 'Track account' above to add your Topstep, FTMO, The5ers accounts."
                )
            } else {
                ForEach(filteredAccounts) { acc in
                    cardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "building.columns")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text(acc.firm)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                }
                                
                                if acc.archived {
                                    Text("Archived")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                                
                                AppBadge(
                                    text: acc.status.label,
                                    color: acc.status == .active || acc.status == .passed ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Text(acc.name)
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            
                            if let parentId = acc.parentId, let parentAcc = dataStore.propAccounts.first(where: { $0.id == parentId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.brand)
                                    Text("Next phase of: \(parentAcc.name)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppColors.brand)
                                }
                            }
                            
                            HStack {
                                if let size = acc.sizeMinor {
                                    Text("Size: \(Formatters.formatCurrency(Decimal(size) / 100, currency: acc.currency))")
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                                Text(acc.program.label)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack(spacing: 12) {
                                Text("Opened: \(acc.openedOn)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                if let closed = acc.closedOn {
                                    Text("• Closed: \(closed)")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText)
                                }
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
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.brand)
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
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.brand)
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                                
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    dataStore.archivePropAccount(id: acc.id, archived: !acc.archived, reason: "User toggle archive")
                                } label: {
                                    Text(acc.archived ? "Restore" : "Archive")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .buttonStyle(ApplePressableButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Payouts Tab
    
    private var payoutsProgressView: some View {
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
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Expected payout (after split):")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(p.expectedMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Actually received:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(p.actualMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.profit)
                                }
                            }
                            
                            if p.remainingMinor > 0 {
                                HStack {
                                    Text("Remaining payout:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text(Formatters.formatCurrency(Decimal(p.remainingMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.loss)
                                }
                            }
                            
                            if p.varianceMinor != 0 && p.entry.status == .completed {
                                HStack {
                                    Text("Settlement variance:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Spacer()
                                    Text(Formatters.formatCurrency(Decimal(p.varianceMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(p.varianceMinor >= 0 ? AppColors.profit : AppColors.loss)
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack {
                                Text("Requested: \(p.entry.occurredOn)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
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
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.brand)
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
    
    private var transactionsListView: some View {
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
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(m.firm)
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                    AppBadge(
                                        text: m.category.capitalized,
                                        color: m.kind == "payout" || m.kind == "receipt" ? AppColors.profit : AppColors.secondaryText
                                    )
                                }
                                Text(m.date ?? "Pending settlement")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                if !m.reference.isEmpty {
                                    Text("Ref: \(m.reference)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
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
                                
                                HStack(spacing: 12) {
                                    if m.kind == "expense" {
                                        Button {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            if let entry = dataStore.propEntries.first(where: { $0.id == m.entryId }) {
                                                selectedExpenseForRefund = entry
                                            }
                                        } label: {
                                            Text("Refund")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(AppColors.brand)
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
    
    // MARK: - Activity / Audit Trail View
    private var activityAuditView: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.brand)
                        Text("Activity & Audit Trail")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                    }
                    Spacer()
                    Text("\(dataStore.propAudits.count) events")
                        .font(AppTypography.caption)
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                if dataStore.propAudits.isEmpty {
                    Text("No audit events recorded yet.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(dataStore.propAudits.reversed()) { a in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(AppColors.brand)
                                    .padding(.top, 5)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(a.entityType.uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppColors.brand.opacity(0.12))
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text(a.createdAt.prefix(19))
                                            .font(.system(size: 10))
                                            .monospacedDigit()
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                    
                                    Text(a.reason)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                    
                                    Text("ID: \(a.entityId)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                }
                            }
                            
                            if a.id != dataStore.propAudits.first?.id {
                                Divider().background(AppColors.border.opacity(0.3))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - New Prop Account Sheet

public struct NewPropAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultCurrency: String
    var initialFirm: String = "Topstep"
    var initialProgram: PropProgram = .evaluation
    var initialSizeText: String = "50000"
    var parentId: String? = nil
    
    @State private var firm: String
    @State private var name: String = ""
    @State private var program: PropProgram
    @State private var sizeText: String
    @State private var notes: String = ""
    
    var onSave: (PropAccountItem) -> Void
    
    public init(
        defaultCurrency: String,
        initialFirm: String = "Topstep",
        initialProgram: PropProgram = .evaluation,
        initialSizeText: String = "50000",
        parentId: String? = nil,
        onSave: @escaping (PropAccountItem) -> Void
    ) {
        self.defaultCurrency = defaultCurrency
        self.initialFirm = initialFirm
        self.initialProgram = initialProgram
        self.initialSizeText = initialSizeText
        self.parentId = parentId
        self.onSave = onSave
        _firm = State(initialValue: initialFirm)
        _program = State(initialValue: initialProgram)
        _sizeText = State(initialValue: initialSizeText)
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                if let pId = parentId {
                    Section("Lineage Link") {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(AppColors.accent)
                            Text("Next phase (Parent: \(pId))")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
                
                Section("Firm & Account Name") {
                    TextField("Firm name (Topstep, FTMO, Apex...)", text: $firm)
                    TextField("Account name", text: $name)
                }
                
                Section("Program Type & Size") {
                    Picker("Stage", selection: $program) {
                        ForEach(PropProgram.allCases, id: \.self) { prog in
                            Text(prog.label).tag(prog)
                        }
                    }
                    TextField("Account size (\(defaultCurrency))", text: $sizeText)
                        .keyboardType(.numberPad)
                }
                
                Section("Notes") {
                    TextField("Drawdown rules, profit targets...", text: $notes)
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle(parentId == nil ? "Track account" : "Next stage / Phase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let sizeMinor = (Int64(sizeText) ?? 0) * 100
                        
                        let acc = PropAccountItem(
                            firm: firm,
                            name: name.isEmpty ? "\(firm) Account" : name,
                            program: program,
                            status: .active,
                            currency: defaultCurrency,
                            sizeMinor: sizeMinor,
                            parentId: parentId,
                            openedOn: today,
                            notes: notes
                        )
                        onSave(acc)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit Prop Account Sheet

public struct EditPropAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: PropAccountItem
    var onSave: (PropAccountItem) -> Void
    
    @State private var name: String
    @State private var status: PropStatus
    @State private var notes: String
    @State private var renewalDateText: String
    @State private var renewalAmountText: String
    @State private var closedDateText: String
    
    public init(account: PropAccountItem, onSave: @escaping (PropAccountItem) -> Void) {
        self.account = account
        self.onSave = onSave
        _name = State(initialValue: account.name)
        _status = State(initialValue: account.status)
        _notes = State(initialValue: account.notes)
        _renewalDateText = State(initialValue: account.renewalOn ?? "")
        _renewalAmountText = State(initialValue: account.renewalMinor.map { String($0 / 100) } ?? "")
        _closedDateText = State(initialValue: account.closedOn ?? "")
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Firm & Account Name") {
                    Text("Firm: \(account.firm)")
                        .foregroundColor(AppColors.secondaryText)
                    TextField("Account name", text: $name)
                }
                
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(PropStatus.allCases, id: \.self) { st in
                            Text(st.label).tag(st)
                        }
                    }
                    if status == .passed || status == .breached || status == .closed {
                        TextField("Closed date (YYYY-MM-DD)", text: $closedDateText)
                    }
                }
                
                Section("Renewal Reminder") {
                    TextField("Next renewal date (YYYY-MM-DD)", text: $renewalDateText)
                    TextField("Renewal fee (\(account.currency))", text: $renewalAmountText)
                        .keyboardType(.numberPad)
                }
                
                Section("Notes") {
                    TextField("Account notes...", text: $notes)
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = account
                        let cleanName = name.trimmingCharacters(in: .whitespaces)
                        updated.name = cleanName.isEmpty ? account.name : cleanName
                        updated.status = status
                        updated.notes = notes
                        let cleanClosed = closedDateText.trimmingCharacters(in: .whitespaces)
                        updated.closedOn = cleanClosed.isEmpty ? nil : cleanClosed
                        let cleanRenewal = renewalDateText.trimmingCharacters(in: .whitespaces)
                        updated.renewalOn = cleanRenewal.isEmpty ? nil : cleanRenewal
                        if let rAmt = Int64(renewalAmountText.trimmingCharacters(in: .whitespaces)) {
                            updated.renewalMinor = rAmt * 100
                        } else {
                            updated.renewalMinor = nil
                        }
                        updated.revision += 1
                        updated.updatedAt = JournalIds.nowIso()
                        onSave(updated)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Prop Audit Trail Sheet

public struct PropAuditTrailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let audits: [PropAuditItem]
    
    public var body: some View {
        NavigationStack {
            List {
                if audits.isEmpty {
                    Text("No audit history recorded.")
                        .foregroundColor(AppColors.secondaryText)
                } else {
                    ForEach(audits.reversed()) { a in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(a.entityType.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.accent)
                                Spacer()
                                Text(a.createdAt.prefix(19))
                                    .font(.system(size: 10))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Text(a.reason)
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.primaryText)
                            Text("ID: \(a.entityId)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Prop Audit Trail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - New Prop Entry Sheet

public struct NewPropEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let accounts: [PropAccountItem]
    let defaultCurrency: String
    
    @State private var selectedAccountId: String = ""
    @State private var firm: String = "Topstep"
    @State private var kind: String = "expense"
    @State private var category: PropExpenseCategory = .evaluation
    @State private var amountText: String = ""
    @State private var splitText: String = "90"
    @State private var feeText: String = "0"
    @State private var notes: String = ""
    
    var onSave: (PropEntryItem) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Linked Account") {
                    Picker("Account", selection: $selectedAccountId) {
                        Text("Shared firm cost").tag("")
                        ForEach(accounts) { acc in
                            Text("\(acc.firm) - \(acc.name)").tag(acc.id)
                        }
                    }
                }
                
                Section("Classification") {
                    Picker("Transaction type", selection: $kind) {
                        Text("Expense (Fee, reset...)").tag("expense")
                        Text("Payout request").tag("payout")
                    }
                    
                    if kind == "expense" {
                        Picker("Expense category", selection: $category) {
                            ForEach(PropExpenseCategory.allCases, id: \.self) { cat in
                                Text(cat.label).tag(cat)
                            }
                        }
                    }
                }
                
                Section("Amount") {
                    TextField("Amount (\(defaultCurrency))", text: $amountText)
                        .keyboardType(.decimalPad)
                    
                    if kind == "payout" {
                        TextField("Trader split (%) (e.g. 90)", text: $splitText)
                            .keyboardType(.numberPad)
                        TextField("Transfer fee (\(defaultCurrency))", text: $feeText)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section("Notes") {
                    TextField("Invoice number, context...", text: $notes)
                }
            }
            .font(AppTypography.inputText)
            .navigationTitle("Record expense / Payout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText, currency: defaultCurrency)) ?? 0
                        let feeMinor = (try? PropFirmEngine.toMinor(value: feeText, currency: defaultCurrency)) ?? 0
                        let splitBps = ((Int(splitText) ?? 100) * 100)
                        
                        let linkedAcc = accounts.first(where: { $0.id == selectedAccountId })
                        let firmName = linkedAcc?.firm ?? firm
                        
                        let entry = PropEntryItem(
                            accountId: selectedAccountId.isEmpty ? nil : selectedAccountId,
                            firm: firmName,
                            kind: kind,
                            category: kind == "payout" ? "payout" : category.rawValue,
                            currency: defaultCurrency,
                            amountMinor: minor,
                            splitBps: splitBps,
                            feeMinor: feeMinor,
                            occurredOn: today,
                            status: kind == "payout" ? .requested : .completed,
                            notes: notes
                        )
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add Receipt Sheet

public struct AddReceiptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payout: PropEntryItem
    
    @State private var amountText: String = ""
    @State private var isReversal: Bool = false
    @State private var reference: String = ""
    @State private var notes: String = ""
    
    var onAdd: (PropReceiptItem) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Payout Details") {
                    Text("Firm: \(payout.firm)")
                    Text("Expected payout: \(Formatters.formatCurrency(Decimal(PropFirmEngine.expectedPayout(entry: payout)) / 100, currency: payout.currency))")
                }
                
                Section("Cash Settlement") {
                    Toggle("Reversal / Return?", isOn: $isReversal)
                    TextField("Actual amount received (\(payout.currency))", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Bank reference (Deel, Wise...)", text: $reference)
                }
                
                Section("Notes") {
                    TextField("Additional notes...", text: $notes)
                }
            }
            .navigationTitle("Record payout receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText, currency: payout.currency)) ?? 0
                        
                        let rcpt = PropReceiptItem(
                            payoutId: payout.id,
                            kind: isReversal ? "reversal" : "receipt",
                            amountMinor: minor,
                            occurredOn: today,
                            reference: reference,
                            notes: notes
                        )
                        onAdd(rcpt)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add Refund Sheet

public struct AddRefundSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expense: PropEntryItem
    
    @State private var amountText: String = ""
    @State private var notes: String = "Evaluation fee refund after passing"
    
    var onRefund: (PropEntryItem) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Original Expense") {
                    Text("Firm: \(expense.firm)")
                    Text("Amount spent: \(Formatters.formatCurrency(Decimal(expense.amountMinor) / 100, currency: expense.currency))")
                }
                
                Section("Refund Amount") {
                    TextField("Refunded amount (\(expense.currency))", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Notes...", text: $notes)
                }
            }
            .navigationTitle("Record refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        let today = formatter.string(from: Date())
                        let minor = (try? PropFirmEngine.toMinor(value: amountText, currency: expense.currency)) ?? 0
                        
                        let refundEntry = PropEntryItem(
                            accountId: expense.accountId,
                            firm: expense.firm,
                            kind: "refund",
                            category: "refund",
                            currency: expense.currency,
                            amountMinor: minor,
                            occurredOn: today,
                            status: .completed,
                            parentId: expense.id,
                            notes: notes
                        )
                        onRefund(refundEntry)
                        dismiss()
                    }
                    .disabled(amountText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Prop CSV Import Sheet

public struct PropCsvImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var csvContent: String = ""
    @State private var importResult: PropCsvImportResult? = nil
    @State private var errorMessage: String? = nil
    @State private var isImporting: Bool = false
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Standard CSV Template (/prop-cash-template.csv)") {
                    Text("id,kind,firm,account_id,currency,date,amount,category,expense_id,reference,notes")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Section("CSV Content") {
                    TextEditor(text: $csvContent)
                        .frame(minHeight: 160)
                        .font(.system(size: 12, design: .monospaced))
                    
                    if let err = errorMessage {
                        Text(err)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                }
                
                if let res = importResult {
                    Section("Import Preview") {
                        Text("Valid rows to import: \(res.imported)")
                            .foregroundColor(AppColors.profit)
                        Text("Duplicate rows skipped: \(res.skipped)")
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .navigationTitle("Import Prop CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if importResult == nil {
                        Button("Preview") {
                            do {
                                errorMessage = nil
                                let res = try dataStore.importPropCsvData(csvText: csvContent, preview: true)
                                importResult = res
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .disabled(csvContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Import now") {
                            do {
                                errorMessage = nil
                                _ = try dataStore.importPropCsvData(csvText: csvContent, preview: false)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }
}
