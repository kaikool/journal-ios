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
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Playbooks",
                showFilters: false
            ) {
                AppActionPill("New playbook", icon: "plus") {
                    showNewPlaybookSheet = true
                }
            }
            
            ScrollView {
                VStack(spacing: 14) {
                    if dataStore.playbooks.isEmpty {
                        emptyState
                    } else {
                        playbooksList
                    }
                }
                .padding(16)
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showNewPlaybookSheet) {
            NewPlaybookSheet { newPb in
                dataStore.savePlaybook(newPb)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
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
        cardContainer {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppColors.brand.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "book.pages")
                        .font(.system(size: 28))
                        .foregroundColor(AppColors.brand)
                }
                .padding(.top, 8)
                
                Text("Build Trading Playbooks")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Text("A playbook is a setup you trade on purpose — name it, write its rules, then tag trades with it and let Reports tell you if it actually pays.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    showNewPlaybookSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("New Playbook")
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brandTextOnDark)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ApplePressableButtonStyle())
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 16)
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
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
    
    private func tradesForPlaybook(_ playbookId: String) -> [Trade] {
        dataStore.filteredTrades.filter { $0.playbookId == playbookId }
    }
    
    private func playbookCard(summary: PlaybookAdherenceSummary) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.brand)
                        Text(summary.playbook.title)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    Spacer()
                    
                    Text("\(summary.totalTrades) trades")
                        .font(AppTypography.caption)
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        playbookToDelete = summary.playbook
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText.opacity(0.6))
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(TapGesture().onEnded {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        playbookToDelete = summary.playbook
                        showDeleteConfirmation = true
                    })
                }
                
                if !summary.playbook.description.isEmpty {
                    Text(summary.playbook.description)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                if !summary.playbook.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(summary.playbook.rules.prefix(4).enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.brand)
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
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenFollowed))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("When broken")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenBroken, currency: env.currentCurrency))
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
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
    
    // MARK: - Apple HIG Card Container
    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: playbook.title,
                showFilters: false,
                onBack: { dismiss() }
            )
            
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
        cardContainer {
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
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Checklist Rules (\(playbook.rules.count))")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.primaryText)
                
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Assigned Trades (\(trades.count))")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, 4)
            
            if trades.isEmpty {
                cardContainer {
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
        
        cardContainer {
            VStack(alignment: .leading, spacing: 8) {
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
                VStack(alignment: .leading, spacing: 6) {
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
                    .font(.system(size: 15))
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
                        .font(AppTypography.inputText)
                    TextField("One-line description", text: $description)
                        .font(AppTypography.inputText)
                }
                
                Section {
                    TextEditor(text: $rulesText)
                        .font(AppTypography.inputText)
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
