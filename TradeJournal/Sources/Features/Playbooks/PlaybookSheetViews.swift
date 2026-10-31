import SwiftUI

// MARK: - New Playbook Sheet (Refined Dynamic Numbered Checklist 1, 2, 3...)

public struct NewPlaybookSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var rules: [String] = [""]
    @State private var isDefault: Bool = false
    
    var onSave: (Playbook) -> Void
    
    private var validRulesCount: Int {
        rules.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    
    public var body: some View {
        NavigationStack {
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
            .navigationTitle("New Playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Create", isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        saveAndDismiss()
                    }
                }
            }
        }
    }
    
    private var detailsCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Strategy identity", icon: "pencil.and.outline")
                
                AppFormField(
                    "Playbook Name",
                    text: $title,
                    placeholder: "e.g. London Breakout, A+ Trend Reversal",
                    height: 42
                )
                
                AppFormField(
                    "Strategy Description",
                    text: $description,
                    placeholder: "Setup conditions, context, or entry guidelines",
                    height: 42
                )
                
                // Default Playbook Toggle
                AppToggleRow(
                    "Set as Default Playbook",
                    subtitle: "Automatically assigned to newly opened and imported trades",
                    icon: "star.circle.fill",
                    isOn: $isDefault
                )
            }
        }
    }
    
    private var checklistCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader(
                    "Checklist rules",
                    icon: "checklist",
                    badge: "\(validRulesCount)",
                    trailingBadge: "Dynamic Entry",
                    trailingBadgeColor: AppColors.brand
                )
                
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
                AppButton(
                    "Add rule condition",
                    icon: "plus.circle",
                    style: .outline,
                    fullWidth: true
                ) {
                    rules.append("")
                }
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func ruleInputRow(index: Int) -> some View {
        HStack(spacing: 8) {
            // Numbered Badge 1, 2, 3...
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.12))
                    .frame(width: 26, height: 26)
                Text("\(index + 1)")
                    .font(AppTypography.captionMicroBold)
                    .foregroundColor(AppColors.brand)
            }
            
            AppTextField("Rule condition (e.g. Price above 200 EMA)", text: Binding(
                get: {
                    guard index < rules.count else { return "" }
                    return rules[index]
                },
                set: { newVal in
                    guard index < rules.count else { return }
                    rules[index] = newVal
                    // Progressive Disclosure: If user typed in the last row, spawn next row
                    if !newVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && index == rules.count - 1 {
                        withAnimation(AppAnimations.springQuick) {
                            rules.append("")
                        }
                    }
                }
            ))
            
            if rules.count > 1 || (index < rules.count && !rules[index].isEmpty) {
                ModalCloseButton {
                    withAnimation(AppAnimations.springQuick) {
                        if index < rules.count {
                            rules.remove(at: index)
                            if rules.isEmpty {
                                rules.append("")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func saveAndDismiss() {
        let parsedRules = rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let pb = Playbook(
            title: title.isEmpty ? "New Playbook" : title,
            description: description,
            rules: parsedRules,
            isDefault: isDefault
        )
        onSave(pb)
        if isDefault {
            TradeDataStore.shared.setDefaultPlaybook(id: pb.id)
        }
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    detailsCard
                    checklistCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppColors.background)
            .navigationTitle("Edit Playbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ModalSecondaryButton("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    ModalPrimaryButton("Save", isEnabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        saveAndDismiss()
                    }
                }
            }
        }
    }
    
    private var detailsCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader("Strategy identity", icon: "pencil.and.outline")
                
                AppFormField(
                    "Playbook Name",
                    text: $title,
                    placeholder: "Playbook name",
                    height: 42
                )
                
                AppFormField(
                    "Strategy Description",
                    text: $description,
                    placeholder: "Setup conditions or notes",
                    height: 42
                )
            }
        }
    }
    
    private var checklistCard: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeader(
                    "Checklist rules",
                    icon: "checklist",
                    badge: "\(validRulesCount)",
                    trailingBadge: "Dynamic Entry",
                    trailingBadgeColor: AppColors.brand
                )
                
                Text("Edit conditions. Line additions happen automatically as you type in the bottom line.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                VStack(spacing: 10) {
                    ForEach(Array(rules.indices), id: \.self) { index in
                        ruleInputRow(index: index)
                    }
                }
                
                AppButton(
                    "Add rule condition",
                    icon: "plus.circle",
                    style: .outline,
                    fullWidth: true
                ) {
                    rules.append("")
                }
                .padding(.top, 4)
            }
        }
    }
    
    @ViewBuilder
    private func ruleInputRow(index: Int) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(AppColors.brand.opacity(0.12))
                    .frame(width: 26, height: 26)
                Text("\(index + 1)")
                    .font(AppTypography.captionMicroBold)
                    .foregroundColor(AppColors.brand)
            }
            
            AppTextField("Rule condition", text: Binding(
                get: {
                    guard index < rules.count else { return "" }
                    return rules[index]
                },
                set: { newVal in
                    guard index < rules.count else { return }
                    rules[index] = newVal
                    if !newVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && index == rules.count - 1 {
                        withAnimation(AppAnimations.springQuick) {
                            rules.append("")
                        }
                    }
                }
            ))
            
            if rules.count > 1 || (index < rules.count && !rules[index].isEmpty) {
                ModalCloseButton {
                    withAnimation(AppAnimations.springQuick) {
                        if index < rules.count {
                            rules.remove(at: index)
                            if rules.isEmpty {
                                rules.append("")
                            }
                        }
                    }
                }
            }
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
            rules: parsedRules,
            isDefault: playbook.isDefault
        )
        dismiss()
    }
}

