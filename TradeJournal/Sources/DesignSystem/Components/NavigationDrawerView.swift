import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Navigation drawer matching Apple iOS Design Guidelines & Web Shell Parity:
/// - Native Apple `.ultraThinMaterial` frosted glass translucency
/// - Dynamic continuous curvature edge (24pt trailing radius) with elevation shadow
/// - Distinct section headers ("TRADING" & "WORKSPACE") with 44pt Apple touch targets
/// - SF Symbol icon badges with active brand accents and subtle status chevrons
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
            .stroke(AppColors.border.opacity(0.7), lineWidth: 1)
        )
    }
    
    // MARK: - Header View
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // App Logo Icon with subtle gradient glow
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.brand, AppColors.brand.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: AppColors.brand.opacity(0.35), radius: 6, x: 0, y: 3)
                    
                    TradeJournalMarkView(size: 20, color: .white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trade Journal")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.primaryText)
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(dataStore.isSyncing ? AppColors.brand : AppColors.profit)
                            .frame(width: 6, height: 6)
                        
                        Text(dataStore.isSyncing ? "Syncing..." : "Online · v1.0")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
                
                Spacer()
                
                // Native Apple Circular Close Button
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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
                .accessibilityLabel("Close navigation drawer")
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            .padding(.bottom, 14)
            
            Divider().background(AppColors.border.opacity(0.6))
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
    
    // MARK: - Navigation Row (44pt Apple HIG Standard)
    
    @ViewBuilder
    private func navRow(for tab: AppTab) -> some View {
        let isActive = env.selectedTab == tab
        
        Button {
            triggerHaptic()
            env.selectedTab = tab
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                env.isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 12) {
                // SF Symbol Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? AppColors.brand : AppColors.secondaryBackground.opacity(0.7))
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: tab.iconName)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .white : AppColors.secondaryText)
                }
                
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
                        .cornerRadius(6)
                } else if tab == .accounts && !dataStore.accounts.isEmpty {
                    Text("\(dataStore.accounts.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.secondaryBackground.opacity(0.6))
                        .cornerRadius(6)
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
            Divider().background(AppColors.border.opacity(0.6))
            
            VStack(spacing: 8) {
                // Global Cloud Sync Row
                Button {
                    triggerHaptic()
                    Task {
                        if The5ersService.shared.isConfigured {
                            _ = try? await dataStore.syncWithThe5ers()
                        } else if SupabaseService.shared.isConfigured {
                            await dataStore.syncWithSupabase()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(dataStore.isSyncing ? AppColors.brand : AppColors.secondaryText)
                            .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                            .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sync Accounts")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            
                            Text(dataStore.isSyncing ? "Syncing with cloud..." : (The5ersService.shared.isConfigured ? "The5ers Connected" : "Supabase Cloud"))
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.secondaryBackground.opacity(0.6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                
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
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.border.opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    
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
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(env.isPrivacyModeEnabled ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
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
