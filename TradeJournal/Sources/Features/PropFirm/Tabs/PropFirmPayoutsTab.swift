import SwiftUI

// MARK: - Prop Firm Payouts Progress Tab
extension PropFirmLedgerView {
    // MARK: - 3. Payouts Tab
    
    internal var payoutsProgressView: some View {
        VStack(spacing: 12) {
            if payoutItems.isEmpty {
                EmptyStateView(
                    icon: "banknote",
                    title: "No payout requests",
                    message: "Track approval status, receipts and transfer fee variance for each prop firm payout."
                )
            } else {
                ForEach(payoutItems) { p in
                    cardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "banknote")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.brand)
                                    Text("\(p.entry.firm) Payout")
                                        .font(AppTypography.subheadlineBold)
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                Spacer()
                                if p.isOverdue {
                                    AppBadge(text: "Overdue", color: AppColors.loss)
                                } else if p.isPartial {
                                    AppBadge(text: "Partially received", color: AppColors.brand)
                                }
                                AppBadge(
                                    text: p.entry.status.label,
                                    color: p.entry.status == .completed ? AppColors.profit : AppColors.brand
                                )
                            }
                            
                            // Subtitle matching web prop-firm-tracker.tsx:980
                            Text("Requested \(p.entry.occurredOn) • Trader split \(p.entry.splitBps / 100)% • Gross \(Formatters.formatCurrency(Decimal(p.entry.amountMinor) / 100, currency: p.entry.currency))\(p.entry.dueOn.map { " • Expected \($0)" } ?? "")")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            // Primary Headline Amount (Received if receipts exist, or Expected Net)
                            let hasReceipt = p.actualMinor > 0
                            HStack(alignment: .firstTextBaseline) {
                                Text(hasReceipt ? "Received:" : "Expected net:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Text(Formatters.formatCurrency(Decimal(hasReceipt ? p.actualMinor : p.expectedMinor) / 100, currency: p.entry.currency))
                                    .font(AppTypography.financialNumber(size: 20, weight: .bold))
                                    .foregroundColor(hasReceipt ? AppColors.profit : AppColors.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer()
                                if hasReceipt && p.remainingMinor > 0 {
                                    Text("Remaining \(Formatters.formatCurrency(Decimal(p.remainingMinor) / 100, currency: p.entry.currency))")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(AppColors.loss)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            
                            // 4-Column Metric Details matching web prop-firm-tracker.tsx:1024-1041
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gross profit")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(p.entry.amountMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Trader split")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text("\(p.entry.splitBps / 100)%")
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .center, spacing: 2) {
                                    Text("Expected net")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(p.expectedMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Actual received")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Text(Formatters.formatCurrency(Decimal(p.actualMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(AppColors.profit)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(AppColors.secondaryBackground.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            if p.varianceMinor != 0 && p.entry.status == .completed {
                                HStack {
                                    Text("Settlement variance:")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(Formatters.formatCurrency(Decimal(p.varianceMinor) / 100, currency: p.entry.currency))
                                        .font(AppTypography.captionBold)
                                        .monospacedDigit()
                                        .foregroundColor(p.varianceMinor >= 0 ? AppColors.profit : AppColors.loss)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            
                            Divider().background(AppColors.border.opacity(0.5))
                            
                            HStack {
                                Text("Requested: \(p.entry.occurredOn)")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    selectedPayoutForReceipt = p.entry
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                        Text("Record receipt")
                                    }
                                    .font(AppTypography.actionPill)
                                    .foregroundColor(AppColors.brand)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.brand.opacity(0.12))
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
