import SwiftUI

/// Drawer thanh điều hướng chuẩn xác 100% từ `source-repo/apps/web/src/components/shell.tsx`:
/// Hỗ trợ đầy đủ 13 phân hệ, phân cách rõ ràng giữa NAV chính và NAV_SETUP,
/// kèm nút điều khiển Global Sync và Chế độ bảo mật Privacy ở chân Drawer.
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
                                
                                Text(dataStore.isSyncing ? "Đang đồng bộ..." : "Đồng bộ tất cả tài khoản")
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
                                
                                Text("Chế độ bảo mật")
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.primaryText)
                                
                                Spacer()
                                
                                Text(env.isPrivacyModeEnabled ? "BẬT" : "TẮT")
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
