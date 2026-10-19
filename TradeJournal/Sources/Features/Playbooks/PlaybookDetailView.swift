import SwiftUI

// MARK: - Playbook Detail View

public struct PlaybookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let playbook: Playbook
    let summary: PlaybookAdherenceSummary
    let trades: [Trade]
    
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    
    private var currentPlaybook: Playbook {
        dataStore.playbooks.first(where: { $0.id == playbook.id }) ?? playbook
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: currentPlaybook.title,
                showFilters: false,
                onBack: { dismiss() }
            ) {
                AppActionPill("Edit", icon: "pencil") {
                    showEditSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 14) {
                    infoCard
                    rulesCard
                    tradesSection
                    deleteButton
                }
                .padding(16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveEdgeBack(onBack: { dismiss() })
        .enableNativePopGesture()
        .background(AppColors.background)
        .sheet(isPresented: $showEditSheet) {
            EditPlaybookSheet(playbook: currentPlaybook)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .alert("Delete “\(currentPlaybook.title)”? ", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dataStore.deletePlaybook(id: currentPlaybook.id)
                dismiss()
            }
        } message: {
            Text("Trades keep their data, just lose the link.")
        }
    }
    
    @ViewBuilder
    private var infoCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("STRATEGY DESCRIPTION")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                    .tracking(0.5)
                
                Text(currentPlaybook.description.isEmpty ? "No description provided." : currentPlaybook.description)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
            }
        }
    }
    
    @ViewBuilder
    private var rulesCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    
                    Text("CHECKLIST CONDITIONS (\(currentPlaybook.rules.count))")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                        .tracking(0.3)
                    
                    Spacer()
                }
                
                ForEach(Array(currentPlaybook.rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppColors.brand.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(AppColors.brand)
                        }
                        
                        Text(rule)
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.primaryText)
                        
                        Spacer()
                    }
                    
                    if index < currentPlaybook.rules.count - 1 {
                        Divider().background(AppColors.border.opacity(0.35))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assigned Trades (\(trades.count))")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 4)
            
            if trades.isEmpty {
                AppleCard {
                    Text("No trades currently assigned to this playbook.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            } else {
                ForEach(trades) { trade in
                    tradeCard(trade)
                }
            }
        }
    }
    
    @ViewBuilder
    private func tradeCard(_ trade: Trade) -> some View {
        let isLong = trade.direction == .long
        let dirColor = isLong ? AppColors.brand : AppColors.warning
        
        AppleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(trade.symbol)
                        .font(AppTypography.subheadlineBold)
                        .foregroundColor(AppColors.primaryText)
                    AppBadge(
                        trade.direction.rawValue.uppercased(),
                        color: dirColor
                    )
                    Spacer()
                    Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                        .font(AppTypography.subheadlineBold)
                        .monospacedDigit()
                        .foregroundColor(Formatters.pnlColor(trade.netPnl))
                }
                
                // Rule checkboxes for this trade
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(playbook.rules, id: \.self) { rule in
                        ruleCheckboxRow(trade: trade, rule: rule)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func ruleCheckboxRow(trade: Trade, rule: String) -> some View {
        let followed = dataStore.playbookAssessments.first(where: {
            $0.tradeKey == trade.key && $0.playbookId == playbook.id && $0.rule == rule
        })?.followed ?? false
        
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            dataStore.setRuleAssessment(tradeKey: trade.key, playbookId: playbook.id, rule: rule, followed: !followed)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: followed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(followed ? AppColors.profit : AppColors.secondaryText)
                    .font(.system(size: 16))
                Text(rule)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var deleteButton: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showDeleteAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Delete Playbook")
            }
            .font(AppTypography.captionBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.loss.opacity(0.12))
            .foregroundColor(AppColors.loss)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ApplePressableButtonStyle())
        .padding(.top, 4)
    }
}
