import SwiftUI

/// Trade detail view implementing Apple Human Interface Guidelines:
/// High contrast, breathable card containers, balanced 2-column metric tiles,
/// and design DNA 100% unified with DashboardView.
public struct TradeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let isModal: Bool
    @State var trade: Trade
    @State private var showReplayView: Bool = false
    @State private var showEditTradeSheet: Bool = false
    @State private var showEditTargetsSheet: Bool = false
    @State private var showAICoachSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var noteContent: String = ""
    @State private var selectedPlaybookId: String = ""
    
    public init(trade: Trade, isModal: Bool = false) {
        self.isModal = isModal
        self._trade = State(initialValue: trade)
        let cleanNote: String = {
            guard let notes = trade.notes else { return "" }
            if notes.hasPrefix("Position synced from") { return "" }
            return notes
        }()
        self._noteContent = State(initialValue: cleanNote)
        self._selectedPlaybookId = State(initialValue: trade.playbookId ?? "")
    }
    
    private var ticketDisplay: String? {
        if let firstId = trade.executionIds.first, !firstId.isEmpty {
            return Formatters.formatEntityId(firstId)
        }
        return nil
    }
    
    private var tradeDurationString: String? {
        guard let closedAt = trade.closedAt else { return "Open" }
        let diff = closedAt.timeIntervalSince(trade.openedAt)
        if diff <= 0 { return "< 1m" }
        let mins = Int(diff / 60)
        let hours = mins / 60
        let days = hours / 24
        if days > 0 {
            let remHours = hours % 24
            return remHours > 0 ? "\(days)d \(remHours)h" : "\(days)d"
        } else if hours > 0 {
            let remMins = mins % 60
            return remMins > 0 ? "\(hours)h \(remMins)m" : "\(hours)h"
        } else {
            return "\(max(1, mins))m"
        }
    }
    
    private var fills: [Execution] {
        dataStore.executions
            .filter { trade.executionIds.contains($0.id) }
            .sorted { $0.executedAt < $1.executedAt }
    }
    
    // Risk calculations
    private var riskAmount: Decimal? {
        guard let sl = trade.stopLoss, trade.avgEntry > 0, trade.quantity > 0 else { return nil }
        let gross = AssetContractEngine.calculateGrossPnl(
            symbol: trade.symbol,
            direction: trade.direction,
            quantity: trade.quantity,
            entryPrice: trade.avgEntry,
            exitPrice: sl,
            customMultiplier: AssetContractEngine.customMultiplier(for: trade.symbol, multipliers: dataStore.multipliers),
            conversionRates: dataStore.currencyConversion.rates,
            reportingCurrency: env.currentCurrency
        )
        return abs(gross)
    }
    
    private var realizedR: Decimal? {
        guard let sl = trade.stopLoss, let exit = trade.avgExit, trade.avgEntry > 0 else { return nil }
        let riskPerUnit = abs(trade.avgEntry - sl)
        guard riskPerUnit > 0 else { return nil }
        let gainPerUnit = (trade.direction == .long) ? (exit - trade.avgEntry) : (trade.avgEntry - exit)
        return gainPerUnit / riskPerUnit
    }
    
    private var plannedR: Decimal? {
        guard let sl = trade.stopLoss, let tp = trade.profitTarget, trade.avgEntry > 0 else { return nil }
        let riskPerUnit = abs(trade.avgEntry - sl)
        guard riskPerUnit > 0 else { return nil }
        let targetPerUnit = abs(tp - trade.avgEntry)
        return targetPerUnit / riskPerUnit
    }
    
    // MARK: - Main Body
    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // 1. Hero Overview Card
                TradeDetailHeroCard(
                    trade: trade,
                    durationString: tradeDurationString
                )
                
                // 2. Financial & Execution Performance (2x3 Balanced Tiles)
                TradeDetailMetricsCard(
                    trade: trade,
                    durationString: tradeDurationString,
                    ticketDisplay: ticketDisplay,
                    reportingCurrency: env.currentCurrency,
                    timeZone: env.currentTimeZone
                )
                
                // 3. Risk Management & Targets (2x2 Balanced Tiles + Visual Bar)
                TradeDetailRiskCard(
                    trade: trade,
                    riskAmount: riskAmount,
                    realizedR: realizedR,
                    plannedR: plannedR,
                    reportingCurrency: env.currentCurrency,
                    onEditTargets: { showEditTargetsSheet = true }
                )
                
                // 4. Discipline, Rating & Strategy Review
                TradeDetailDisciplineCard(
                    trade: $trade,
                    selectedPlaybookId: $selectedPlaybookId,
                    playbooks: dataStore.playbooks,
                    playbookAssessments: dataStore.playbookAssessments,
                    onUpdate: persistTradeUpdates,
                    onToggleRule: { pbId, rule, isFollowed in
                        dataStore.setRuleAssessment(
                            tradeKey: trade.key,
                            playbookId: pbId,
                            rule: rule,
                            followed: isFollowed
                        )
                    }
                )
                
                // 5. Journal Notes
                TradeDetailNotesCard(
                    noteContent: $noteContent,
                    onSave: persistTradeUpdates
                )
                
                // 6. Attachments & Screenshots
                attachmentsSection
                
                // 7. Actions (AI Coach, Replay, Edit, Delete)
                TradeDetailActionsCard(
                    isTradeOpen: trade.status == .open || trade.closedAt == nil,
                    onAICoach: { showAICoachSheet = true },
                    onReplay: { showReplayView = true },
                    onEdit: { showEditTradeSheet = true },
                    onDelete: { showDeleteAlert = true }
                )
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBarView(
                title: trade.symbol,
                showFilters: false,
                onBack: { dismiss() },
                isModal: isModal
            )
        }
        .background(AppColors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .interactiveEdgeBack(onBack: isModal ? nil : { dismiss() })
        .enableNativePopGesture()
        .sheet(isPresented: $showAICoachSheet) {
            TradeAICoachSheet(trade: trade) { updated in
                self.trade = updated
                let cleanNote: String = {
                    guard let notes = updated.notes else { return "" }
                    if notes.hasPrefix("Position synced from") { return "" }
                    return notes
                }()
                self.noteContent = cleanNote
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReplayView) {
            TradeReplayView(trade: trade, executions: fills, isModal: true)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete trade \(trade.symbol)?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete permanently", role: .destructive) {
                dataStore.deleteTrade(key: trade.key)
                dismiss()
            }
        } message: {
            Text("This trade and its associated executions will be permanently removed.")
        }
        .sheet(isPresented: $showEditTargetsSheet) {
            EditTargetsSheet(trade: trade) { updated in
                self.trade = updated
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditTradeSheet) {
            EditManualTradeSheet(trade: trade) { updated in
                self.trade = updated
                let cleanNote: String = {
                    guard let notes = updated.notes else { return "" }
                    if notes.hasPrefix("Position synced from") { return "" }
                    return notes
                }()
                self.noteContent = cleanNote
                self.selectedPlaybookId = updated.playbookId ?? ""
            }
        }
        .onChange(of: dataStore.trades) { newTrades in
            if let fresh = newTrades.first(where: { $0.key == trade.key }) {
                self.trade = fresh
            }
        }
    }
    
    // MARK: - 6. Attachments & Screenshots
    private var attachmentsSection: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("CHART SCREENSHOTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    Image(systemName: "photo.stack")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(AppColors.secondaryBackground.opacity(0.5))
                        .clipShape(Circle())
                }
                
                AttachmentsSectionView(
                    ownerType: "trade",
                    ownerId: trade.key,
                    title: ""
                )
            }
        }
    }
    
    // MARK: - Persistence Helper
    private func persistTradeUpdates() {
        let trimmedNote = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesToSave = trimmedNote.isEmpty || trimmedNote.hasPrefix("Position synced from") ? nil : trimmedNote
        
        dataStore.updateTradeAnnotations(
            key: trade.key,
            notes: notesToSave,
            tags: trade.tags,
            mistakes: trade.mistakes,
            stopLoss: trade.stopLoss,
            profitTarget: trade.profitTarget,
            rating: trade.rating,
            playbookId: selectedPlaybookId.isEmpty ? nil : selectedPlaybookId,
            reviewedAt: Date()
        )
        
        if let updated = dataStore.trades.first(where: { $0.key == trade.key }) {
            self.trade = updated
        }
    }
}
