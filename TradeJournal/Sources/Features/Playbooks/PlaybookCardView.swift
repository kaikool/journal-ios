import SwiftUI

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
                            .truncationMode(.tail)
                    }
                    
                    Spacer()
                    
                    Text("\(summary.totalTrades) trades")
                        .font(AppTypography.caption)
                        .monospacedDigit()
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.loss.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
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
                            .buttonStyle(.borderless)
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
                            .lineLimit(1)
                        Text(Formatters.formatPnL(summary.netPnlWhenFollowed, currency: currency))
                            .font(AppTypography.bodyBold)
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
                            .font(AppTypography.bodyBold)
                            .monospacedDigit()
                            .foregroundColor(Formatters.pnlColor(summary.netPnlWhenBroken))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
        }
    }
}
