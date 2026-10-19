import SwiftUI

/// Unified Modern Top Navigation Bar:
/// - Drawer hamburger trigger button with micro-spring animation
/// - Brand logo mark & title
/// - Interactive Account Selector Capsule Chip with direct switching menu
/// - Quick Add Trade button (+) with primary brand styling
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @State private var showAddTradeSheet: Bool = false
    
    public init() {}
    
    private var currentAccountName: String {
        if dataStore.selectedAccountId == "all" {
            let count = dataStore.visibleAccounts.count
            return count > 0 ? "All (\(count))" : "All Accounts"
        }
        if let acc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId }) {
            return Formatters.cleanAccountName(acc.name)
        }
        return "Select Account"
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Leading: Hamburger Drawer Menu Trigger
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
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Toggle navigation drawer")
            
            // Brand Logo & Title Link
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                env.selectedTab = .dashboard
            } label: {
                HStack(spacing: 7) {
                    TradeJournalMarkView(size: 20, color: AppColors.brand)
                    
                    Text("Trade Journal")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(-0.3)
                        .foregroundColor(AppColors.primaryText)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Center-Right: Interactive Account Selector Capsule Chip
            Menu {
                Button {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    dataStore.selectAccount(id: "all")
                } label: {
                    HStack {
                        Text("All Accounts (\(dataStore.visibleAccounts.count))")
                        if dataStore.selectedAccountId == "all" {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
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
                        .fill(dataStore.selectedAccountId == "all" ? AppColors.brand : AppColors.profit)
                        .frame(width: 6, height: 6)
                    
                    Text(currentAccountName)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppColors.secondaryText.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.cardBackground.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Select Trading Account")
            
            // Trailing: Quick Add Trade Pill Button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                showAddTradeSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(AppColors.buttonText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.brand)
                .clipShape(Capsule())
                .shadow(color: AppColors.brand.opacity(0.24), radius: 4, x: 0, y: 1.5)
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Quick Add Trade")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(AppColors.border.opacity(0.4)),
            alignment: .bottom
        )
        .sheet(isPresented: $showAddTradeSheet) {
            AddTradeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }
}
