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
                    HStack(spacing: 6) {
                        AppButton("Track account", icon: "plus", style: .outline) {
                            showNewAccountSheet = true
                        }
                        AppButton("Add expense", icon: "arrow.up.right", style: .outline) {
                            showNewEntrySheet = true
                        }
                        AppButton("Track payout", icon: "arrow.down.left", style: .primary) {
                            showAddReceiptSheet = true
                        }
                    }
                }
                
                // Currency Selector Bar
                HStack {
                    Text("Currency:")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(availableCurrencies, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Spacer()
                    
                    if selectedTab == .accounts {
                        Toggle("Archived", isOn: $showArchivedAccounts)
                            .toggleStyle(.button)
                            .font(.system(size: 11, weight: .medium))
                            .tint(AppColors.brand)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.cardBackground.opacity(0.6))
                
                // Segmented Tab Picker
                Picker("Section", selection: $selectedTab) {
                    ForEach(PropLedgerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
                
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
            }
            .sheet(item: $selectedAccountForEdit) { acc in
                EditPropAccountSheet(account: acc) { updatedAcc in
                    dataStore.savePropAccount(item: updatedAcc, reason: "Update account details")
                }
            }
            .sheet(isPresented: $showAuditSheet) {
                PropAuditTrailSheet(audits: dataStore.propAudits)
            }
            .sheet(isPresented: $showNewEntrySheet) {
                NewPropEntrySheet(accounts: filteredAccounts, defaultCurrency: selectedCurrency) { newEntry in
                    dataStore.savePropEntry(item: newEntry, reason: "Record transaction")
                }
            }
            .sheet(item: $selectedPayoutForReceipt) { payout in
                AddReceiptSheet(payout: payout) { receipt in
                    try? dataStore.addPropReceipt(item: receipt, reason: "Payout receipt settlement")
                }
            }
            .sheet(item: $selectedExpenseForRefund) { expense in
                AddRefundSheet(expense: expense) { refundEntry in
                    dataStore.savePropEntry(item: refundEntry, reason: "Evaluation fee refund")
                }
            }
            .sheet(isPresented: $showCsvSheet) {
                PropCsvImportSheet()
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
                        AppCard {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(AppColors.accent)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upcoming renewal: \(rAcc.firm)")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                    Text("\(rAcc.name) • Due: \(rAcc.renewalOn ?? "") • Fee: \(Formatters.formatCurrency(Decimal(rAcc.renewalMinor ?? 0) / 100, currency: rAcc.currency))")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            
            // Summary Card
            AppCard {
                VStack(spacing: 12) {
                    HStack {
                        Text("NET PROP CASH (\(selectedCurrency))")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        if let roi = summary.roi {
                            AppBadge(
                                text: String(format: "ROI: %+.1f%%", roi * 100),
                                color: roi >= 0 ? AppColors.profit : AppColors.loss
                            )
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline) {
                        let netDecimal = Decimal(summary.netMinor) / 100
                        Text(Formatters.formatPnL(netDecimal, currency: selectedCurrency))
                            .font(AppTypography.financialNumber(size: 32, weight: .bold))
                            .foregroundColor(Formatters.pnlColor(netDecimal))
                        Spacer()
                    }
                    
                    Divider().background(AppColors.border)
                    
                    // Spending vs Received
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gross spent")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(Decimal(summary.spentMinor) / 100, currency: selectedCurrency))
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.loss)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Refunded")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(Decimal(summary.refundsMinor) / 100, currency: selectedCurrency))
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Net spend")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(Decimal(summary.netSpendMinor) / 100, currency: selectedCurrency))
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Payouts received")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(Formatters.formatCurrency(Decimal(summary.receivedMinor) / 100, currency: selectedCurrency))
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                    }
                }
            }
            
            // Pass Rate & Account Outcomes Card
            if let pr = passRate {
                AppCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Phase pass rate")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Text(String(format: "%.1f%%", pr * 100))
                                .font(AppTypography.headline)
                                .foregroundColor(pr >= 0.5 ? AppColors.profit : AppColors.accent)
                        }
                        Spacer()
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
            
            // Cumulative Net Cash Chart
            if !timelinePoints.isEmpty {
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUMULATIVE CASH TIMELINE")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Chart {
                            ForEach(timelinePoints, id: \.date) { pt in
                                LineMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", Double(pt.netMinor) / 100.0)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(AppColors.accent)
                                
                                AreaMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Net cash", Double(pt.netMinor) / 100.0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.accent.opacity(0.3), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }
                        .frame(height: 180)
                    }
                }
            }
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
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(acc.firm)
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.accent)
                                if acc.archived {
                                    Text("[Archived]")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                                AppBadge(
                                    text: acc.status.label,
                                    color: acc.status == .active || acc.status == .passed ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Text(acc.name)
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            if let parentId = acc.parentId, let parentAcc = dataStore.propAccounts.first(where: { $0.id == parentId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.accent)
                                    Text("Next phase of: \(parentAcc.name)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.accent)
                                }
                            }
                            
                            HStack {
                                if let size = acc.sizeMinor {
                                    Text("Size: \(Formatters.formatCurrency(Decimal(size) / 100, currency: acc.currency))")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                Spacer()
                                Text(acc.program.label)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Divider().background(AppColors.border)
                            
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
                                        selectedAccountForNextPhase = acc
                                    } label: {
                                        Text("Next phase")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppColors.accent)
                                    }
                                }
                                
                                Button {
                                    selectedAccountForEdit = acc
                                } label: {
                                    Text("Edit")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.accent)
                                }
                                
                                Button {
                                    dataStore.archivePropAccount(id: acc.id, archived: !acc.archived, reason: "User toggle archive")
                                } label: {
                                    Text(acc.archived ? "Restore" : "Archive")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                }
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
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(p.entry.firm) Payout")
                                    .font(AppTypography.subheadlineBold)
                                Spacer()
                                if p.isOverdue {
                                    AppBadge(text: "Overdue", color: AppColors.loss)
                                } else if p.isPartial {
                                    AppBadge(text: "Partially received", color: AppColors.brand)
                                }
                                AppBadge(
                                    text: p.entry.status.label,
                                    color: p.entry.status == .completed ? AppColors.profit : AppColors.accent
                                )
                            }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Expected payout (after split):")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(p.expectedMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Actually received:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                    Text(Formatters.formatCurrency(Decimal(p.actualMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
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
                                        .foregroundColor(p.varianceMinor >= 0 ? AppColors.profit : AppColors.loss)
                                }
                            }
                            
                            Divider().background(AppColors.border)
                            
                            HStack {
                                Text("Requested: \(p.entry.occurredOn)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Button {
                                    selectedPayoutForReceipt = p.entry
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                        Text("Record receipt")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                }
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
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(m.firm)
                                        .font(AppTypography.subheadlineBold)
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
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                let isIncoming = m.kind == "receipt" || m.kind == "refund"
                                let amountDecimal = Decimal(m.amountMinor) / 100
                                Text("\(isIncoming ? "+" : "-")\(Formatters.formatCurrency(amountDecimal, currency: m.currency))")
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(isIncoming ? AppColors.profit : AppColors.loss)
                                
                                HStack(spacing: 8) {
                                    if m.kind == "expense" {
                                        Button {
                                            if let entry = dataStore.propEntries.first(where: { $0.id == m.entryId }) {
                                                selectedExpenseForRefund = entry
                                            }
                                        } label: {
                                            Text("Refund")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(AppColors.accent)
                                        }
                                    }
                                    
                                    Button {
                                        itemToVoid = (id: m.entryId, isEntry: true)
                                        showVoidAlert = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(AppColors.loss.opacity(0.8))
                                    }
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
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Activity & Audit Trail")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text("\(dataStore.propAudits.count) events")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Divider()
                
                if dataStore.propAudits.isEmpty {
                    Text("No audit events recorded yet.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(dataStore.propAudits.reversed()) { a in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.accent)
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 4) {
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
                                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                }
                            }
                            
                            if a.id != dataStore.propAudits.first?.id {
                                Divider()
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
