import SwiftUI

/// Standardized Apple HIG Account Card displaying status, broker badges, balance, and action controls
public struct AccountCardView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    public let account: Account
    public let tradeCount: Int
    public var onEdit: () -> Void
    public var onDelete: () -> Void
    
    public init(
        account: Account,
        tradeCount: Int,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.account = account
        self.tradeCount = tradeCount
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    public var body: some View {
        let isSelected = dataStore.selectedAccountId == account.id
        let isArchived = account.archivedAt != nil
        let isVisible = dataStore.isAccountVisible(account)
        
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Journal visibility toggle button
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        dataStore.toggleAccountVisibility(id: account.id)
                    } label: {
                        Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(isVisible ? AppColors.brand : AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(Formatters.cleanAccountName(account.name, balance: account.initialBalance))
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if isSelected {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(AppColors.profit)
                                    .font(.system(size: 13))
                            }
                        }
                        
                        Text("\(account.broker.isEmpty ? "Standard" : account.broker) · \(account.currency)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Primary active view button
                    if !isSelected {
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            dataStore.selectAccount(id: account.id)
                        } label: {
                            Text("Select")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(AppColors.brand.opacity(0.12))
                                .foregroundColor(AppColors.brand)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                        .fixedSize()
                    } else {
                        Text("Viewing")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(AppColors.profit.opacity(0.15))
                            .foregroundColor(AppColors.profit)
                            .clipShape(Capsule())
                            .fixedSize()
                    }
                }
                
                // Badges
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        let prop = dataStore.propAccount(for: account)
                        let isProp = dataStore.isPropAccount(account)
                        
                        if isArchived {
                            badgeView("Archived", color: AppColors.secondaryText)
                        } else if isProp {
                            if let p = prop {
                                switch p.status {
                                case .active:
                                    badgeView("Active", color: AppColors.profit)
                                case .passed:
                                    badgeView("Passed", color: Color.blue)
                                case .breached:
                                    badgeView("Breached", color: AppColors.loss)
                                case .closed:
                                    badgeView("Closed", color: AppColors.secondaryText)
                                case .inactive:
                                    badgeView("Inactive", color: AppColors.secondaryText)
                                }
                            } else {
                                if dataStore.isAccountActive(account) {
                                    badgeView("Active", color: AppColors.profit)
                                } else {
                                    badgeView("Inactive", color: AppColors.secondaryText)
                                }
                            }
                        } else {
                            badgeView("Active", color: AppColors.profit)
                        }
                        
                        // Prop Program / Phase badge
                        if let prog = prop?.program.label ?? account.propProgram?.capitalized, !prog.isEmpty {
                            badgeView(prog, color: AppColors.brand)
                        }
                        
                        if !account.broker.isEmpty {
                            badgeView(account.broker, color: AppColors.brand)
                        }
                        
                        badgeView(account.kind.rawValue.uppercased(), color: AppColors.secondaryText)
                        badgeView(account.profitCalcMethod.rawValue.uppercased(), color: AppColors.secondaryText)
                        
                        if account.autoSync {
                            badgeView("Auto-sync", color: AppColors.profit)
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Balance and Trades Info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Initial Balance")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                        Text(Formatters.formatCurrency(account.initialBalance, currency: account.currency))
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Trades")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                        Text("\(tradeCount) trades")
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Action row
                HStack(spacing: 12) {
                    Toggle("Auto-sync", isOn: Binding(
                        get: { account.autoSync },
                        set: { _ in dataStore.toggleAccountAutoSync(id: account.id) }
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .tint(AppColors.brand)
                    
                    Spacer()
                    
                    // Edit Account
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    // Archive / Restore
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        dataStore.archiveAccount(id: account.id, archived: !isArchived)
                    } label: {
                        Image(systemName: "tray.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                    
                    // Delete
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.loss.opacity(0.8))
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
        }
        .opacity(isArchived ? 0.65 : 1.0)
    }
    
    private func badgeView(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
