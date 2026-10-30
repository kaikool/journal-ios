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
                .font(.system(size: 16, weight: .bold))
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                
                // Default Playbook Checkbox
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    isDefault.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isDefault ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(isDefault ? AppColors.brand : AppColors.secondaryText)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set as Default Playbook")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            Text("Automatically assigned to newly opened and imported trades")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isDefault ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.5), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
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
                    .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 16, weight: .bold))
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 12, weight: .bold))
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
            rules: parsedRules,
            isDefault: playbook.isDefault
        )
        dismiss()
    }
}

