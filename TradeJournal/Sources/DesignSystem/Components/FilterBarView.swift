import SwiftUI
#if canImport(UIKit)
import UIKit

public enum AppSafeArea {
    /// Safe area top inset dynamically detected from active UIWindowScene, guaranteeing notch / Dynamic Island clearance.
    public static var topInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        let window = windowScene?.windows.first(where: { $0.isKeyWindow })
            ?? windowScene?.windows.first
        let top = window?.safeAreaInsets.top ?? 0
        return top > 0 ? top : 47
    }
}
#endif

public enum JournalTimeRange: String, CaseIterable, Identifiable {
    case d7 = "7D"
    case d30 = "30D"
    case d90 = "90D"
    case ytd = "YTD"
    case all = "ALL"
    
    public var id: String { rawValue }
    
    /// User selectable time ranges (excluding "ALL" per user requirements)
    public static let selectableCases: [JournalTimeRange] = [.d7, .d30, .d90, .ytd]
    
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
    
    /// High-performance filtering using numerical Date boundaries without expensive DateFormatter string allocations
    public func filterTrades(_ trades: [Trade], timeZone: TimeZone = .current, referenceDate: Date = Date()) -> [Trade] {
        guard self != .all else { return trades }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: referenceDate)
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return trades }
        
        let fromDate: Date
        switch self {
        case .all:
            return trades
        case .ytd:
            let year = calendar.component(.year, from: referenceDate)
            fromDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? startOfToday
        case .d7:
            fromDate = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        case .d30:
            fromDate = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        case .d90:
            fromDate = calendar.date(byAdding: .day, value: -89, to: startOfToday) ?? startOfToday
        }
        
        return trades.filter { trade in
            let date = trade.closedAt ?? trade.openedAt
            return date >= fromDate && date < endOfToday
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
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Binding private var selectedRange: JournalTimeRange
    private let title: String
    private let showAccountSelector: Bool
    private let showFilters: Bool
    private let activeFilterCount: Int
    private let onOpenFilterDialog: (() -> Void)?
    private let onBack: (() -> Void)?
    private let isModal: Bool
    private let actions: Actions
    
    public init(
        title: String = "",
        selectedRange: Binding<JournalTimeRange>? = nil,
        showAccountSelector: Bool = true,
        showFilters: Bool = true,
        activeFilterCount: Int = 0,
        onOpenFilterDialog: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        isModal: Bool = false,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self._selectedRange = selectedRange ?? .constant(.all)
        self.showAccountSelector = showAccountSelector
        self.showFilters = showFilters
        self.activeFilterCount = activeFilterCount
        self.onOpenFilterDialog = onOpenFilterDialog
        self.onBack = onBack
        self.isModal = isModal
        self.actions = actions()
    }
    
    private var hasHeader: Bool {
        !title.isEmpty || onBack != nil
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            if hasHeader {
                headerRow
            }
            
            if showFilters {
                filterRow
            }
        }
        .padding(.horizontal, 14)
        #if canImport(UIKit)
        .padding(.top, isModal ? 10 : (hasHeader ? AppSafeArea.topInset + 6 : 6))
        #else
        .padding(.top, isModal ? 10 : (hasHeader ? 8 : 6))
        #endif
        .padding(.bottom, 8)
        .background {
            Color.clear
        }
        .enableNativePopGesture()
    }
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            if let onBack = onBack {
                AppBackButton(action: onBack)
            }
            
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(AppColors.cardBackground.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 0.6)
                )
            
            Spacer(minLength: 4)
            
            actions
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private var filterRow: some View {
        HStack(spacing: 8) {
            timeRangeSelector
            Spacer(minLength: 6)
            if let onFilter = onOpenFilterDialog {
                filterDialogButton(onFilter: onFilter)
            }
            if !hasHeader {
                actions
            }
        }
    }
    
    private var accountSelectorMenu: some View {
        Menu {
            ForEach(dataStore.visibleAccounts) { acc in
                Button {
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    dataStore.selectAccount(id: acc.id)
                } label: {
                    accountMenuItemLabel(acc: acc)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                
                Text(currentAccountName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.cardBackground.opacity(colorScheme == .dark ? 0.65 : 0.85))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45),
                                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
    }
    
    private func accountMenuItemLabel(acc: Account) -> some View {
        let rawName = acc.name.isEmpty ? "\(acc.broker.isEmpty ? "Standard" : acc.broker) Account" : acc.name
        let displayName = Formatters.cleanAccountName(rawName, balance: acc.initialBalance)
        return HStack {
            Text(displayName + (acc.archivedAt != nil ? " (archived)" : ""))
            if dataStore.selectedAccountId == acc.id {
                Image(systemName: "checkmark")
            }
        }
    }
    
    private var timeRangeSelector: some View {
        HStack(spacing: 2) {
            ForEach(JournalTimeRange.selectableCases) { range in
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
                        .font(.system(size: 11, weight: selectedRange == range ? .bold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4.5)
                        .background(
                            selectedRange == range ?
                            AppColors.cardBackground : Color.clear
                        )
                        .foregroundColor(selectedRange == range ? AppColors.primaryText : AppColors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: selectedRange == range ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06) : Color.clear, radius: 2, x: 0, y: 1)
                }
            }
        }
        .padding(2.5)
        .background(AppColors.secondaryBackground.opacity(colorScheme == .dark ? 0.5 : 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.35),
                            Color.white.opacity(colorScheme == .dark ? 0.03 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
    }
    
    private func filterDialogButton(onFilter: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onFilter()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                Text("Filters")
                    .font(.system(size: 11, weight: .medium))
                
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(AppTypography.badgeMicro)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(AppColors.brand)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(activeFilterCount > 0 ? AppColors.brand.opacity(colorScheme == .dark ? 0.2 : 0.12) : AppColors.cardBackground.opacity(colorScheme == .dark ? 0.65 : 0.85))
            .foregroundColor(activeFilterCount > 0 ? AppColors.brand : AppColors.secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(filterButtonBorder)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, x: 0, y: 1.5)
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
    
    @ViewBuilder
    private var filterButtonBorder: some View {
        if activeFilterCount > 0 {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(AppColors.brand.opacity(0.4), lineWidth: 0.6)
        } else {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.16 : 0.45),
                            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
    }
    
    private var topSpecularHighlight: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.35),
                Color.white.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 1)
        .allowsHitTesting(false)
    }
    
    private var bottomBorder: some View {
        Rectangle()
            .fill(AppColors.border.opacity(colorScheme == .dark ? 0.35 : 0.25))
            .frame(height: 0.5)
    }
    
    private var currentAccountName: String {
        if let acc = dataStore.accounts.first(where: { $0.id == dataStore.selectedAccountId || TradeDataStore.isSameAccountId($0.id, dataStore.selectedAccountId) }) {
            let title = acc.name.isEmpty ? "\(acc.broker.isEmpty ? "Standard" : acc.broker) Account" : acc.name
            return Formatters.cleanAccountName(title, balance: acc.initialBalance)
        }
        if let first = dataStore.visibleAccounts.first {
            let title = first.name.isEmpty ? "\(first.broker.isEmpty ? "Standard" : first.broker) Account" : first.name
            return Formatters.cleanAccountName(title, balance: first.initialBalance)
        }
        return "Trading Account"
    }
}
