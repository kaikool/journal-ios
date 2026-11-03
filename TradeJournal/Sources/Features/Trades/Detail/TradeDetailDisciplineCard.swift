import SwiftUI

/// Discipline, Rating & Strategy Playbook Card for Trade Detail View
public struct TradeDetailDisciplineCard: View {
    @Binding public var trade: Trade
    @Binding public var selectedPlaybookId: String
    public let playbooks: [Playbook]
    public let playbookAssessments: [PlaybookRuleAssessment]
    public var onUpdate: () -> Void
    public var onToggleRule: (String, String, Bool) -> Void // (tradeKey, playbookId, followed)
    
    @State private var showAddMistakeInput: Bool = false
    @State private var newMistake: String = ""
    @State private var showAddTagInput: Bool = false
    @State private var newTag: String = ""
    
    private let commonMistakes = [
        "FOMO", "Chased Entry", "Moved SL", "Early Exit",
        "Overtrading", "Revenge", "No Plan"
    ]
    
    private let commonTags = [
        "Trend Follow", "Breakout", "Reversal", "News Event", "Key Level"
    ]
    
    public init(
        trade: Binding<Trade>,
        selectedPlaybookId: Binding<String>,
        playbooks: [Playbook],
        playbookAssessments: [PlaybookRuleAssessment],
        onUpdate: @escaping () -> Void,
        onToggleRule: @escaping (String, String, Bool) -> Void
    ) {
        self._trade = trade
        self._selectedPlaybookId = selectedPlaybookId
        self.playbooks = playbooks
        self.playbookAssessments = playbookAssessments
        self.onUpdate = onUpdate
        self.onToggleRule = onToggleRule
    }
    
    private var activePlaybook: Playbook? {
        playbooks.first(where: { $0.id == trade.playbookId })
    }
    
    public var body: some View {
        TradeFormCardContainer {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                AppSectionHeader("Discipline & playbook")
                
                // Execution Rating
                HStack {
                    Text("Execution Rating")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= (trade.rating ?? 0) ? "star.fill" : "star")
                                .foregroundColor(star <= (trade.rating ?? 0) ? .yellow : AppColors.secondaryText.opacity(0.3))
                                .font(AppTypography.displayMedium)
                                .onTapGesture {
                                    NativeHaptics.lightImpact()
                                    trade.rating = (trade.rating == star) ? nil : star
                                    onUpdate()
                                }
                        }
                    }
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Playbook Strategy Selector
                HStack {
                    Text("Playbook Strategy")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    AppleMenuChip(
                        selectionText: activePlaybook?.name ?? "None",
                        icon: "book.pages"
                    ) {
                        Button("None") {
                            selectedPlaybookId = ""
                            trade.playbookId = nil
                            onUpdate()
                        }
                        ForEach(playbooks) { pb in
                            Button(pb.name) {
                                selectedPlaybookId = pb.id
                                trade.playbookId = pb.id
                                onUpdate()
                            }
                        }
                    }
                }
                
                // Interactive Playbook Rules
                if let pb = activePlaybook {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pb.rules, id: \.self) { rule in
                            let isChecked = playbookAssessments.first(where: {
                                $0.tradeKey == trade.key && $0.playbookId == pb.id && $0.rule == rule
                            })?.followed ?? false
                            
                            AppCheckboxRow(
                                rule,
                                isChecked: isChecked,
                                isStrikethroughWhenChecked: false
                            ) {
                                onToggleRule(pb.id, rule, !isChecked)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Mistakes Section
                mistakesSubsection
                
                Divider().background(AppColors.border.opacity(0.4))
                
                // Tags Section
                tagsSubsection
            }
        }
    }
    
    private var mistakesSubsection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mistakes Identified")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                ModalCircleButton(icon: showAddMistakeInput ? "chevron.up" : "plus") {
                    showAddMistakeInput.toggle()
                }
            }
            
            if !trade.mistakes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trade.mistakes, id: \.self) { mistake in
                            AppTag(mistake, color: AppColors.loss, prefix: "⚠️ ") {
                                trade.mistakes.removeAll { $0 == mistake }
                                onUpdate()
                            }
                        }
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(commonMistakes, id: \.self) { m in
                        let isAdded = trade.mistakes.contains(m)
                        AppFilterChip(
                            m,
                            isSelected: isAdded,
                            height: 26,
                            activeColor: AppColors.loss
                        ) {
                            if isAdded {
                                trade.mistakes.removeAll { $0 == m }
                            } else {
                                trade.mistakes.append(m)
                            }
                            onUpdate()
                        }
                    }
                }
            }
            
            if showAddMistakeInput {
                HStack(spacing: 6) {
                    AppFormField(
                        text: $newMistake,
                        placeholder: "Custom mistake...",
                        height: 32
                    )
                    
                    AppDestructiveButton(
                        "Add",
                        height: 32
                    ) {
                        let clean = newMistake.trimmingCharacters(in: .whitespaces)
                        if !clean.isEmpty && !trade.mistakes.contains(clean) {
                            trade.mistakes.append(clean)
                            newMistake = ""
                            onUpdate()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    private var tagsSubsection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Strategy Tags")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                ModalCircleButton(icon: showAddTagInput ? "chevron.up" : "plus") {
                    showAddTagInput.toggle()
                }
            }
            
            if !trade.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trade.tags, id: \.self) { tag in
                            AppTag(tag, color: AppColors.brand, prefix: "#") {
                                trade.tags.removeAll { $0 == tag }
                                onUpdate()
                            }
                        }
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(commonTags, id: \.self) { t in
                        let isAdded = trade.tags.contains(t)
                        AppFilterChip(
                            "#\(t)",
                            isSelected: isAdded,
                            height: 26,
                            activeColor: AppColors.brand
                        ) {
                            if isAdded {
                                trade.tags.removeAll { $0 == t }
                            } else {
                                trade.tags.append(t)
                            }
                            onUpdate()
                        }
                    }
                }
            }
            
            if showAddTagInput {
                HStack(spacing: 6) {
                    AppFormField(
                        text: $newTag,
                        placeholder: "Custom tag...",
                        height: 32
                    )
                    
                    AppPrimaryButton(
                        "Add",
                        height: 32
                    ) {
                        let clean = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                        if !clean.isEmpty && !trade.tags.contains(clean) {
                            trade.tags.append(clean)
                            newTag = ""
                            onUpdate()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}
