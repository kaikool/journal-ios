import SwiftUI
import Charts

public enum PropLedgerTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case accounts = "Accounts"
    case payouts = "Payouts"
    case transactions = "Transactions"
    
    public var id: String { rawValue }
}

public struct PropFirmLedgerView: View {
    @ObservedObject var dataStore = TradeDataStore.shared
    @ObservedObject var env = AppEnvironment.shared
    
    @State var selectedTab: PropLedgerTab = .overview
    @State var selectedCurrency: String = "USD"
    @State var showArchivedAccounts: Bool = false
    
    @State var showNewAccountSheet: Bool = false
    @State var showNewEntrySheet: Bool = false
    @State var showAddReceiptSheet: Bool = false
    @State var showRefundSheet: Bool = false
    @State var showVoidAlert: Bool = false
    @State var showCsvSheet: Bool = false
    @State var showAuditSheet: Bool = false
    
    @State var selectedPayoutForReceipt: PropEntryItem? = nil
    @State var selectedExpenseForRefund: PropEntryItem? = nil
    @State var selectedAccountForEdit: PropAccountItem? = nil
    @State var selectedAccountForNextPhase: PropAccountItem? = nil
    @State var itemToVoid: (id: String, isEntry: Bool)? = nil
    @State var voidReason: String = ""
    
    public init() {}
    
    var availableCurrencies: [String] {
        let set = Set(dataStore.propAccounts.map { $0.currency } + dataStore.propEntries.map { $0.currency })
        return set.isEmpty ? ["USD"] : Array(set).sorted()
    }
    
    var filteredAccounts: [PropAccountItem] {
        dataStore.propAccounts.filter { prop in
            (showArchivedAccounts || !prop.archived) &&
            (prop.currency == selectedCurrency) &&
            dataStore.isPropAccountVisible(prop)
        }
    }
    
    var filteredEntries: [PropEntryItem] {
        dataStore.propEntries.filter { entry in
            !entry.voided &&
            entry.currency == selectedCurrency
        }
    }
    
    var movements: [CashMovementItem] {
        PropFirmEngine.cashMovements(entries: filteredEntries, receipts: dataStore.propReceipts)
            .filter { $0.currency == selectedCurrency }
    }
    
    var summary: CashSummaryResult {
        (try? PropFirmEngine.cashSummary(rows: movements)) ?? CashSummaryResult(
            spentMinor: 0, refundsMinor: 0, netSpendMinor: 0, receivedMinor: 0, netMinor: 0, roi: nil
        )
    }
    
    var timelinePoints: [CashTimelinePoint] {
        (try? PropFirmEngine.cashTimeline(rows: movements)) ?? []
    }
    
    var payoutItems: [PayoutProgressResult] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return PropFirmEngine.payoutProgress(
            entries: filteredEntries,
            receipts: dataStore.propReceipts,
            today: today
        )
    }
    
    var passRate: Double? {
        PropFirmEngine.resolvedPhasePassRate(accounts: filteredAccounts)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // FilterBar matching web
            FilterBarView(
                title: "Prop firms",
                showFilters: false
            ) {
                AppActionMenu("New", icon: "plus") {
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
                }
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
        .alert("Transaction Action", isPresented: $showVoidAlert) {
            TextField("Void reason (optional)...", text: $voidReason)
            Button("Cancel", role: .cancel) { itemToVoid = nil; voidReason = "" }
            Button("Void transaction", role: .destructive) {
                if let target = itemToVoid {
                    if target.isEntry {
                        try? dataStore.voidPropEntry(id: target.id, voided: true, reason: voidReason.isEmpty ? "Void transaction" : voidReason)
                    }
                    itemToVoid = nil
                    voidReason = ""
                }
            }
            Button("Delete permanently", role: .destructive) {
                if let target = itemToVoid {
                    if target.isEntry {
                        dataStore.deletePropEntry(id: target.id)
                    }
                    itemToVoid = nil
                    voidReason = ""
                }
            }
        } message: {
            Text("You can void this transaction to keep it in audit history, or delete it permanently from your journal and Supabase.")
        }
    }
}
