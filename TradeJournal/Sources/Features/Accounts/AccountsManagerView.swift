import SwiftUI

public enum AccountFilterTab: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case active = "Active"
    case visible = "Displayed"
    case all = "All"
    
    public var id: String { rawValue }
}

/// Accounts Manager screen matching `source-repo/apps/web/src/app/accounts/page.tsx`:
/// - FilterBar with title "Accounts" and "New account" button
/// - Tab filters: Default, Active, Displayed, All with live counts
/// - Search input
/// - Bulk visibility actions: Active only, Show all, Hide all
/// - Account card with visibility checkbox, broker/status badges, initial balance, trade count, sync toggle, archive/restore and delete
public struct AccountsManagerView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var filterTab: AccountFilterTab = .default
    @State private var searchText: String = ""
    @State private var showNewAccountSheet: Bool = false
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var syncingAccountId: String? = nil
    
    public init() {}
    
    private var accounts: [Account] {
        dataStore.accounts
    }
    
    private var defaultCount: Int {
        accounts.filter { dataStore.isAccountActive($0) || dataStore.isAccountVisible($0) }.count
    }
    
    private var activeCount: Int {
        accounts.filter { dataStore.isAccountActive($0) }.count
    }
    
    private var visibleCount: Int {
        accounts.filter { dataStore.isAccountVisible($0) }.count
    }
    
    private var filteredAccounts: [Account] {
        accounts.filter { acc in
            let isActive = dataStore.isAccountActive(acc)
            let isVisible = dataStore.isAccountVisible(acc)
            
            switch filterTab {
            case .default:
                if !isActive && !isVisible { return false }
            case .active:
                if !isActive { return false }
            case .visible:
                if !isVisible { return false }
            case .all:
                break
            }
            
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let matches = acc.name.lowercased().contains(q) ||
                              acc.broker.lowercased().contains(q) ||
                              acc.id.lowercased().contains(q) ||
                              (acc.propProgram?.lowercased().contains(q) ?? false)
                if !matches { return false }
            }
            return true
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Accounts",
                showFilters: false
            ) {
                AppButton("New account", icon: "plus", style: .primary) {
                    showNewAccountSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    // Filter & Search Controls matching accounts/page.tsx line 182-228
                    filterAndSearchHeader
                    
                    // Bulk Visibility Actions matching accounts/page.tsx line 229-250
                    bulkVisibilityBar
                    
                    // Account Cards List
                    if filteredAccounts.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredAccounts) { acc in
                                accountCard(acc)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showNewAccountSheet) {
            CreateAccountSheet()
        }
        .alert("Delete Account", isPresented: $showDeleteAlert, presenting: accountToDelete) { acc in
            Button("Delete", role: .destructive) {
                dataStore.deleteAccount(id: acc.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { acc in
            Text("This will remove “\(acc.name)” and unlink its associated trades from your device.")
        }
    }
    
    // MARK: - Subviews
    
    private var filterAndSearchHeader: some View {
        VStack(spacing: 10) {
            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton(title: "Default (\(defaultCount))", tab: .default)
                    filterButton(title: "Active (\(activeCount))", tab: .active)
                    filterButton(title: "Displayed (\(visibleCount))", tab: .visible)
                    filterButton(title: "All (\(accounts.count))", tab: .all)
                }
                .padding(.horizontal, 16)
            }
            
            // Search Input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                TextField("Search by name, broker, ID...", text: $searchText)
                    .font(AppTypography.body)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private func filterButton(title: String, tab: AccountFilterTab) -> some View {
        Button {
            filterTab = tab
        } label: {
            Text(title)
                .font(AppTypography.captionBold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(filterTab == tab ? AppColors.brand : AppColors.secondaryBackground)
                .foregroundColor(filterTab == tab ? AppColors.brandTextOnDark : AppColors.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var bulkVisibilityBar: some View {
        HStack(spacing: 8) {
            Text("Quick display:")
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
            
            Button("Active only") {
                dataStore.setBulkAccountVisibility(action: "select-active")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .foregroundColor(AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Button("Show all") {
                dataStore.setBulkAccountVisibility(action: "select-all")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .foregroundColor(AppColors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Button("Hide all") {
                dataStore.setBulkAccountVisibility(action: "deselect-all")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.cardBackground)
            .foregroundColor(AppColors.secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 40))
                .foregroundColor(AppColors.secondaryText.opacity(0.6))
            Text("No accounts found")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
            Text("Create a new account or connect your broker sync credentials in Settings.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    @ViewBuilder
    private func accountCard(_ acc: Account) -> some View {
        let isSelected = dataStore.selectedAccountId == acc.id
        let isArchived = acc.archivedAt != nil
        let tradeCount = dataStore.trades.filter { $0.accountId == acc.id }.count
        let isVisible = acc.visibleInJournal ?? true
        
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Journal visibility toggle button
                    Button {
                        dataStore.toggleAccountVisibility(id: acc.id)
                    } label: {
                        Image(systemName: isVisible ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundColor(isVisible ? AppColors.brand : AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(acc.name)
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.profit)
                                    .font(.system(size: 14))
                            }
                        }
                        
                        Text("ID: \(acc.id)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Primary active view button
                    if !isSelected {
                        Button("Select") {
                            dataStore.selectAccount(id: acc.id)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.brand.opacity(0.12))
                        .foregroundColor(AppColors.brand)
                        .clipShape(Capsule())
                    } else {
                        Text("Viewing")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.profit.opacity(0.15))
                            .foregroundColor(AppColors.profit)
                            .clipShape(Capsule())
                    }
                }
                
                // Badges
                HStack(spacing: 6) {
                    if isArchived {
                        badgeView("Archived", color: AppColors.secondaryText)
                    } else {
                        badgeView("Active", color: AppColors.profit)
                    }
                    
                    if !acc.broker.isEmpty {
                        badgeView(acc.broker, color: AppColors.brand)
                    }
                    
                    badgeView(acc.kind.rawValue.uppercased(), color: AppColors.secondaryText)
                    badgeView(acc.profitCalcMethod.rawValue.uppercased(), color: AppColors.secondaryText)
                    
                    if acc.autoSync {
                        badgeView("Auto-sync", color: AppColors.profit)
                    }
                }
                
                Divider()
                
                // Balance and Trades Info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Initial balance")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatCurrency(acc.initialBalance, currency: acc.currency))
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total trades")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(tradeCount) trades")
                            .font(AppTypography.bodyBold)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                
                Divider()
                
                // Action row
                HStack(spacing: 12) {
                    // Auto sync toggle
                    Toggle("Auto-sync", isOn: Binding(
                        get: { acc.autoSync },
                        set: { _ in dataStore.toggleAccountAutoSync(id: acc.id) }
                    ))
                    .font(.system(size: 11))
                    .tint(AppColors.brand)
                    
                    Spacer()
                    
                    // Archive / Restore
                    Button {
                        dataStore.archiveAccount(id: acc.id, archived: !isArchived)
                    } label: {
                        Image(systemName: isArchived ? "tray.and.arrow.up" : "archivebox")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    // Delete
                    Button {
                        accountToDelete = acc
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.loss.opacity(0.8))
                    }
                }
            }
        }
        .opacity(isArchived ? 0.65 : 1.0)
    }
    
    @ViewBuilder
    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Sheet to create a new trading account
public struct CreateAccountSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var broker: String = "The5ers"
    @State private var currency: String = "USD"
    @State private var initialBalanceText: String = "10000"
    @State private var calcMethod: ProfitCalcMethod = .fifo
    
    private let commonBrokers = ["The5ers", "FTMO", "Topstep", "Oanda", "MetaTrader 5", "Binance", "Manual"]
    private let commonCurrencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Account & Broker")) {
                    TextField("Account name (e.g. The5ers 100K Bootcamp)", text: $name)
                    
                    Picker("Broker", selection: $broker) {
                        ForEach(commonBrokers, id: \.self) { b in
                            Text(b).tag(b)
                        }
                    }
                }
                
                Section(header: Text("Financials & Calculation Method")) {
                    Picker("Currency", selection: $currency) {
                        ForEach(commonCurrencies, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    
                    TextField("Initial balance", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                    
                    Picker("P&L Method", selection: $calcMethod) {
                        Text("FIFO (First In First Out)").tag(ProfitCalcMethod.fifo)
                        Text("LIFO (Last In First Out)").tag(ProfitCalcMethod.lifo)
                        Text("Weighted Average").tag(ProfitCalcMethod.wavg)
                    }
                }
            }
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let bal = Decimal(string: initialBalanceText) ?? 0
                        dataStore.addAccount(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            broker: broker,
                            currency: currency,
                            initialBalance: bal,
                            profitCalcMethod: calcMethod
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .font(AppTypography.headline)
                }
            }
        }
    }
}
