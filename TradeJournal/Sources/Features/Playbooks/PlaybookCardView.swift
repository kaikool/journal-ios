import SwiftUI

// MARK: - Playbook Card View (Expandable Rules Checklist)

public struct PlaybookCardView: View {
    let summary: PlaybookAdherenceSummary
    let currency: String
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSetDefault: (() -> Void)?
    
    @State private var isExpanded: Bool = false
    
    public init(
        summary: PlaybookAdherenceSummary,
        currency: String,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSetDefault: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.currency = currency
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onSetDefault = onSetDefault
    }
    
    public var body: some View {
        AppleCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack(alignment: .center) {
                    Button {
                        .lightImpact()
                        onSelect()
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.brand.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "book.pages")
                                    .font(AppTypography.cardHeader)
                                    .foregroundColor(AppColors.brand)
                            }
                            
                            Text(summary.playbook.title)
                                .font(AppTypography.rowPrimary)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if summary.playbook.isDefault {
                                AppBadge("DEFAULT", variant: .brand)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("\(summary.totalTrades) trades")
                        .font(AppTypography.statLabel)
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    
                    ModalIconButton(icon: "pencil", color: AppColors.secondaryText, label: "Edit playbook", action: onEdit)
                    ModalDeleteButton(action: onDelete)
                }
                
                // Content area that opens Detail
                Button {
                    .lightImpact()
                    onSelect()
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        if !summary.playbook.description.isEmpty {
                            Text(summary.playbook.description)
                                .font(AppTypography.rowSecondary)
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        
                        // Numbered Checklist Rules Section
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
                                                .font(AppTypography.badgeStandard)
                                                .foregroundColor(AppColors.brand)
                                        }
                                        .padding(.top, 1)
                                        
                                        Text(rule)
                                            .font(AppTypography.body)
                                            .foregroundColor(AppColors.primaryText)
                                            .lineLimit(isExpanded ? 3 : 1)
                                            .multilineTextAlignment(.leading)
                                        
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        
                        Divider().background(AppColors.border.opacity(0.5))
                        
                        // Adherence summary row
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("When followed")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Text(Formatters.formatPnL(summary.netPnlWhenFollowed, currency: currency))
                                    .font(AppTypography.statValue)
                                    .monospacedDigit()
                                    .foregroundColor(Formatters.pnlColor(summary.netPnlWhenFollowed))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("When broken")
                                    .font(AppTypography.statLabel)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Text(Formatters.formatPnL(summary.netPnlWhenBroken, currency: currency))
                                    .font(AppTypography.statValue)
                                    .monospacedDigit()
                                    .foregroundColor(Formatters.pnlColor(summary.netPnlWhenBroken))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Bottom Action Row: More rules (left) & Set Default under When broken (right)
                HStack(alignment: .center) {
                    if summary.playbook.rules.count > 3 {
                        AppFilterChip(
                            isExpanded ? "Show less" : "+ \(summary.playbook.rules.count - 3) more rules",
                            isSelected: isExpanded,
                            icon: isExpanded ? "chevron.up" : "chevron.down",
                            height: 26
                        ) {
                            withAnimation(AppAnimations.springStandard) {
                                isExpanded.toggle()
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if let onSetDefault = onSetDefault {
                        AppFilterChip(
                            summary.playbook.isDefault ? "Default" : "Set default",
                            isSelected: summary.playbook.isDefault,
                            icon: summary.playbook.isDefault ? "checkmark.circle.fill" : "star",
                            height: 26
                        ) {
                            onSetDefault()
                        }
                    }
                }
                .padding(.top, -2)
            }
        }
    }
}
