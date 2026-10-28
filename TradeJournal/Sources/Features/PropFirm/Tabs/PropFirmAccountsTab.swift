import SwiftUI

// MARK: - Prop Firm Accounts Tab & Cash Summary
extension PropFirmLedgerView {
    // MARK: - 2. Accounts Tab
    
    internal func accountCashSummary(account: PropAccountItem) -> CashSummaryResult {
        let accClean = account.id.cleanAccountId
        let accCurr = account.currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let accMovements = movements.filter { mov in
            let movCurr = mov.currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard movCurr == accCurr || (movCurr.isEmpty && (accCurr == "USD" || accCurr.isEmpty)) else { return false }
            
            if let mAccId = mov.accountId, !mAccId.isEmpty {
                return mAccId == account.id ||
                       mAccId == account.journalAccountId ||
                       TradeDataStore.isSameAccountId(mAccId, account.id) ||
                       (account.journalAccountId.map { TradeDataStore.isSameAccountId(mAccId, $0) } ?? false) ||
                       mAccId.cleanAccountId == accClean
            }
            return false
        }
        return (try? PropFirmEngine.cashSummary(rows: accMovements)) ?? CashSummaryResult(
            spentMinor: 0, refundsMinor: 0, netSpendMinor: 0, receivedMinor: 0, netMinor: 0, roi: nil
        )
    }
    
    internal var accountsListView: some View {
        VStack(spacing: 12) {
            if filteredAccounts.isEmpty {
                EmptyStateView(
                    icon: "building.columns",
                    title: selectedAccountStatus == .all ? "No prop accounts" : "No \(selectedAccountStatus.rawValue.lowercased()) prop accounts",
                    message: "Tap 'Track account' above to add your Topstep, FTMO, The5ers accounts."
                )
            } else {
                ForEach(filteredAccounts) { acc in
                    cardContainer(isActive: acc.status == .active) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "building.columns")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text(acc.firm)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                }
                                
                                if acc.archived {
                                    Text("Archived")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.secondaryBackground)
                                        .clipShape(Capsule())
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                AppBadge(
                                    text: acc.status.label,
                                    color: acc.status == .active || acc.status == .passed ? AppColors.profit : AppColors.loss
                                )
                            }
                            
                            Text(Formatters.cleanAccountName(acc.name, balance: acc.sizeMinor.map { Decimal($0) / 100 }))
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if let parentId = acc.parentId, let parentAcc = dataStore.propAccounts.first(where: { $0.id == parentId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.brand)
                                    Text("Next phase of: \(Formatters.cleanAccountName(parentAcc.name))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(AppColors.brand)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            
                            HStack {
                                if let size = acc.sizeMinor {
                                    Text("Initial Size: \(Formatters.formatCurrency(Decimal(size) / 100, currency: acc.currency))")
                                        .font(AppTypography.caption)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(acc.currentStepName ?? acc.program.label)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            // 3-Column Account Balance, Equity & Net P&L (Authoritative MCP Account State)
                            let balMinor = acc.balanceMinor ?? acc.sizeMinor ?? 0
                            let eqMinor = acc.equityMinor ?? balMinor
                            let pnlMinor: Int64 = {
                                if let np = acc.netPnlMinor { return np }
                                if let b = acc.balanceMinor, let s = acc.sizeMinor, s > 0 { return b - s }
                                return 0
                            }()
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("BALANCE")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .tracking(0.5)
                                    Text(Formatters.formatCurrency(Decimal(balMinor) / 100, currency: acc.currency))
                                        .font(AppTypography.financialNumber(size: 16, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                VStack(alignment: .center, spacing: 3) {
                                    Text("EQUITY")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .tracking(0.5)
                                    Text(Formatters.formatCurrency(Decimal(eqMinor) / 100, currency: acc.currency))
                                        .font(AppTypography.financialNumber(size: 16, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("NET P&L")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .tracking(0.5)
                                    let isNetPos = pnlMinor >= 0
                                    Text("\(isNetPos && pnlMinor > 0 ? "+" : "")\(Formatters.formatCurrency(Decimal(pnlMinor) / 100, currency: acc.currency))")
                                        .font(AppTypography.financialNumber(size: 16, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(pnlMinor == 0 ? AppColors.primaryText : (isNetPos ? AppColors.profit : AppColors.loss))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(AppColors.secondaryBackground.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            
                            // Program Rules, Stop Loss & Progression (Visual Objective Charts & Risk Shields)
                            let hasProgramDetails = acc.profitTargetMinor != nil || acc.maxLossMinor != nil || acc.maxDailyLossMinor != nil || acc.winningDays != nil || acc.minTradingDays != nil || acc.currentStepName != nil || acc.totalTrades != nil
                            if acc.status == .active || hasProgramDetails {
                                PropAccountObjectivesChartCard(acc: acc)
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            // 2-row footer layout: prevents button text wrapping on small screens
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Text("Opened: \(acc.openedOn)")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    if let closed = acc.closedOn {
                                        Text("• Closed: \(closed)")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                
                                HStack(spacing: 8) {
                                    Spacer()
                                    
                                    if acc.status == .passed || acc.status == .breached || acc.status == .closed {
                                        Button {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            selectedAccountForNextPhase = acc
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.right.circle")
                                                Text("Next phase")
                                            }
                                            .font(AppTypography.actionPill)
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(AppColors.brand.opacity(0.12))
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                        }
                                        .buttonStyle(ApplePressableButtonStyle())
                                    }
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        selectedAccountForEdit = acc
                                    } label: {
                                        Text("Edit")
                                            .font(AppTypography.actionPill)
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(AppColors.secondaryBackground)
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                        }
                                    .buttonStyle(ApplePressableButtonStyle())
                                    
                                    Button {
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                        dataStore.archivePropAccount(id: acc.id, archived: !acc.archived, reason: "User toggle archive")
                                    } label: {
                                        Text(acc.archived ? "Restore" : "Archive")
                                            .font(AppTypography.actionPill)
                                            .foregroundColor(AppColors.secondaryText)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(AppColors.secondaryBackground)
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .buttonStyle(ApplePressableButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
}
