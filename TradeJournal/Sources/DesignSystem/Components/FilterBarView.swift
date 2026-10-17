import SwiftUI

public enum JournalTimeRange: String, CaseIterable, Identifiable {
    case d7 = "7D"
    case d30 = "30D"
    case d90 = "90D"
    case ytd = "YTD"
    case all = "ALL"
    
    public var id: String { rawValue }
}

/// FilterBar component matching 100% of `source-repo/apps/web/src/components/filter-bar.tsx`:
/// - Page title (16px font-semibold)
/// - AccountSelector pill (select account or "All accounts")
/// - Time range pill strip (7D, 30D, 90D, YTD, ALL)
/// - Filters trigger button with active filter badge count
/// - Right-aligned action buttons slot
public struct FilterBarView<Actions: View>: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Binding private var selectedRange: JournalTimeRange
    private let title: String
    private let showFilters: Bool
    private let activeFilterCount: Int
    private let onOpenFilterDialog: (() -> Void)?
    private let actions: Actions
    
    public init(
        title: String,
        selectedRange: Binding<JournalTimeRange>? = nil,
        showFilters: Bool = true,
        activeFilterCount: Int = 0,
        onOpenFilterDialog: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self._selectedRange = selectedRange ?? .constant(.all)
        self.showFilters = showFilters
        self.activeFilterCount = activeFilterCount
        self.onOpenFilterDialog = onOpenFilterDialog
        self.actions = actions()
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(AppTypography.pageTitle)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Spacer()
                
                actions
            }
            
            if showFilters {
                HStack(spacing: 8) {
                    // Account Selector Dropdown Pill (port 1:1 from account-selector.tsx)
                    Menu {
                        Button {
                            #if os(iOS)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            dataStore.selectedAccountId = "all"
                        } label: {
                            HStack {
                                Text("All accounts")
                                if dataStore.selectedAccountId == "all" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Divider()
                        
                        ForEach(dataStore.visibleAccounts) { acc in
                            Button {
                                #if os(iOS)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                                dataStore.selectedAccountId = acc.id
                            } label: {
                                HStack {
                                    Text(acc.name.isEmpty ? acc.id : acc.name + (acc.archivedAt != nil ? " (archived)" : ""))
                                    if dataStore.selectedAccountId == acc.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                            
                            Text(currentAccountName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.cardBackground.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                        )
                    }
                    
                    // Time Range Selector Pills (7D, 30D, 90D, YTD, ALL)
                    HStack(spacing: 2) {
                        ForEach(JournalTimeRange.allCases) { range in
                            Button {
                                if selectedRange != range {
                                    #if os(iOS)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    #endif
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                        selectedRange = range
                                    }
                                }
                            } label: {
                                Text(range.rawValue)
                                    .font(.system(size: 11, weight: selectedRange == range ? .bold : .medium, design: .rounded))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        selectedRange == range ?
                                        AppColors.secondaryBackground : Color.clear
                                    )
                                    .foregroundColor(selectedRange == range ? AppColors.primaryText : AppColors.secondaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .shadow(color: selectedRange == range ? Color.black.opacity(0.06) : Color.clear, radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                    .padding(2.5)
                    .background(AppColors.cardBackground.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
                    )
                    
                    Spacer()
                    
                    // Filter Dialog Button
                    if let onFilter = onOpenFilterDialog {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            onFilter()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 11))
                                Text(activeFilterCount > 0 ? "Filters · \(activeFilterCount)" : "Filters")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppColors.cardBackground.opacity(0.9))
                            .foregroundColor(activeFilterCount > 0 ? AppColors.brand : AppColors.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(activeFilterCount > 0 ? AppColors.brand.opacity(0.4) : AppColors.border.opacity(0.6), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(ApplePressableButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.background.opacity(0.95))
        .overlay(
            Divider().background(AppColors.border),
            alignment: .bottom
        )
    }
    
    private var currentAccountName: String {
        if dataStore.selectedAccountId == "all" {
            return "All accounts"
        }
        if let acc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId }) {
            return acc.name.isEmpty ? acc.id : acc.name
        }
        return "All accounts"
    }
}
