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
    
    @State private var filterTab: AccountFilterTab = .visible
    @State private var searchText: String = ""
    @State private var showNewAccountSheet: Bool = false
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var syncingAccountId: String? = nil
    @Namespace private var accountsFilterNamespace
    
    public init() {}
    
    private var accounts: [Account] {
        dataStore.accounts
    }
    
    private var defaultCount: Int {
        accounts.filter { dataStore.isAccountVisible($0) }.count
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
                if !isVisible { return false }
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
    
    // MARK: - Apple HIG Card Container
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
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Accounts",
                showFilters: false
            ) {
                AppActionPill("New account", icon: "plus") {
                    showNewAccountSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 14) {
                    // Filter & Search Controls
                    filterAndSearchHeader
                    
                    // Bulk Visibility Actions
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
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showNewAccountSheet) {
            CreateAccountSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
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
            // Universal Apple HIG Sliding Filter Bar
            AppleSlidingSegmentedBar(
                selection: $filterTab,
                items: AccountFilterTab.allCases,
                titleFor: { $0.rawValue },
                badgeCountFor: { tab in
                    switch tab {
                    case .default: return defaultCount
                    case .active: return activeCount
                    case .visible: return visibleCount
                    case .all: return accounts.count
                    }
                }
            )
            .padding(.horizontal, 16)
            
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.secondaryText)
                    .font(.system(size: 13))
                TextField("Search by name, broker, ID...", text: $searchText)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.secondaryText)
                            .font(.system(size: 13))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }
    
    private var bulkVisibilityBar: some View {
        HStack(spacing: 8) {
            Text("Quick display:")
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dataStore.setBulkAccountVisibility(action: "select-active")
            } label: {
                Text("Active only")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.cardBackground)
                    .foregroundColor(AppColors.primaryText)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dataStore.setBulkAccountVisibility(action: "select-all")
            } label: {
                Text("Show all")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.cardBackground)
                    .foregroundColor(AppColors.primaryText)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dataStore.setBulkAccountVisibility(action: "deselect-all")
            } label: {
                Text("Hide all")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.cardBackground)
                    .foregroundColor(AppColors.secondaryText)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    private var emptyStateView: some View {
        cardContainer {
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
            .padding(.vertical, 40)
        }
        .padding(.horizontal, 16)
    }
    
    private var tradeCountMap: [String: Int] {
        var map: [String: Int] = [:]
        for t in dataStore.trades {
            map[t.accountId, default: 0] += 1
            let clean = t.accountId.hasPrefix("the5ers_") ? String(t.accountId.dropFirst(8)) : t.accountId
            map[clean, default: 0] += 1
        }
        return map
    }
    
    @ViewBuilder
    private func accountCard(_ acc: Account) -> some View {
        let isSelected = dataStore.selectedAccountId == acc.id
        let isArchived = acc.archivedAt != nil
        let altId = acc.id.hasPrefix("the5ers_") ? String(acc.id.dropFirst(8)) : "the5ers_\(acc.id)"
        let tradeCount = tradeCountMap[acc.id] ?? tradeCountMap[altId] ?? 0
        let isVisible = acc.visibleInJournal ?? true
        
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Journal visibility toggle button
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        dataStore.toggleAccountVisibility(id: acc.id)
                    } label: {
                        Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(isVisible ? AppColors.brand : AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(Formatters.cleanAccountName(acc.name, balance: acc.initialBalance))
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                            
                            if isSelected {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(AppColors.profit)
                                    .font(.system(size: 13))
                            }
                        }
                        
                        Text("\(acc.broker.isEmpty ? "Standard" : acc.broker) · \(acc.currency)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Primary active view button
                    if !isSelected {
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            dataStore.selectAccount(id: acc.id)
                        } label: {
                            Text("Select")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(AppColors.brand.opacity(0.12))
                                .foregroundColor(AppColors.brand)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                    } else {
                        Text("Viewing")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
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
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Balance and Trades Info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Initial Balance")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatCurrency(acc.initialBalance, currency: acc.currency))
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Trades")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(tradeCount) trades")
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Action row
                HStack(spacing: 12) {
                    // Auto sync toggle
                    Toggle("Auto-sync", isOn: Binding(
                        get: { acc.autoSync },
                        set: { _ in dataStore.toggleAccountAutoSync(id: acc.id) }
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .tint(AppColors.brand)
                    
                    Spacer()
                    
                    // Archive / Restore
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        dataStore.archiveAccount(id: acc.id, archived: !isArchived)
                    } label: {
                        Image(systemName: isArchived ? "tray.and.arrow.up" : "archivebox")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    // Delete
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        accountToDelete = acc
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.loss.opacity(0.8))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
        }
        .opacity(isArchived ? 0.65 : 1.0)
    }
    
    @ViewBuilder
    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
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
                    
                    AppDropdownField(
                        label: "Broker",
                        selection: $broker,
                        options: commonBrokers,
                        titleFor: { $0 }
                    )
                }
                
                Section(header: Text("Financials & Calculation Method")) {
                    AppDropdownField(
                        label: "Currency",
                        selection: $currency,
                        options: commonCurrencies,
                        titleFor: { $0 }
                    )
                    
                    TextField("Initial balance", text: $initialBalanceText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    
                    AppDropdownField(
                        label: "P&L Method",
                        selection: $calcMethod,
                        options: [ProfitCalcMethod.fifo, ProfitCalcMethod.lifo, ProfitCalcMethod.wavg],
                        titleFor: { method in
                            switch method {
                            case .fifo: return "FIFO (First In First Out)"
                            case .lifo: return "LIFO (Last In First Out)"
                            case .wavg: return "Weighted Average"
                            }
                        }
                    )
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
