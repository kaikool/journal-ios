import SwiftUI

/// Header thanh điều hướng di động chuẩn xác 100% từ `source-repo/apps/web/src/components/shell.tsx`:
/// - Nút Hamburger Drawer mở toàn bộ 13 phân hệ
/// - Logo Trade Journal vector + Nhãn "Trade Journal"
/// - Nút GlobalSyncButton (xoay tròn liên tục khi đang đồng bộ)
/// - Nút PrivacyToggle (Ẩn/Hiện số tiền)
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 10) {
            // Hamburger button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 34, height: 34)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
            }
            .accessibilityLabel("Mở danh mục điều hướng")
            
            // Brand Logo & Title
            HStack(spacing: 8) {
                TradeJournalMarkView(size: 18, color: AppColors.brand)
                
                Text("Trade Journal")
                    .font(AppTypography.pageTitle)
                    .tracking(-0.3)
                    .foregroundColor(AppColors.primaryText)
            }
            
            Spacer()
            
            // Global Sync Button (icon-only in mobile header)
            Button {
                Task {
                    if The5ersService.shared.isConfigured {
                        _ = try? await dataStore.syncWithThe5ers()
                    } else if SupabaseService.shared.isConfigured {
                        await dataStore.syncWithSupabase()
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dataStore.isSyncing ? AppColors.brand : AppColors.secondaryText)
                    .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                    .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                    .frame(width: 32, height: 32)
                    .background(AppColors.cardBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Đồng bộ dữ liệu")
            
            // Privacy Toggle Button
            Button {
                env.togglePrivacyMode()
            } label: {
                Image(systemName: env.isPrivacyModeEnabled ? "eye.slash.fill" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(env.isPrivacyModeEnabled ? AppColors.brand : AppColors.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(AppColors.cardBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Chế độ ẩn số dư")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppColors.background.opacity(0.95))
        .overlay(
            Divider().background(AppColors.border),
            alignment: .bottom
        )
    }
}
