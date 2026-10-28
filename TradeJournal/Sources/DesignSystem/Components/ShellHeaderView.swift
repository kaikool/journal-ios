import SwiftUI

/// Unified Modern Top Navigation Bar conforming to Apple Human Interface Guidelines:
/// - Brand logo emblem button as the primary drawer navigation trigger
/// - Clean, confident page identity title (18pt bold rounded typography)
/// - Quick AI Scanner action button for instant pre-trade analysis from any screen
/// - Sleek, understated Apple background with hairline bottom separator
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showPreTradeAnalysis: Bool = false
    
    public init() {}
    
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
    
    public var body: some View {
        HStack(spacing: 12) {
            // Leading: App Brand Logo Button as Drawer Menu Trigger (Enlarged per user request)
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(AppColors.secondaryBackground.opacity(0.85))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                        )
                    
                    LogoMarkView(size: 26)
                }
                .contentShape(Circle())
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Open navigation menu")
            
            // Current Page Title: Enlarged Pill Pod
            HStack(spacing: 6) {
                Text(currentTabTitle)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7.5)
            .background(AppColors.cardBackground.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.6)
            )
            
            Spacer(minLength: 8)
            
            // Trailing: Quick AI Pre-Trade Scanner Button
            aiScannerButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(Color.clear)
        .sheet(isPresented: $showPreTradeAnalysis) {
            PreTradeAnalysisSheet(initialSymbol: "XAUUSD")
        }
    }
    
    // MARK: - Trailing Action Buttons
    
    private var aiScannerButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showPreTradeAnalysis = true
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryBackground.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                
                Image(systemName: "sparkles")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(AppColors.brand)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Open AI Pre-Trade Analysis")
    }
}
