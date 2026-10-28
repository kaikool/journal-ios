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
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                filterAndSearchHeader
                
                bulkVisibilityBar
                
                allAccountsScopeCard
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            .background(Color.clear)
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
            
            // Search Input & New Account Button
            HStack(spacing: 10) {
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
                .frame(height: 36)
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    showNewAccountSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(AppColors.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var bulkVisibilityBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Quick display:")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    dataStore.setBulkAccountVisibility(action: "select-active")
                } label: {
                    Text("Active only")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
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
                .fixedSize()
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    dataStore.setBulkAccountVisibility(action: "select-all")
                } label: {
                    Text("Show all")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
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
                .fixedSize()
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    dataStore.setBulkAccountVisibility(action: "deselect-all")
                } label: {
                    Text("Hide all")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
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
                .fixedSize()
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var allAccountsScopeCard: some View {
        let isAllSelected = dataStore.selectedAccountId == "all"
        let visibleCount = dataStore.visibleAccounts.count
        let totalCount = dataStore.accounts.count
        
        return Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            dataStore.selectAccount(id: "all")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isAllSelected ? AppColors.brand : AppColors.secondaryText)
                
                Text("All Accounts Combined")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                
                Text("·")
                    .foregroundColor(AppColors.secondaryText.opacity(0.4))
                
                Text("\(visibleCount)/\(totalCount) active")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                if isAllSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Active View")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppColors.profit.opacity(0.12))
                    .foregroundColor(AppColors.profit)
                    .clipShape(Capsule())
                } else {
                    Text("Select All")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(AppColors.brand.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isAllSelected ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.5), lineWidth: 0.8)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
        .padding(.horizontal, 16)
    }

    private var emptyStateView: some View {
        TradeFormCardContainer {
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
}
