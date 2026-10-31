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
                HStack(alignment: .center) {
                    Text("DISCIPLINE & PLAYBOOK")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .tracking(0.5)
                    Spacer()
                    Image(systemName: "book.pages")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(AppColors.secondaryBackground.opacity(0.5))
                        .clipShape(Circle())
                }
                
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
                                .font(.system(size: 18))
                                .onTapGesture {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pb.rules, id: \.self) { rule in
                            let isChecked = playbookAssessments.first(where: {
                                $0.tradeKey == trade.key && $0.playbookId == pb.id && $0.rule == rule
                            })?.followed ?? false
                            
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                onToggleRule(pb.id, rule, !isChecked)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isChecked ? AppColors.profit : AppColors.secondaryText)
                                        .font(.system(size: 15))
                                    Text(rule)
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.primaryText)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
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
                Button {
                    showAddMistakeInput.toggle()
                } label: {
                    Image(systemName: showAddMistakeInput ? "chevron.up" : "plus.circle")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.brand)
                }
            }
            
            if !trade.mistakes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trade.mistakes, id: \.self) { mistake in
                            HStack(spacing: 4) {
                                Text("⚠️ \(mistake)")
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.loss)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.loss.opacity(0.12))
                            .clipShape(Capsule())
                            .onTapGesture {
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
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            if isAdded {
                                trade.mistakes.removeAll { $0 == m }
                            } else {
                                trade.mistakes.append(m)
                            }
                            onUpdate()
                        } label: {
                            Text(m)
                                .font(.system(size: 11, weight: isAdded ? .bold : .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isAdded ? AppColors.loss.opacity(0.15) : AppColors.secondaryBackground)
                                .foregroundColor(isAdded ? AppColors.loss : AppColors.secondaryText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                    }
                }
            }
            
            if showAddMistakeInput {
                HStack(spacing: 6) {
                    TextField("Custom mistake...", text: $newMistake)
                        .font(AppTypography.caption)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Button("Add") {
                        let clean = newMistake.trimmingCharacters(in: .whitespaces)
                        if !clean.isEmpty && !trade.mistakes.contains(clean) {
                            trade.mistakes.append(clean)
                            newMistake = ""
                            onUpdate()
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(AppColors.loss)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .buttonStyle(ApplePressableButtonStyle())
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
                Button {
                    showAddTagInput.toggle()
                } label: {
                    Image(systemName: showAddTagInput ? "chevron.up" : "plus.circle")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.brand)
                }
            }
            
            if !trade.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trade.tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.brand)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.brand.opacity(0.12))
                            .clipShape(Capsule())
                            .onTapGesture {
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
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            if isAdded {
                                trade.tags.removeAll { $0 == t }
                            } else {
                                trade.tags.append(t)
                            }
                            onUpdate()
                        } label: {
                            Text("#\(t)")
                                .font(.system(size: 11, weight: isAdded ? .bold : .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isAdded ? AppColors.brand.opacity(0.15) : AppColors.secondaryBackground)
                                .foregroundColor(isAdded ? AppColors.brand : AppColors.secondaryText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                    }
                }
            }
            
            if showAddTagInput {
                HStack(spacing: 6) {
                    TextField("Custom tag...", text: $newTag)
                        .font(AppTypography.caption)
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Button("Add") {
                        let clean = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                        if !clean.isEmpty && !trade.tags.contains(clean) {
                            trade.tags.append(clean)
                            newTag = ""
                            onUpdate()
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(AppColors.brand)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .buttonStyle(ApplePressableButtonStyle())
                }
                .padding(.top, 2)
            }
        }
    }
}
