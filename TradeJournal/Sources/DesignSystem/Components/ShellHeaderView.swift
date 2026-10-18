import SwiftUI

/// Mobile navigation header matching 100% of `source-repo/apps/web/src/components/shell.tsx`:
/// - Drawer hamburger button opening all 13 application routes
/// - Trade Journal vector mark + "Trade Journal" title
/// - GlobalSyncButton (continuous rotation spinner during synchronization)
/// - PrivacyToggle (hide / unhide financial balances)
/// - ThemeToggle (toggle between dark and light appearance)
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            // Hamburger button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(AppColors.cardBackground.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Toggle navigation drawer")
            
            // Brand Logo & Title (matching web Link href="/")
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                env.selectedTab = .dashboard
            } label: {
                HStack(spacing: 8) {
                    TradeJournalMarkView(size: 20, color: AppColors.brand)
                    
                    Text("Trade Journal")
                        .font(AppTypography.pageTitle)
                        .tracking(-0.3)
                        .foregroundColor(AppColors.primaryText)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Global Sync Button (icon-only in mobile header)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                Task {
                    await dataStore.performGlobalSync()
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(dataStore.isSyncing ? AppColors.brand : AppColors.secondaryText)
                    .rotationEffect(dataStore.isSyncing ? .degrees(360) : .zero)
                    .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                    .frame(width: 36, height: 36)
                    .background(AppColors.cardBackground.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Sync accounts")
            
            // Privacy Toggle Button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                env.togglePrivacyMode()
            } label: {
                Image(systemName: env.isPrivacyModeEnabled ? "eye.slash.fill" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(env.isPrivacyModeEnabled ? AppColors.brand : AppColors.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(AppColors.cardBackground.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Toggle privacy mode")
            
            // Theme Toggle Button (Light / Dark mode)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                env.toggleTheme()
            } label: {
                Image(systemName: env.appTheme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(AppColors.cardBackground.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Toggle theme")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(AppColors.border.opacity(0.4)),
            alignment: .bottom
        )
    }
}

