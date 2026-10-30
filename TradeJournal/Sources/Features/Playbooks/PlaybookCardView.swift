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
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onSelect()
                    } label: {
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
                                .font(AppTypography.subheadlineBold)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if summary.playbook.isDefault {
                                Text("DEFAULT")
                                    .font(AppTypography.badgeMicro)
                                    .foregroundColor(AppColors.brand)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.brand.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("\(summary.totalTrades) trades")
                        .font(AppTypography.caption)
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 32, height: 32)
                            .background(AppColors.secondaryBackground)
                            .clipShape(Circle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.loss.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(AppColors.loss.opacity(0.1))
                            .clipShape(Circle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                // Content area that opens Detail
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onSelect()
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        if !summary.playbook.description.isEmpty {
                            Text(summary.playbook.description)
                                .font(AppTypography.caption)
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
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(AppColors.brand)
                                        }
                                        .padding(.top, 1)
                                        
                                        Text(rule)
                                            .font(AppTypography.caption)
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
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Text(Formatters.formatPnL(summary.netPnlWhenFollowed, currency: currency))
                                    .font(AppTypography.subheadlineBold)
                                    .monospacedDigit()
                                    .foregroundColor(Formatters.pnlColor(summary.netPnlWhenFollowed))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("When broken")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                Text(Formatters.formatPnL(summary.netPnlWhenBroken, currency: currency))
                                    .font(AppTypography.subheadlineBold)
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
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(isExpanded ? "Show less" : "+ \(summary.playbook.rules.count - 3) more rules")
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize()
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
                    }
                    
                    Spacer()
                    
                    if let onSetDefault = onSetDefault {
                        Button {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            onSetDefault()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: summary.playbook.isDefault ? "checkmark.circle.fill" : "star")
                                    .font(.system(size: 10, weight: summary.playbook.isDefault ? .bold : .medium))
                                Text(summary.playbook.isDefault ? "Default" : "Set default")
                                    .font(.system(size: 11, weight: summary.playbook.isDefault ? .semibold : .medium))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundColor(summary.playbook.isDefault ? AppColors.brand : AppColors.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(summary.playbook.isDefault ? AppColors.brand.opacity(0.12) : AppColors.secondaryBackground)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(summary.playbook.isDefault ? AppColors.brand.opacity(0.3) : AppColors.border.opacity(0.5), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, -2)
            }
        }
    }
}
