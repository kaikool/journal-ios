import SwiftUI

/// Unified Modern Top Navigation Bar:
/// - Drawer hamburger trigger button with micro-spring animation
/// - Brand logo mark & title
/// - Interactive Account Selector Capsule Chip with direct switching menu
/// - Quick Add Trade button (+) with primary brand styling
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @State private var showAddTradeSheet: Bool = false
    
    public init() {}
    
    private var currentAccountName: String {
        if dataStore.selectedAccountId == "all" {
            let count = dataStore.visibleAccounts.count
            return count > 0 ? "All (\(count))" : "All Accounts"
        }
        if let acc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId }) {
            return Formatters.cleanAccountName(acc.name)
        }
        return "Select Account"
    }
    
    private var currentTabTitle: String {
        switch env.selectedTab {
        case .dashboard: return "Dashboard"
        case .calendar: return "Calendar"
        case .journal: return "Daily Journal"
        case .trades: return "Trades"
        case .reports: return "Analytics"
        case .propFirms: return "Prop Firms"
        case .notebook: return "Notebook"
        case .playbooks: return "Playbooks"
        case .progress: return "Progress"
        case .missed: return "Missed Trades"
        case .importTrades: return "Import Trades"
        case .accounts: return "Accounts"
        case .settings: return "Settings"
        }
    }
    
    private var shouldShowAccountSelector: Bool {
        switch env.selectedTab {
        case .dashboard, .calendar, .journal, .trades, .reports, .propFirms:
            return true
        default:
            return false
        }
    }
    
    private var shouldShowQuickAdd: Bool {
        switch env.selectedTab {
        case .dashboard, .calendar, .journal, .trades:
            return true
        default:
            return false
        }
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Leading: Hamburger Drawer Menu Trigger
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 32, height: 32)
                    .background(AppColors.cardBackground.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.7)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Toggle navigation drawer")
            
            // Current Page Title & Brand Mark (Always prominent and unambiguous)
            HStack(spacing: 6) {
                TradeJournalMarkView(size: 16, color: AppColors.brand)
                
                Text(currentTabTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            
            Spacer(minLength: 6)
            
            // Trailing 1: Compact Account Selector Chip (financial tabs only)
            if shouldShowAccountSelector {
                accountSelectorMenu
            }
            
            // Trailing 2: Refined Circular Quick Add (+) Button
            if shouldShowQuickAdd {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    showAddTradeSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(AppColors.brand)
                        .clipShape(Circle())
                        .shadow(color: AppColors.brand.opacity(0.24), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(ApplePressableButtonStyle())
                .accessibilityLabel("Quick Add Trade")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(AppColors.border.opacity(0.35)),
            alignment: .bottom
        )
        .sheet(isPresented: $showAddTradeSheet) {
            AddTradeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }
    
    private var accountSelectorMenu: some View {
        Menu {
            Button {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                dataStore.selectAccount(id: "all")
            } label: {
                HStack {
                    Text("All Accounts (\(dataStore.visibleAccounts.count))")
                    if dataStore.selectedAccountId == "all" {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            ForEach(dataStore.visibleAccounts) { acc in
                Button {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    dataStore.selectAccount(id: acc.id)
                } label: {
                    HStack {
                        Text(Formatters.cleanAccountName(acc.name, balance: acc.initialBalance))
                        if dataStore.selectedAccountId == acc.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Button {
                env.selectedTab = .accounts
            } label: {
                Label("Manage Accounts...", systemImage: "creditcard")
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(dataStore.selectedAccountId == "all" ? AppColors.brand : AppColors.profit)
                    .frame(width: 6, height: 6)
                
                Text(currentAccountName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 105)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppColors.cardBackground.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 0.7)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Select Trading Account")
    }
}
