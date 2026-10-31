import SwiftUI

// MARK: - Playbook Detail View

public struct PlaybookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let playbook: Playbook
    let summary: PlaybookAdherenceSummary
    let trades: [Trade]
    var isModal: Bool = true
    
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    
    public init(
        playbook: Playbook,
        summary: PlaybookAdherenceSummary,
        trades: [Trade],
        isModal: Bool = true
    ) {
        self.playbook = playbook
        self.summary = summary
        self.trades = trades
        self.isModal = isModal
    }
    
    private var currentPlaybook: Playbook {
        dataStore.playbooks.first(where: { $0.id == playbook.id }) ?? playbook
    }
    
    private var closedTrades: [Trade] {
        trades.filter { $0.status != .open || $0.closedAt != nil }
    }
    
    private var totalNetPnl: Decimal {
        trades.reduce(Decimal.zero) { $0 + $1.netPnl }
    }
    
    private var winRate: Double? {
        let closed = closedTrades
        guard !closed.isEmpty else { return nil }
        let wins = closed.filter { $0.netPnl > 0 || $0.status == .win }.count
        return Double(wins) / Double(closed.count)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    kpiSummaryCard
                    
                    strategyChecklistCard
                    
                    PlaybookConditionEdgeChart(
                        playbook: currentPlaybook,
                        trades: trades,
                        assessments: dataStore.playbookAssessments
                    )
                    
                    deleteButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.background)
            .navigationTitle(currentPlaybook.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        ModalDeleteButton { showDeleteAlert = true }
                        ModalPrimaryButton("Edit", icon: "pencil") { showEditSheet = true }
                    }
                }
            }
        }
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
    
    // MARK: - Executive KPI Summary Card
    
    @ViewBuilder
    private var kpiSummaryCard: some View {
        AppleCard {
            HStack(alignment: .top, spacing: 0) {
                kpiCell(
                    label: "TRADES",
                    value: "\(trades.count)",
                    color: AppColors.primaryText
                )
                
                Divider()
                    .frame(height: 28)
                    .background(AppColors.border.opacity(0.35))
                
                kpiCell(
                    label: "WIN RATE",
                    value: winRate != nil ? "\(Int(winRate! * 100))%" : "–",
                    color: winRate.map { $0 >= 0.5 ? AppColors.profit : AppColors.loss } ?? AppColors.secondaryText
                )
                
                Divider()
                    .frame(height: 28)
                    .background(AppColors.border.opacity(0.35))
                
                kpiCell(
                    label: "NET P&L",
                    value: Formatters.formatPnL(totalNetPnl, currency: env.currentCurrency),
                    color: Formatters.pnlColor(totalNetPnl)
                )
                
                Divider()
                    .frame(height: 28)
                    .background(AppColors.border.opacity(0.35))
                
                kpiCell(
                    label: "ADHERENCE",
                    value: summary.rate != nil ? "\(Int(summary.rate! * 100))%" : "–",
                    color: summary.rate.map { $0 >= 0.7 ? AppColors.profit : AppColors.warning } ?? AppColors.secondaryText
                )
            }
            .padding(.vertical, 2)
        }
    }
    
    @ViewBuilder
    private func kpiCell(label: String, value: String, color: Color = AppColors.primaryText) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .tracking(0.4)
                .lineLimit(1)
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Strategy Checklist & Description Card
    
    @ViewBuilder
    private var strategyChecklistCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    
                    Text("STRATEGY CHECKLIST (\(currentPlaybook.rules.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    if currentPlaybook.isDefault {
                        Text("DEFAULT")
                            .font(AppTypography.badgeMicro)
                            .foregroundColor(AppColors.brand)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.brand.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
                if !currentPlaybook.description.isEmpty {
                    Text(currentPlaybook.description)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 2)
                }
                
                if !currentPlaybook.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(currentPlaybook.rules.enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .center, spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.brand.opacity(0.12))
                                        .frame(width: 18, height: 18)
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppColors.brand)
                                }
                                
                                Text(rule)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(2)
                                
                                Spacer(minLength: 4)
                            }
                            
                            if index < currentPlaybook.rules.count - 1 {
                                Divider().background(AppColors.border.opacity(0.25))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    // MARK: - Delete Button
    
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
                    .font(.system(size: 12, weight: .medium))
                Text("Delete Playbook")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(AppColors.loss.opacity(0.1))
            .foregroundColor(AppColors.loss)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ApplePressableButtonStyle())
        .padding(.top, 4)
    }
}
