import SwiftUI

/// Navigation drawer matching 100% of `source-repo/apps/web/src/components/shell.tsx`:
/// Supports all 13 application routes divided into primary NAV and NAV_SETUP sections,
/// with Global Sync, Theme switch, and Privacy controls in the drawer footer.
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
        ZStack(alignment: .leading) {
            // Blurred dark overlay
            if env.isDrawerOpen {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            env.isDrawerOpen = false
                        }
                    }
                    .transition(.opacity)
                
                // Slide-out Drawer Panel
                VStack(alignment: .leading, spacing: 0) {
                    // Drawer Header
                    HStack(spacing: 10) {
                        TradeJournalMarkView(size: 20, color: AppColors.brand)
                        
                        Text("Trade Journal")
                            .font(AppTypography.pageTitle)
                            .foregroundColor(AppColors.primaryText)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                env.isDrawerOpen = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 30, height: 30)
                                .background(AppColors.secondaryBackground)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(
                        Divider().background(AppColors.border),
                        alignment: .bottom
                    )
                    
                    // Nav Items Scroll
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(mainNavTabs) { tab in
                                navRow(for: tab)
                            }
                            
                            Divider()
                                .background(AppColors.border)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                            
                            ForEach(setupNavTabs) { tab in
                                navRow(for: tab)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                    }
                    
                    // Drawer Bottom Footer
                    VStack(spacing: 8) {
                        Divider().background(AppColors.border)
                        
                        // Global Sync Action Row
                        Button {
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
                                    .font(.system(size: 14))
                                    .foregroundColor(dataStore.isSyncing ? AppColors.brand : AppColors.secondaryText)
                                    .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                                    .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                                
                                Text(dataStore.isSyncing ? "Syncing..." : "Sync all accounts")
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                        
                        // Theme Mode Action Row
                        Button {
                            env.toggleTheme()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: env.appTheme == .dark ? "sun.max" : "moon")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.secondaryText)
                                
                                Text(env.appTheme == .dark ? "Light mode" : "Dark mode")
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                        
                        // Privacy Mode Action Row
                        Button {
                            env.togglePrivacyMode()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: env.isPrivacyModeEnabled ? "eye.slash.fill" : "eye")
                                    .font(.system(size: 14))
                                    .foregroundColor(env.isPrivacyModeEnabled ? AppColors.brand : AppColors.secondaryText)
                                
                                Text("Privacy mode")
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Spacer()
                                
                                Text(env.isPrivacyModeEnabled ? "ON" : "OFF")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(env.isPrivacyModeEnabled ? AppColors.brand : AppColors.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .frame(width: min(UIScreen.main.bounds.width - 50, 280))
                .background(AppColors.cardBackground)
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(AppColors.border),
                    alignment: .trailing
                )
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if value.translation.width < -30 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    env.isDrawerOpen = false
                                }
                            }
                        }
                )
                .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: env.isDrawerOpen)
    }
    
    private func navRow(for tab: AppTab) -> some View {
        let isActive = env.selectedTab == tab
        
        return Button {
            env.selectedTab = tab
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                env.isDrawerOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? AppColors.brand : AppColors.secondaryText)
                    .frame(width: 22)
                
                Text(tab.rawValue)
                    .font(isActive ? AppTypography.bodyBold : AppTypography.bodyMedium)
                    .foregroundColor(isActive ? AppColors.primaryText : AppColors.secondaryText)
                
                Spacer()
                
                if isActive {
                    Circle()
                        .fill(AppColors.brand)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? AppColors.secondaryBackground : Color.clear)
            .cornerRadius(6)
        }
    }
}
