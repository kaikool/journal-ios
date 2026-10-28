import SwiftUI

// MARK: - Prop Firm Transactions & Fees Tab
extension PropFirmLedgerView {
    // MARK: - 4. Transactions Tab
    
    internal var transactionsListView: some View {
        VStack(spacing: 12) {
            if movements.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right",
                    title: "No cash movements",
                    message: "Evaluation fees, refunds, and payout receipts will appear here."
                )
            } else {
                ForEach(movements) { m in
                    cardContainer {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(m.firm)
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    let badgeLabel: String = {
                                        if m.kind == "refund" { return "Fee Refund" }
                                        if m.kind == "receipt" || m.kind == "payout" { return "Payout" }
                                        switch m.category.lowercased() {
                                        case "evaluation", "program": return "Evaluation Fee"
                                        case "reset": return "Reset Fee"
                                        case "activation": return "Activation Fee"
                                        case "subscription": return "Subscription"
                                        default: return "Evaluation Fee"
                                        }
                                    }()
                                    let badgeColor: Color = {
                                        if m.kind == "refund" { return AppColors.brand }
                                        if m.kind == "receipt" || m.kind == "payout" { return AppColors.profit }
                                        switch m.category.lowercased() {
                                        case "evaluation", "program", "activation": return AppColors.brand
                                        case "reset": return AppColors.warning
                                        default: return AppColors.secondaryText
                                        }
                                    }()
                                    AppBadge(text: badgeLabel, color: badgeColor)
                                }
                                
                                if m.kind == "refund" {
                                    Text("Refund of evaluation fee from prop firm")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                } else if let entry = dataStore.propEntries.first(where: { $0.id == m.entryId }), !entry.notes.isEmpty {
                                    let cleanNote = Formatters.cleanTransactionNote(entry.notes.components(separatedBy: "\n").first ?? entry.notes)
                                    if !cleanNote.isEmpty {
                                        Text(cleanNote)
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.primaryText)
                                            .lineLimit(1)
                                    }
                                }
                                
                                HStack(spacing: 6) {
                                    Text(Formatters.formatDisplayDate(m.date))
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    
                                    if !m.reference.isEmpty {
                                        Text("•")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.secondaryText.opacity(0.5))
                                        Text(Formatters.formatReference(m.reference))
                                            .font(AppTypography.number(11, weight: .medium))
                                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 6) {
                                let isIncoming = m.kind == "receipt" || m.kind == "refund"
                                let amountDecimal = Decimal(m.amountMinor) / 100
                                Text("\(isIncoming ? "+" : "-")\(Formatters.formatCurrency(amountDecimal, currency: m.currency))")
                                    .font(AppTypography.subheadlineBold)
                                    .monospacedDigit()
                                    .foregroundColor(isIncoming ? AppColors.profit : AppColors.loss)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                HStack(spacing: 8) {
                                    if m.kind == "expense" {
                                        Button {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            if let entry = dataStore.propEntries.first(where: { $0.id == m.entryId }) {
                                                selectedExpenseForRefund = entry
                                            }
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "arrow.counterclockwise")
                                                    .font(.system(size: 10))
                                                Text("Fee refund")
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppColors.brand)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
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
                                        itemToVoid = (id: m.entryId, isEntry: true)
                                        showVoidAlert = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.loss.opacity(0.8))
                                            .padding(6)
                                            .background(AppColors.secondaryBackground)
                                            .clipShape(Circle())
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
