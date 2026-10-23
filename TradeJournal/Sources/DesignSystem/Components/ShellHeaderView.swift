import SwiftUI

/// Unified Modern Top Navigation Bar conforming to Apple Human Interface Guidelines:
/// - Brand logo emblem button as the primary drawer navigation trigger
/// - Contextual page identity: Dedicated page-specific SF Symbol + prominent title (18pt bold rounded)
/// - Modern concise Account Selector chip (concrete accounts only, no truncation)
/// - Pure black background matching body in dark mode (no 2-tone gray/black banding)
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    private var currentAccountName: String {
        if let acc = dataStore.selectedAccount {
            return Formatters.compactAccountName(acc.name)
        }
        if let first = dataStore.visibleAccounts.first {
            return Formatters.compactAccountName(first.name)
        }
        return "Trading Account"
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
            return dataStore.visibleAccounts.count > 1
        default:
            return false
        }
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Leading: App Brand Logo as Drawer Menu Trigger
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                TradeJournalMarkView(size: 24)
                    .frame(width: 38, height: 38)
                    .background(AppColors.cardBackground.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(AppColors.border.opacity(0.55), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Open navigation menu")
            
            // Current Page Identity: Tab-Specific Icon + Page Title
            HStack(spacing: 8) {
                Image(systemName: env.selectedTab.selectedIconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(width: 22, height: 22)
                
                Text(currentTabTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
            }
            .layoutPriority(1)
            
            Spacer(minLength: 8)
            
            // Trailing: Compact Account Selector Chip (concrete accounts only, no "All Accounts")
            if shouldShowAccountSelector {
                accountSelectorMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(AppColors.background)
        .overlay(
            Divider().background(AppColors.border.opacity(0.35)),
            alignment: .bottom
        )
    }
    
    // MARK: - Subcomponents
    
    private var accountSelectorMenu: some View {
        Menu {
            ForEach(dataStore.visibleAccounts) { acc in
                Button {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    dataStore.selectAccount(id: acc.id)
                } label: {
                    HStack {
                        Text(Formatters.cleanAccountName(acc.name, balance: acc.initialBalance))
                        if dataStore.selectedAccount?.id == acc.id {
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
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColors.profit)
                    .frame(width: 6, height: 6)
                
                Text(currentAccountName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 130)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 32)
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
