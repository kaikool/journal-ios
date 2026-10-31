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
                    AppFilterChip(cat, isSelected: isSelected) {
                        selectedCategory = cat
                    }
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
                                .font(AppTypography.rowTitle)
                                .foregroundColor(AppColors.primaryText)
                            
                            Spacer()
                            
                            AppActionPill("Analyze", icon: "sparkles") {
                                onSelectTemplate(t)
                            }
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
