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
    
    private var filterTab: AccountFilterTab { env.accountFilterTab }
    @State private var searchText: String = ""
    @State private var showNewAccountSheet: Bool = false
    @State private var accountToEdit: Account? = nil
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var syncingAccountId: String? = nil
    
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
        let q = (env.isSearchActive ? env.searchQuery : searchText).lowercased().trimmingCharacters(in: .whitespaces)
        return accounts.filter { acc in
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
            
            if !q.isEmpty {
                let matches = acc.name.lowercased().contains(q) ||
                              acc.broker.lowercased().contains(q) ||
                              acc.id.lowercased().contains(q) ||
                              (acc.propProgram?.lowercased().contains(q) ?? false)
                if !matches { return false }
            }
            return true
        }
    }
    
    private var tradeCountMap: [String: Int] {
        var map: [String: Int] = [:]
        for t in dataStore.trades {
            let clean = t.accountId.cleanAccountId
            map[clean, default: 0] += 1
        }
        return map
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                let countMap = tradeCountMap
                if filteredAccounts.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredAccounts) { acc in
                            AccountCardView(
                                account: acc,
                                tradeCount: countMap[acc.id.cleanAccountId] ?? countMap[acc.id] ?? (dataStore.propAccount(for: acc)?.totalTrades ?? 0),
                                onEdit: { accountToEdit = acc },
                                onDelete: {
                                    accountToDelete = acc
                                    showDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .onReceive(env.$requestNewAccount) { requested in
            if requested {
                env.requestNewAccount = false
                showNewAccountSheet = true
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .sheet(isPresented: $showNewAccountSheet) {
            CreateAccountSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(item: $accountToEdit) { acc in
            EditAccountSheet(account: acc)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .appConfirmationAlert(
            isPresented: $showDeleteAlert,
            presenting: accountToDelete,
            title: { _ in "Delete Account" },
            message: { acc in "This will remove “\(acc.name)” and unlink its associated trades from your device." }
        ) { acc in
            dataStore.deleteAccount(id: acc.id)
        }
    }
    
    // MARK: - Subviews
    
    private var bulkVisibilityBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Quick display:")
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                
                AppSecondaryButton("Active only", height: 28) {
                    dataStore.setBulkAccountVisibility(action: "select-active")
                }
                .fixedSize()
                
                AppSecondaryButton("Show all", height: 28) {
                    dataStore.setBulkAccountVisibility(action: "select-all")
                }
                .fixedSize()
                
                AppSecondaryButton("Hide all", height: 28) {
                    dataStore.setBulkAccountVisibility(action: "deselect-all")
                }
                .fixedSize()
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var allAccountsScopeCard: some View {
        let isAllSelected = dataStore.selectedAccountId == "all"
        let visibleCount = dataStore.visibleAccounts.count
        let totalCount = dataStore.accounts.count
        
        return HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(AppTypography.actionButtonCompact)
                    .foregroundColor(isAllSelected ? AppColors.brand : AppColors.secondaryText)
                
                Text("All Accounts Combined")
                    .font(AppTypography.rowTitle)
                    .foregroundColor(AppColors.primaryText)
                
                Text("·")
                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
                
                Text("\(visibleCount)/\(totalCount) active")
                    .font(AppTypography.captionMicro)
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                if isAllSelected {
                    AppBadge("Active View", icon: "checkmark", variant: .profit)
                } else {
                    AppBadge("Select All", variant: .brand)
                }
            }
            .appCardStyle(cornerRadius: 12)
            .contentShape(Rectangle())
            .onTapGesture {
                NativeHaptics.lightImpact()
                dataStore.selectAccount(id: "all")
            }
        .padding(.horizontal, 16)
    }

    private var emptyStateView: some View {
        TradeFormCardContainer {
            AppEmptyState(
                icon: "creditcard.and.123",
                title: "No accounts found",
                message: "Create a new account or connect your broker sync credentials in Settings.",
                iconColor: AppColors.secondaryText,
                actionTitle: "New Account",
                actionIcon: "plus",
                isInCard: true
            ) {
                showNewAccountSheet = true
            }
        }
        .padding(.horizontal, 16)
    }
}
