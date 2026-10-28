import SwiftUI

// MARK: - Journal Notes Markdown View
// Renders structured journal notes and Risk AI analysis with rich typography
public struct JournalNotesMarkdownView: View {
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        let blocks = JournalNotesParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                renderBlock(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func renderBlock(_ block: JournalNoteBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            let isRiskAiHeader = text.lowercased().contains("risk ai")
            HStack(spacing: 6) {
                if isRiskAiHeader {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.brand)
                }
                Text(LocalizedStringKey(text))
                    .font(.system(
                        size: level == 1 ? 14 : (level == 2 ? 13 : 12.5),
                        weight: .bold
                    ))
                    .foregroundColor(isRiskAiHeader ? AppColors.brand : AppColors.primaryText)
            }
            .padding(.top, level == 1 ? 6 : 3)
            .padding(.bottom, 1)
            
        case .divider:
            Divider()
                .background(AppColors.border.opacity(0.6))
                .padding(.vertical, 4)
            
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColors.brand)
                    .frame(width: 3)
                
                JustifiedText(
                    text,
                    font: .system(size: 12, weight: .medium),
                    fontSize: 12,
                    fontWeight: .medium,
                    textColor: AppColors.primaryText,
                    lineSpacing: 3
                )
                .padding(.vertical, 2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground.opacity(0.6))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
            )
            
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(AppColors.brand.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .padding(.top, 5.5)
                
                JustifiedText(
                    text,
                    font: AppTypography.caption,
                    fontSize: 13,
                    fontWeight: .regular,
                    textColor: AppColors.primaryText,
                    lineSpacing: 3
                )
            }
            .padding(.leading, 2)
            
        case .numbered(let num, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).")
                    .font(AppTypography.number(12, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 18, alignment: .leading)
                
                JustifiedText(
                    text,
                    font: AppTypography.caption,
                    fontSize: 13,
                    fontWeight: .regular,
                    textColor: AppColors.primaryText,
                    lineSpacing: 3
                )
            }
            
        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    // Table Header Row
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { colIdx, header in
                            Text(LocalizedStringKey(header))
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 85, maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .trailing) {
                                    if colIdx < headers.count - 1 {
                                        Rectangle()
                                            .fill(AppColors.border.opacity(0.35))
                                            .frame(width: 0.5)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(AppColors.border.opacity(0.5))
                                        .frame(height: 0.5)
                                }
                        }
                    }
                    .background(AppColors.secondaryBackground.opacity(0.85))
                    
                    // Table Data Rows
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                        GridRow {
                            ForEach(Array(headers.indices), id: \.self) { colIdx in
                                let cellText = colIdx < row.count ? row[colIdx] : ""
                                Text(LocalizedStringKey(cellText))
                                    .font(.system(size: 11.5, weight: .regular))
                                    .foregroundColor(AppColors.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .frame(minWidth: 85, maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .trailing) {
                                        if colIdx < headers.count - 1 {
                                            Rectangle()
                                                .fill(AppColors.border.opacity(0.25))
                                                .frame(width: 0.5)
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if rowIdx < rows.count - 1 {
                                            Rectangle()
                                                .fill(AppColors.border.opacity(0.2))
                                                .frame(height: 0.5)
                                        }
                                    }
                            }
                        }
                        .background(rowIdx % 2 == 0 ? Color.clear : AppColors.secondaryBackground.opacity(0.3))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                )
            }
            .padding(.vertical, 4)
            
        case .paragraph(let text):
            JustifiedText(
                text,
                font: AppTypography.caption,
                fontSize: 13,
                fontWeight: .regular,
                textColor: AppColors.primaryText,
                lineSpacing: 3.5
            )
        }
    }
}
