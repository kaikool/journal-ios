import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Navigation drawer matching Apple iOS Design Guidelines & Web Shell Parity:
/// - Native Apple `.ultraThinMaterial` frosted glass translucency
/// - Dynamic continuous curvature edge (24pt trailing radius) with elevation shadow
/// - Clean, unboxed SF Symbol icons following Apple HIG standard
/// - Crisp brand vector mark without double background wrappers
/// - Professional active account subtitle (no unprofessional "online v1.0" tag)
/// - Glass control dock at bottom: Cloud sync action, Theme mode toggle, and Privacy toggle
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
    
    private var activeAccountScope: String {
        if dataStore.isSyncing {
            return "Syncing..."
        }
        if dataStore.selectedAccountId == "all" {
            return "All accounts"
        }
        if let acc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId || TradeDataStore.isSameAccountId($0.id, dataStore.selectedAccountId) }) {
            return Formatters.cleanAccountName(acc.name, balance: acc.initialBalance)
        }
        if let first = dataStore.visibleAccounts.first {
            return Formatters.cleanAccountName(first.name, balance: first.initialBalance)
        }
        return "Trading Terminal"
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Apple-Standard Sidebar Header
            headerView
            
            // Sectioned Navigation List
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Section 1: TRADING
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader(title: "TRADING")
                        
                        ForEach(mainNavTabs) { tab in
                            navRow(for: tab)
                        }
                    }
                    
                    // Section 2: WORKSPACE & SETUP
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader(title: "WORKSPACE")
                        
                        ForEach(setupNavTabs) { tab in
                            navRow(for: tab)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
            }
            
            // Bottom Glass Control Dock
            footerControlDock
        }
        .frame(width: 300)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                AppColors.cardBackground
                    .opacity(0.88)
            }
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
            .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
        )
    }
    
    // MARK: - Header View
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Standalone Brand Vector Mark (Zero enclosing background box)
                LogoMarkView(size: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trade Journal")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
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
                    } else {
                        Text(activeAccountScope)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(AppColors.secondaryBackground.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(ApplePressableButtonStyle())
                .accessibilityLabel("Close navigation drawer")
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            .padding(.bottom, 14)
            
            Divider().background(AppColors.border.opacity(0.4))
        }
    }
    
    // MARK: - Section Header
    
    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(AppColors.mutedText)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
    
    // MARK: - Navigation Row (44pt Apple HIG Standard, Clean Icon Without Boxes)
    
    @ViewBuilder
    private func navRow(for tab: AppTab) -> some View {
        let isActive = env.selectedTab == tab
        
        Button {
            triggerHaptic()
            if env.selectedTab == tab {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    env.isDrawerOpen = false
                }
                return
            }
            
            // 1. Switch tab immediately
            env.selectedTab = tab
            
            // 2. Close drawer smoothly
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                env.isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 12) {
                // Clean SF Symbol Icon (no background box, Apple HIG standard)
                Image(systemName: isActive ? tab.selectedIconName : tab.iconName)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? AppColors.brand : AppColors.secondaryText)
                    .frame(width: 24, height: 24, alignment: .center)
                
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? AppColors.primaryText : AppColors.secondaryText)
                
                Spacer()
                
                // Trailing Badges or Active Indicator
                if isActive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.brand)
                } else if tab == .trades && !dataStore.trades.isEmpty {
                    Text("\(dataStore.trades.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.secondaryBackground.opacity(0.6))
                        .clipShape(Capsule())
                } else if tab == .accounts && !dataStore.accounts.isEmpty {
                    Text("\(dataStore.accounts.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.secondaryBackground.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
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
    private var footerControlDock: some View {
        VStack(spacing: 8) {
            Divider().background(AppColors.border.opacity(0.4))
            
            VStack(spacing: 8) {
                // Global Sync Center Row
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        env.isDrawerOpen = false
                    }
                    env.showSyncCenter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(dataStore.isSyncing ? AppColors.brand : AppColors.secondaryText)
                            .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                            .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sync Center")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            
                            Text(dataStore.isSyncing ? "Synchronizing..." : "Multi-source sync & filters")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.secondaryBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
                
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
                        .frame(height: 36)
                        .background(AppColors.secondaryBackground.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                        .frame(height: 36)
                        .background(AppColors.secondaryBackground.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(env.isPrivacyModeEnabled ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }
    
    private func triggerHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
