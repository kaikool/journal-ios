import SwiftUI

/// Playbooks screen matching iOS 27 design standards:
/// - FilterBar with title "Playbooks" and "New playbook" button
/// - Empty state with Apple-standard typography and action button
/// - Interactive Playbook cards with expandable rules checklist (+ N more rules accordion)
/// - Modernized New & Edit Playbook sheets with dynamic numbered checklist rows (1, 2, 3...)
/// - Progressive disclosure: entering line 1 automatically spawns line 2
public struct PlaybooksView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showNewPlaybookSheet: Bool = false
    @State private var playbookToEdit: Playbook? = nil
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
        .sheet(item: $playbookToEdit) { pb in
            EditPlaybookSheet(playbook: pb)
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
        AppleCard {
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
                
                Text("A playbook is a setup you trade on purpose — name it, write its checklist rules, then tag trades with it and let Reports reveal its true edge.")
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
                        Image(systemName: "plus.circle.fill")
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
                PlaybookCardView(
                    summary: summary,
                    currency: env.currentCurrency,
                    onEdit: {
                        playbookToEdit = summary.playbook
                    },
                    onDelete: {
                        playbookToDelete = summary.playbook
                        showDeleteConfirmation = true
                    }
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
    
    private func tradesForPlaybook(_ playbookId: String) -> [Trade] {
        dataStore.filteredTrades.filter { $0.playbookId == playbookId }
    }
}

// MARK: - Playbook Card View (Expandable Rules Checklist)

public struct PlaybookCardView: View {
    let summary: PlaybookAdherenceSummary
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isExpanded: Bool = false
    
    public var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(AppColors.brand.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "book.pages")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.brand)
                        }
                        
                        Text(summary.playbook.title)
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
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
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText.opacity(0.7))
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(TapGesture().onEnded {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onEdit()
                    })
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onDelete()
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
                        onDelete()
                    })
                }
                
                if !summary.playbook.description.isEmpty {
                    Text(summary.playbook.description)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(2)
                }
                
                // Numbered Checklist Rules Section with Accordion
                let rules = summary.playbook.rules
                if !rules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        let displayedRules = isExpanded ? rules : Array(rules.prefix(3))
                        
                        ForEach(Array(displayedRules.enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .top, spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.brand.opacity(0.1))
                                        .frame(width: 18, height: 18)
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(AppColors.brand)
                                }
                                .padding(.top, 1)
                                
                                Text(rule)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(isExpanded ? 3 : 1)
                                
                                Spacer()
                            }
                        }
                        
                        // Expand / Collapse Pill if more than 3 rules
                        if rules.count > 3 {
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(isExpanded ? "Show less" : "+ \(rules.count - 3) more rules")
                                        .font(.system(size: 11, weight: .semibold))
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(AppColors.brand)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.brand.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(AppColors.brand.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Divider().background(AppColors.border.opacity(0.5))
                
                // Adherence summary row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("When followed")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenFollowed, currency: currency))
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenFollowed))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("When broken")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text(Formatters.formatPnL(summary.netPnlWhenBroken, currency: currency))
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

// MARK: - New Playbook Sheet (Refined Dynamic Numbered Checklist 1, 2, 3...)

public struct NewPlaybookSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var rules: [String] = [""]
    
    var onSave: (Playbook) -> Void
    
    private var validRulesCount: Int {
        rules.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Apple HIG Frosted Header
            sheetHeader
            
            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Playbook Details
                    detailsCard
                    
                    // Section 2: Numbered Rules Checklist (1, 2, 3...)
                    checklistCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
        }
    }
    
    private var sheetHeader: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .font(AppTypography.body)
            .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            Text("New Playbook")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)
            
            Spacer()
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                saveAndDismiss()
            } label: {
                Text("Create")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.brand.opacity(0.4) : AppColors.brand)
                    .foregroundColor(AppColors.brandTextOnDark)
                    .clipShape(Capsule())
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(AppColors.border.opacity(0.3))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var detailsCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    Text("STRATEGY IDENTITY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Playbook Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("e.g. London Breakout, A+ Trend Reversal", text: $title)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strategy Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("Setup conditions, context, or entry guidelines", text: $description)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
                        )
                }
            }
        }
    }
    
    private var checklistCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                        Text("CHECKLIST RULES (\(validRulesCount))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                    }
                    
                    Spacer()
                    
                    Text("Dynamic Entry")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColors.brand.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Text("Type condition in rule 1. Rule 2 will automatically appear once rule 1 has content.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // Numbered interactive rows
                VStack(spacing: 10) {
                    ForEach(Array(rules.indices), id: \.self) { index in
                        ruleInputRow(index: index)
                    }
                }
                
                // Explicit Add Rule button
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        rules.append("")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Add rule condition")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppColors.brand.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.brand.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func ruleInputRow(index: Int) -> some View {
        HStack(spacing: 10) {
            // Numbered Badge 1, 2, 3...
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.12))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.brand)
            }
            
            // Sleek text field with clear button
            HStack(spacing: 8) {
                TextField("Rule condition (e.g. Price above 200 EMA)", text: Binding(
                    get: {
                        guard index < rules.count else { return "" }
                        return rules[index]
                    },
                    set: { newVal in
                        guard index < rules.count else { return }
                        rules[index] = newVal
                        // Progressive Disclosure: If user typed in the last row, spawn next row
                        if !newVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && index == rules.count - 1 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                rules.append("")
                            }
                        }
                    }
                ))
                .font(AppTypography.body)
                .foregroundColor(AppColors.primaryText)
                
                if rules.count > 1 || (index < rules.count && !rules[index].isEmpty) {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            if index < rules.count {
                                rules.remove(at: index)
                                if rules.isEmpty {
                                    rules.append("")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
            )
        }
    }
    
    private func saveAndDismiss() {
        let parsedRules = rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let pb = Playbook(
            title: title.isEmpty ? "New Playbook" : title,
            description: description,
            rules: parsedRules
        )
        onSave(pb)
        dismiss()
    }
}

// MARK: - Edit Playbook Sheet (Refined Dynamic Numbered Checklist 1, 2, 3...)

public struct EditPlaybookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    let playbook: Playbook
    
    @State private var title: String
    @State private var description: String
    @State private var rules: [String]
    
    public init(playbook: Playbook) {
        self.playbook = playbook
        _title = State(initialValue: playbook.title)
        _description = State(initialValue: playbook.description)
        let initialRules = playbook.rules.isEmpty ? [""] : playbook.rules + [""]
        _rules = State(initialValue: initialRules)
    }
    
    private var validRulesCount: Int {
        rules.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            
            ScrollView {
                VStack(spacing: 16) {
                    detailsCard
                    checklistCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
        }
    }
    
    private var sheetHeader: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .font(AppTypography.body)
            .foregroundColor(AppColors.secondaryText)
            
            Spacer()
            
            Text("Edit Playbook")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)
            
            Spacer()
            
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                saveAndDismiss()
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.brand.opacity(0.4) : AppColors.brand)
                    .foregroundColor(AppColors.brandTextOnDark)
                    .clipShape(Capsule())
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(AppColors.border.opacity(0.3))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var detailsCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.brand)
                    Text("STRATEGY IDENTITY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Playbook Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("Playbook name", text: $title)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Strategy Description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("Setup conditions or notes", text: $description)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
                        )
                }
            }
        }
    }
    
    private var checklistCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                        Text("CHECKLIST RULES (\(validRulesCount))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)
                            .tracking(0.5)
                    }
                    
                    Spacer()
                    
                    Text("Dynamic Entry")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColors.brand.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Text("Edit conditions. Line additions happen automatically as you type in the bottom line.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                VStack(spacing: 10) {
                    ForEach(Array(rules.indices), id: \.self) { index in
                        ruleInputRow(index: index)
                    }
                }
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        rules.append("")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Add rule condition")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppColors.brand.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.brand.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(ApplePressableButtonStyle())
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func ruleInputRow(index: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.12))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.brand)
            }
            
            HStack(spacing: 8) {
                TextField("Rule condition", text: Binding(
                    get: {
                        guard index < rules.count else { return "" }
                        return rules[index]
                    },
                    set: { newVal in
                        guard index < rules.count else { return }
                        rules[index] = newVal
                        if !newVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && index == rules.count - 1 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                rules.append("")
                            }
                        }
                    }
                ))
                .font(AppTypography.body)
                .foregroundColor(AppColors.primaryText)
                
                if rules.count > 1 || (index < rules.count && !rules[index].isEmpty) {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            if index < rules.count {
                                rules.remove(at: index)
                                if rules.isEmpty {
                                    rules.append("")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.secondaryText.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.8)
            )
        }
    }
    
    private func saveAndDismiss() {
        let parsedRules = rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        dataStore.updatePlaybook(
            id: playbook.id,
            title: title.isEmpty ? playbook.title : title,
            description: description,
            rules: parsedRules
        )
        dismiss()
    }
}
