import SwiftUI

public enum JournalTimeRange: String, CaseIterable, Identifiable {
    case d7 = "7D"
    case d30 = "30D"
    case d90 = "90D"
    case ytd = "YTD"
    case all = "ALL"
    
    public var id: String { rawValue }
    
    /// Ported 1:1 from `apps/web/src/components/filter-bar.tsx` useFilters:
    /// Returns `(from: String?, to: String?)` date strings in `YYYY-MM-DD` format according to the given timezone.
    public func dayBounds(timeZone: TimeZone = .current, referenceDate: Date = Date()) -> (from: String?, to: String?) {
        guard self != .all else { return (nil, nil) }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        
        let today = formatter.string(from: referenceDate)
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        
        switch self {
        case .all:
            return (nil, nil)
        case .ytd:
            let year = String(today.prefix(4))
            return ("\(year)-01-01", today)
        case .d7:
            // Web: d.setUTCDate(d.getUTCDate() - 7 + 1) -> 7 calendar days including today (-6 days)
            let fromDate = calendar.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate
            return (formatter.string(from: fromDate), today)
        case .d30:
            // Web: d.setUTCDate(d.getUTCDate() - 30 + 1) -> 30 calendar days including today (-29 days)
            let fromDate = calendar.date(byAdding: .day, value: -29, to: referenceDate) ?? referenceDate
            return (formatter.string(from: fromDate), today)
        case .d90:
            // Web: d.setUTCDate(d.getUTCDate() - 90 + 1) -> 90 calendar days including today (-89 days)
            let fromDate = calendar.date(byAdding: .day, value: -89, to: referenceDate) ?? referenceDate
            return (formatter.string(from: fromDate), today)
        }
    }
    
    /// Filters trades using `trade.closedAt ?? trade.openedAt` matching web `matchesFilters` in `packages/core/src/analysis.ts`
    public func filterTrades(_ trades: [Trade], timeZone: TimeZone = .current, referenceDate: Date = Date()) -> [Trade] {
        guard self != .all else { return trades }
        let (from, to) = dayBounds(timeZone: timeZone, referenceDate: referenceDate)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        
        return trades.filter { trade in
            let date = trade.closedAt ?? trade.openedAt
            let day = formatter.string(from: date)
            if let from = from, day < from { return false }
            if let to = to, day > to { return false }
            return true
        }
    }
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
    private let onBack: (() -> Void)?
    private let actions: Actions
    
    public init(
        title: String,
        selectedRange: Binding<JournalTimeRange>? = nil,
        showFilters: Bool = true,
        activeFilterCount: Int = 0,
        onOpenFilterDialog: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self._selectedRange = selectedRange ?? .constant(.all)
        self.showFilters = showFilters
        self.activeFilterCount = activeFilterCount
        self.onOpenFilterDialog = onOpenFilterDialog
        self.onBack = onBack
        self.actions = actions()
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let onBack = onBack {
                    AppBackButton(action: onBack)
                }
                
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
                                    let displayName = Formatters.cleanAccountName(acc.name.isEmpty ? "\(acc.broker.isEmpty ? "Standard" : acc.broker) Account" : acc.name, balance: acc.initialBalance)
                                    Text(displayName + (acc.archivedAt != nil ? " (archived)" : ""))
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
            let title = acc.name.isEmpty ? "\(acc.broker.isEmpty ? "Standard" : acc.broker) Account" : acc.name
            return Formatters.cleanAccountName(title, balance: acc.initialBalance)
        }
        return "All accounts"
    }
}
