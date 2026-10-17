import SwiftUI

/// Playbooks screen matching 1:1 with `source-repo/apps/web/src/app/playbooks/page.tsx`:
/// - FilterBar with title "Playbooks" and "New playbook" button
/// - Empty state: "A playbook is a setup you trade on purpose — name it, write its rules, then tag trades with it and let Reports tell you if it actually pays."
/// - Playbook cards with title, trade count, trash icon, description, numbered rules, and adherence breakdown
/// - New playbook sheet with title, description, and rules
public struct PlaybooksView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showNewPlaybookSheet: Bool = false
    @State private var playbookToDelete: Playbook? = nil
    @State private var showDeleteConfirmation: Bool = false
    
    public init() {}
    
    private var adherenceSummaries: [PlaybookAdherenceSummary] {
        AdherenceEngine.analyzeAdherence(
            playbooks: dataStore.playbooks,
            trades: dataStore.filteredTrades,
            assessments: dataStore.playbookAssessments
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Playbooks",
                showFilters: false
            ) {
                AppButton("New playbook", icon: "plus", style: .primary) {
                    showNewPlaybookSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    if dataStore.playbooks.isEmpty {
                        emptyState
                    } else {
                        playbooksList
                    }
                }
                .padding(14)
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showNewPlaybookSheet) {
            NewPlaybookSheet { newPb in
                dataStore.savePlaybook(newPb)
            }
        }
        .alert("Delete “\(playbookToDelete?.title ?? "")”?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { playbookToDelete = nil }
            Button("Delete", role: .destructive) {
                if let pb = playbookToDelete {
                    dataStore.deletePlaybook(id: pb.id)
                    playbookToDelete = nil
                }
            }
        } message: {
            Text("Trades keep their data, just lose the link.")
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.secondaryText.opacity(0.6))
                
                Text("A playbook is a setup you trade on purpose — name it, write its rules, then tag trades with it and let Reports tell you if it actually pays.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Button {
                    showNewPlaybookSheet = true
                } label: {
                    Text("New playbook")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.brandTextOnDark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColors.brand)
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var playbooksList: some View {
        ForEach(adherenceSummaries) { summary in
            let pbTrades = tradesForPlaybook(summary.playbook.id)
            NavigationLink(destination: PlaybookDetailView(
                playbook: summary.playbook,
                summary: summary,
                trades: pbTrades
            )) {
                playbookCard(summary: summary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func tradesForPlaybook(_ playbookId: String) -> [Trade] {
        dataStore.filteredTrades.filter { $0.playbookId == playbookId }
    }
    
    private func playbookCard(summary: PlaybookAdherenceSummary) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header matching playbooks/page.tsx line 73-97
                HStack(alignment: .center) {
                    Text(summary.playbook.title)
                        .font(AppTypography.bodyBold)
                        .foregroundColor(AppColors.primaryText)
                    
                    Spacer()
                    
                    Text("\(summary.totalTrades) trades")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Button {
                        playbookToDelete = summary.playbook
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                
                if !summary.playbook.description.isEmpty {
                    Text(summary.playbook.description)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                if !summary.playbook.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(summary.playbook.rules.prefix(4).enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text(rule)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Adherence summary row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("When followed")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenFollowed, currency: env.currentCurrency))
                            .font(AppTypography.captionBold)
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenFollowed))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("When broken")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenBroken, currency: env.currentCurrency))
                            .font(AppTypography.captionBold)
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenBroken))
                    }
                }
            }
        }
    }
}

// MARK: - Playbook Detail View

public struct PlaybookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let playbook: Playbook
    let summary: PlaybookAdherenceSummary
    let trades: [Trade]
    
    @State private var showDeleteAlert = false
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                infoCard
                rulesCard
                tradesSection
                deleteButton
            }
            .padding()
        }
        .navigationTitle(playbook.title)
        .background(AppColors.background)
        .alert("Delete “\(playbook.title)”? ", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dataStore.deletePlaybook(id: playbook.id)
                dismiss()
            }
        } message: {
            Text("Trades keep their data, just lose the link.")
        }
    }
    
    @ViewBuilder
    private var infoCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Strategy Description")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                Text(playbook.description.isEmpty ? "No description provided." : playbook.description)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primaryText)
            }
        }
    }
    
    @ViewBuilder
    private var rulesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Checklist Rules (\(playbook.rules.count))")
                    .font(AppTypography.headline)
                
                ForEach(Array(playbook.rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.brand)
                        Text(rule)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                    }
                    if index < playbook.rules.count - 1 {
                        Divider().background(AppColors.border.opacity(0.4))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assigned Trades (\(trades.count))")
                .font(AppTypography.headline)
                .padding(.horizontal, 4)
            
            if trades.isEmpty {
                Text("No trades currently assigned to this playbook.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, 4)
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
        
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(trade.symbol)
                        .font(AppTypography.subheadlineBold)
                    AppBadge(
                        trade.direction.rawValue.uppercased(),
                        color: dirColor
                    )
                    Spacer()
                    Text(Formatters.formatPnL(trade.netPnl, currency: env.currentCurrency))
                        .font(AppTypography.subheadlineBold)
                        .foregroundColor(Formatters.pnlColor(trade.netPnl))
                }
                
                // Rule checkboxes for this trade
                VStack(alignment: .leading, spacing: 4) {
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
        
        HStack {
            Image(systemName: followed ? "checkmark.square.fill" : "square")
                .foregroundColor(followed ? AppColors.profit : AppColors.secondaryText)
                .onTapGesture {
                    dataStore.setRuleAssessment(tradeKey: trade.key, playbookId: playbook.id, rule: rule, followed: !followed)
                }
            Text(rule)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.primaryText)
        }
    }
    
    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive, action: { showDeleteAlert = true }) {
            HStack {
                Image(systemName: "trash")
                Text("Delete Playbook")
            }
            .font(AppTypography.captionBold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppColors.loss.opacity(0.1))
            .foregroundColor(AppColors.loss)
            .cornerRadius(12)
        }
        .padding(.top, 8)
    }
}

// MARK: - New Playbook Sheet

public struct NewPlaybookSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var rulesText: String = ""
    
    var onSave: (Playbook) -> Void
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Playbook Details") {
                    TextField("Name (e.g. Opening range breakout)", text: $title)
                    TextField("One-line description", text: $description)
                }
                
                Section {
                    TextEditor(text: $rulesText)
                        .frame(minHeight: 120)
                } header: {
                    Text("Checklist Rules")
                } footer: {
                    Text("One rule per line:\nOnly A+ setups\nRisk max 1R\nNo entries after 11:30")
                }
            }
            .navigationTitle("New playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let parsedRules = rulesText
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        
                        let pb = Playbook(
                            title: title.isEmpty ? "New Playbook" : title,
                            description: description,
                            rules: parsedRules
                        )
                        onSave(pb)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
