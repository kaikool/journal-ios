import SwiftUI

public enum JournalTimeRange: String, CaseIterable, Identifiable {
    case d7 = "7D"
    case d30 = "30D"
    case d90 = "90D"
    case ytd = "YTD"
    case all = "ALL"
    
    public var id: String { rawValue }
}

/// Thanh FilterBar chuẩn xác 100% đối chiếu từ `source-repo/apps/web/src/components/filter-bar.tsx`:
/// - Tiêu đề trang (16px font-semibold)
/// - AccountSelector pill (chọn tài khoản hoặc "Tất cả tài khoản")
/// - Dải nút phạm vi thời gian (7D, 30D, 90D, YTD, ALL)
/// - Nút Filters kèm đếm bộ lọc đang kích hoạt
/// - Slot chứa Action Buttons bên phải
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
                    // Account Selector Dropdown Pill (Port 1:1 từ source-repo account-selector.tsx)
                    Menu {
                        Button {
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
                                .font(AppTypography.captionMedium)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                    
                    // Time Range Selector Pills (7D, 30D, 90D, YTD, ALL)
                    HStack(spacing: 2) {
                        ForEach(JournalTimeRange.allCases) { range in
                            Button {
                                selectedRange = range
                            } label: {
                                Text(range.rawValue)
                                    .font(AppTypography.captionMedium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(selectedRange == range ? AppColors.secondaryBackground : Color.clear)
                                    .foregroundColor(selectedRange == range ? AppColors.primaryText : AppColors.secondaryText)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(2)
                    .background(AppColors.cardBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    
                    Spacer()
                    
                    // Filter Dialog Button
                    if let onFilter = onOpenFilterDialog {
                        Button(action: onFilter) {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10))
                                Text(activeFilterCount > 0 ? "Filters · \(activeFilterCount)" : "Filters")
                                    .font(AppTypography.captionMedium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppColors.cardBackground)
                            .foregroundColor(AppColors.secondaryText)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                        }
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
