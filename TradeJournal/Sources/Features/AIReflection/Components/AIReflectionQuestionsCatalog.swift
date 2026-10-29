import SwiftUI

// MARK: - AI Reflection Questions Catalog & Filter Chips
public struct AIReflectionCategoryChips: View {
    @Binding public var selectedCategory: String
    public let categories: [String]
    
    public init(selectedCategory: Binding<String>, categories: [String] = ["All", "Session", "Trade Audit", "Leaks", "Prop Risk", "Sizing"]) {
        self._selectedCategory = selectedCategory
        self.categories = categories
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    Button(action: {
                        selectedCategory = cat
                    }) {
                        Text(cat)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? AppColors.secondaryBackground : Color.clear)
                            .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isSelected ? AppColors.border : AppColors.border.opacity(0.4), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

public struct AIReflectionQuestionsCatalog: View {
    public let templates: [AIReflectionTemplate]
    public let onSelectTemplate: (AIReflectionTemplate) -> Void
    
    public init(templates: [AIReflectionTemplate], onSelectTemplate: @escaping (AIReflectionTemplate) -> Void) {
        self.templates = templates
        self.onSelectTemplate = onSelectTemplate
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            ForEach(templates) { t in
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(t.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                            
                            Spacer()
                            
                            Button(action: {
                                onSelectTemplate(t)
                            }) {
                                Text("Analyze")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppColors.primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppColors.border.opacity(0.8), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text(t.subtitle)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectTemplate(t)
                }
            }
        }
    }
}
