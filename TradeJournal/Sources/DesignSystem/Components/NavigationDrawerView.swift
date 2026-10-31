import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Navigation drawer matching Apple iOS Design Guidelines & Web Shell Parity:
/// - Crisp brand vector mark with proper safe area clearance from the top notch
/// - Refined Hero Account Switcher & Balance card with concise account naming
/// - Comfortable, standard Apple HIG typography (14pt text, 16pt SF Symbols, 42pt touch rows)
/// - Proportioned vertical spacing without cramped clustering
/// - Native Apple glass control dock at bottom: Cloud sync, Theme switcher, and Privacy mode
public struct NavigationDrawerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    private var mainNavTabs: [AppTab] {
        AppTab.allCases.filter { !$0.isSetupSection }
    }
    
    private var setupNavTabs: [AppTab] {
        AppTab.allCases.filter { $0.isSetupSection }
    }
    
    private var shortAccountDisplayName: String {
        let raw = currentAccountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "Trading Account" else { return "Account" }
        
        var clean = raw
        let repls: [(String, String)] = [
            ("The 5%ers", "5%ers"),
            ("the5ers_", "5%ers "),
            ("account the5ers_", "5%ers "),
            ("The5ers", "5%ers"),
            ("High Stakes", "HighStakes"),
            ("HighStakes", "HighStakes"),
            ("Bootcamp", "Bootcamp"),
            ("Hyper Growth", "Growth"),
            ("Challenge", ""),
            ("Evaluation", ""),
            ("Account", ""),
            ("MetaTrader 5", "MT5"),
            ("MetaTrader 4", "MT4"),
            ("MetaTrader", "MT"),
            ("cTrader", "cTrader")
        ]
        
        for (pattern, repl) in repls {
            clean = clean.replacingOccurrences(of: pattern, with: repl, options: .caseInsensitive)
        }
        
        clean = clean.replacingOccurrences(of: " - ", with: " ")
        clean = clean.replacingOccurrences(of: "  ", with: " ")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if clean.count > 18 {
            let tokens = clean.components(separatedBy: " ").filter { !$0.isEmpty }
            if tokens.count >= 2, let t0 = tokens.first, let t1 = tokens.dropFirst().first {
                let candidate = "\(t0) \(t1)"
                if candidate.count <= 18 {
                    return candidate
                }
            }
            return String(clean.prefix(16)) + "…"
        }
        return clean.isEmpty ? "Account" : clean
    }
    
    private var currentAccountDisplayName: String {
        if let acc = dataStore.selectedAccount {
            return acc.name
        }
        if let first = dataStore.visibleAccounts.first {
            return first.name
        }
        return "Trading Account"
    }
    
    private var currentAccountBalanceFormatted: String {
        guard let acc = dataStore.selectedAccount ?? dataStore.visibleAccounts.first else {
            return "$0.00"
        }
        let curr = acc.currency.isEmpty ? "USD" : acc.currency
        return Formatters.formatCurrency(acc.initialBalance, currency: curr)
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            let isCompact = totalHeight < 740
            let rowHeight: CGFloat = isCompact ? 32 : (totalHeight < 840 ? 35 : 37)
            let iconSize: CGFloat = isCompact ? 14 : 15
            let fontSize: CGFloat = isCompact ? 12.5 : 13.5
            let itemSpacing: CGFloat = isCompact ? 1 : 2
            
            VStack(alignment: .leading, spacing: 0) {
                // Apple-Standard Sidebar Header (with top notch safe clearance)
                headerView(isCompact: isCompact)
                
                // Dedicated Hero Account Switcher & Balance Card
                accountHeroCard(isCompact: isCompact)
                
                // Dynamic spacer above Trading
                Spacer(minLength: 4)
                
                // Section 1: TRADING
                VStack(alignment: .leading, spacing: itemSpacing) {
                    sectionHeader(title: "TRADING", isCompact: isCompact)
                    
                    ForEach(mainNavTabs) { tab in
                        navRow(for: tab, height: rowHeight, iconSize: iconSize, fontSize: fontSize)
                    }
                }
                .padding(.horizontal, 10)
                
                // Dynamic spacer between Trading & Workspace
                Spacer(minLength: 4)
                
                Divider()
                    .background(AppColors.border.opacity(0.3))
                    .padding(.horizontal, 12)
                
                Spacer(minLength: 4)
                
                // Section 2: WORKSPACE
                VStack(alignment: .leading, spacing: itemSpacing) {
                    sectionHeader(title: "WORKSPACE", isCompact: isCompact)
                    
                    ForEach(setupNavTabs) { tab in
                        navRow(for: tab, height: rowHeight, iconSize: iconSize, fontSize: fontSize)
                    }
                }
                .padding(.horizontal, 10)
                
                // Dynamic spacer between Workspace & Cloudbroker Sync
                Spacer(minLength: 4)
                
                Divider()
                    .background(AppColors.border.opacity(0.3))
                    .padding(.horizontal, 12)
                
                Spacer(minLength: 4)
                
                // Section 3: CLOUD & BROKER SYNC & SYSTEM CONTROLS
                footerControlDock(isCompact: isCompact)
                    .padding(.bottom, max(AppSafeArea.bottomInset, isCompact ? 8 : 14))
            }
            .frame(width: 300, height: totalHeight)
        }
        .frame(width: 300)
        .background(
            AppColors.cardBackground
                .opacity(0.96)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
            .stroke(AppColors.border.opacity(0.4), lineWidth: 0.8)
        )
    }
    
    // MARK: - Header View (Preserving Notch & Dynamic Island Clearance)
    
    @ViewBuilder
    private func headerView(isCompact: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoMarkView(size: isCompact ? 24 : 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trade Journal")
                        .font(.system(size: isCompact ? 15 : 16, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                    
                    if dataStore.isSyncing {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                                .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                                .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: dataStore.isSyncing)
                            Text("Syncing...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.brand)
                        }
                    }
                }
                
                Spacer()
                
                // Native Apple Circular Close Button
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        env.isDrawerOpen = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: isCompact ? 26 : 28, height: isCompact ? 26 : 28)
                        .background(AppColors.secondaryBackground.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(ApplePressableButtonStyle())
                .accessibilityLabel("Close navigation drawer")
            }
            .padding(.horizontal, 16)
            #if canImport(UIKit)
            .padding(.top, max(AppSafeArea.topInset + (isCompact ? 2 : 4), isCompact ? 36 : 48))
            #else
            .padding(.top, isCompact ? 36 : 48)
            #endif
            .padding(.bottom, isCompact ? 6 : 8)
            
            Divider().background(AppColors.border.opacity(0.35))
        }
    }
    
    // MARK: - Account Switcher & Balance Hero Card
    @ViewBuilder
    private func accountHeroCard(isCompact: Bool = false) -> some View {
        Menu {
            if dataStore.visibleAccounts.count > 1 {
                Section("Switch Account") {
                    ForEach(dataStore.visibleAccounts) { acc in
                        Button {
                            triggerHaptic()
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
                }
            }
            
            Section {
                Button {
                    triggerHaptic()
                    env.selectedTab = .accounts
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        env.isDrawerOpen = false
                    }
                } label: {
                    Label("Manage Accounts...", systemImage: "creditcard")
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppColors.profit.opacity(0.18))
                        .frame(width: isCompact ? 16 : 18, height: isCompact ? 16 : 18)
                    Circle()
                        .fill(AppColors.profit)
                        .frame(width: isCompact ? 6 : 7, height: isCompact ? 6 : 7)
                }
                
                Text(shortAccountDisplayName)
                    .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Spacer(minLength: 6)
                
                Text(currentAccountBalanceFormatted)
                    .font(.system(size: isCompact ? 12 : 13, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.profit)
                    .lineLimit(1)
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .frame(height: isCompact ? 38 : 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.secondaryBackground.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.45), lineWidth: 0.8)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
        .padding(.horizontal, 10)
        .padding(.top, isCompact ? 6 : 8)
        .padding(.bottom, isCompact ? 4 : 6)
    }
    
    // MARK: - Section Header
    
    @ViewBuilder
    private func sectionHeader(title: String, isCompact: Bool = false) -> some View {
        Text(title)
            .font(.system(size: isCompact ? 10 : 10.5, weight: .bold))
            .tracking(1.0)
            .foregroundColor(AppColors.mutedText)
            .padding(.horizontal, 10)
            .padding(.top, isCompact ? 1 : 2)
            .padding(.bottom, 1)
    }
    
    // MARK: - Navigation Row (Flexible height, icon and typography)
    
    @ViewBuilder
    private func navRow(for tab: AppTab, height: CGFloat = 36, iconSize: CGFloat = 15, fontSize: CGFloat = 13.5) -> some View {
        let isActive = env.selectedTab == tab
        
        Button {
            triggerHaptic()
            if env.selectedTab == tab {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    env.isDrawerOpen = false
                }
                return
            }
            
            // Instantly update tab route (underlying view swaps immediately without layout jank)
            env.selectedTab = tab
            
            // Smoothly dismiss drawer at 120fps
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                env.isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 12) {
                // Clean SF Symbol Icon (no background box, Apple HIG standard)
                Image(systemName: isActive ? tab.selectedIconName : tab.iconName)
                    .font(.system(size: iconSize, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? AppColors.brand : AppColors.secondaryText)
                    .frame(width: 22, height: 22, alignment: .center)
                
                Text(tab.rawValue)
                    .font(.system(size: fontSize, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? AppColors.primaryText : AppColors.secondaryText)
                
                Spacer()
                
                // Active Indicator
                if isActive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.brand)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? AppColors.brand.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? AppColors.brand.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
    
    // MARK: - Footer Control Dock
    
    @ViewBuilder
    private func footerControlDock(isCompact: Bool = false) -> some View {
        VStack(spacing: isCompact ? 6 : 8) {
            // Global Quick Sync Row
            Button {
                triggerHaptic()
                Task {
                    await dataStore.performGlobalSync()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                        .foregroundColor(dataStore.isSyncing ? AppColors.brand : AppColors.secondaryText)
                        .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                        .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cloud & Broker Sync")
                            .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(dataStore.isSyncing ? "Syncing..." : SyncManager.shared.formattedLastSyncTime)
                            .font(.system(size: isCompact ? 10 : 11))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: isCompact ? 38 : 42)
                .background(AppColors.secondaryBackground.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .disabled(dataStore.isSyncing)
            
            // Inline Side-by-Side Controls (Theme + Privacy)
            HStack(spacing: 8) {
                // Theme Switcher
                Button {
                    triggerHaptic()
                    env.toggleTheme()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: env.appTheme == .dark ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 13))
                            .foregroundColor(env.appTheme == .dark ? .orange : .indigo)
                        
                        Text(env.appTheme == .dark ? "Light" : "Dark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 34 : 36)
                    .background(AppColors.secondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
                
                // Privacy Mode Toggle
                Button {
                    triggerHaptic()
                    env.togglePrivacyMode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: env.isPrivacyModeEnabled ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 13))
                            .foregroundColor(env.isPrivacyModeEnabled ? AppColors.brand : AppColors.secondaryText)
                        
                        Text(env.isPrivacyModeEnabled ? "Hidden" : "Public")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(env.isPrivacyModeEnabled ? AppColors.brand : AppColors.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? 34 : 36)
                    .background(AppColors.secondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(env.isPrivacyModeEnabled ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
            }
        }
        .padding(.horizontal, 10)
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
