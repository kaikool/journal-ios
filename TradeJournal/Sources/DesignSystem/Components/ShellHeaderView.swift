import SwiftUI

/// Unified Modern Top Navigation Bar conforming to Apple Human Interface Guidelines:
/// - Brand logo emblem button as the primary drawer navigation trigger (replaces generic 3-line hamburger icon)
/// - Contextual page identity: Dedicated page-specific SF Symbol + prominent title (18pt bold rounded)
/// - Trailing cluster: Refined Account Selector chip (concrete accounts only, no "All Accounts"),
///   clean Time Range selector (7D, 30D, 90D, YTD, no "ALL"), and Quick Privacy toggle
/// - Spacious Apple HIG vertical padding (10pt) and horizontal breathing room (16pt)
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    private var currentAccountName: String {
        if let acc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId || TradeDataStore.isSameAccountId($0.id, dataStore.selectedAccountId) }) {
            return Formatters.cleanAccountName(acc.name, balance: acc.initialBalance)
        }
        if let first = dataStore.visibleAccounts.first {
            return Formatters.cleanAccountName(first.name, balance: first.initialBalance)
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
    
    private var shouldShowTimeRangeSelector: Bool {
        switch env.selectedTab {
        case .dashboard, .trades, .reports:
            return true
        default:
            return false
        }
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Leading: App Brand Logo as Drawer Menu Trigger (Replaces generic 3-line hamburger icon)
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
            
            Spacer(minLength: 6)
            
            // Trailing 1: Compact Account Selector Chip (Shown when multiple accounts exist; concrete accounts only, no "All Accounts")
            if shouldShowAccountSelector {
                accountSelectorMenu
            }
            
            // Trailing 2: Compact Time Range Selector Chip (Dashboard, Trades, Reports; 7D, 30D, 90D, YTD, no "ALL")
            if shouldShowTimeRangeSelector {
                timeRangeSelectorMenu
            }
            
            // Trailing 3: Sleek Privacy Mode Toggle Button
            privacyToggleButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(AppColors.border.opacity(0.35)),
            alignment: .bottom
        )
    }
    
    // MARK: - Subcomponents
    
    private var timeRangeSelectorMenu: some View {
        Menu {
            ForEach(JournalTimeRange.selectableCases) { range in
                Button {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    dataStore.selectedTimeRange = range
                } label: {
                    HStack {
                        Text(range.rawValue)
                        if dataStore.selectedTimeRange == range {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                
                Text(dataStore.selectedTimeRange.rawValue == "ALL" ? "30D" : dataStore.selectedTimeRange.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(height: 32)
            .background(AppColors.cardBackground.opacity(0.9))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppColors.border.opacity(0.6), lineWidth: 0.7)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Select Time Range")
    }
    
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
            HStack(spacing: 5) {
                Circle()
                    .fill(AppColors.profit)
                    .frame(width: 6, height: 6)
                
                Text(currentAccountName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 110)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 10)
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
    
    private var privacyToggleButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.2)) {
                env.isPrivacyModeEnabled.toggle()
            }
        } label: {
            Image(systemName: env.isPrivacyModeEnabled ? "eye.slash.fill" : "eye")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(env.isPrivacyModeEnabled ? AppColors.warning : AppColors.secondaryText)
                .frame(width: 32, height: 32)
                .background(AppColors.cardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppColors.border.opacity(0.55), lineWidth: 0.7)
                )
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel(env.isPrivacyModeEnabled ? "Disable privacy mode" : "Enable privacy mode")
    }
}
