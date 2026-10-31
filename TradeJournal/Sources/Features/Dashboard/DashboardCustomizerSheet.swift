import SwiftUI

// MARK: - 1:1 Port of Dashboard Card Sizing & Groups from `lib/dashboard-layout.ts`
public enum DashboardCardSize: String, CaseIterable, Codable {
    case small
    case medium
    case wide
    case full
}

// MARK: - 4 Canonical Presets ported 1:1 from `lib/dashboard-layout.ts`
public enum DashboardPreset: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tradingDay = "Trading day"
    case performance = "Performance"
    case riskReview = "Risk review"
    case custom = "Custom"
    
    public var id: String { rawValue }
    public var name: String { rawValue }
    
    public var description: String {
        switch self {
        case .overview: return "All cards in the original order."
        case .tradingDay: return "Calendar and recent trades first, then daily results."
        case .performance: return "Returns, win rate, equity, and your trading edge."
        case .riskReview: return "Drawdown, streaks, expectancy, and daily swings."
        case .custom: return "Customized arrangement."
        }
    }
    
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .tradingDay: return "calendar.badge.clock"
        case .performance: return "chart.line.uptrend.xyaxis"
        case .riskReview: return "chart.line.downtrend.xyaxis"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    /// Canonical ordering defined in `dashboard-layout.ts:25-36`
    public var canonicalOrder: [String] {
        switch self {
        case .overview:
            return DashboardCardRegistry.defaultOrder
        case .tradingDay:
            let selected = ["widget-8", "widget-9", "widget-0", "widget-1", "widget-3", "widget-7", "widget-15"]
            let rest = DashboardCardRegistry.defaultOrder.filter { !selected.contains($0) }
            return selected + rest
        case .performance:
            let selected = ["widget-0", "widget-1", "widget-2", "widget-4", "widget-6", "widget-7", "widget-5", "widget-15"]
            let rest = DashboardCardRegistry.defaultOrder.filter { !selected.contains($0) }
            return selected + rest
        case .riskReview:
            let selected = ["widget-10", "widget-11", "widget-12", "widget-14", "widget-6", "widget-7"]
            let rest = DashboardCardRegistry.defaultOrder.filter { !selected.contains($0) }
            return selected + rest
        case .custom:
            return DashboardCardRegistry.defaultOrder
        }
    }
    
    /// Hidden card IDs defined in `dashboard-layout.ts:37-49`
    public var canonicalHidden: Set<String> {
        switch self {
        case .overview:
            return []
        case .tradingDay:
            let selected = Set(["widget-8", "widget-9", "widget-0", "widget-1", "widget-3", "widget-7", "widget-15"])
            return Set(DashboardCardRegistry.defaultOrder.filter { !selected.contains($0) })
        case .performance:
            let selected = Set(["widget-0", "widget-1", "widget-2", "widget-4", "widget-6", "widget-7", "widget-5", "widget-15"])
            return Set(DashboardCardRegistry.defaultOrder.filter { !selected.contains($0) })
        case .riskReview:
            let selected = Set(["widget-10", "widget-11", "widget-12", "widget-14", "widget-6", "widget-7"])
            return Set(DashboardCardRegistry.defaultOrder.filter { !selected.contains($0) })
        case .custom:
            return []
        }
    }
}

public struct DashboardCardItem: Identifiable, Hashable {
    public let id: String
    public let label: String
    public let icon: String
    public let size: DashboardCardSize
    public let group: String
}

public enum DashboardCardRegistry {
    public static let allCards: [DashboardCardItem] = [
        DashboardCardItem(id: "widget-0", label: "Net P&L", icon: "dollarsign.circle", size: .small, group: "summary"),
        DashboardCardItem(id: "widget-1", label: "Trade win %", icon: "target", size: .small, group: "summary"),
        DashboardCardItem(id: "widget-2", label: "Profit factor", icon: "scalemass", size: .small, group: "summary"),
        DashboardCardItem(id: "widget-3", label: "Day win %", icon: "calendar.badge.clock", size: .small, group: "summary"),
        DashboardCardItem(id: "widget-4", label: "Avg win / loss", icon: "arrow.up.arrow.down", size: .small, group: "summary"),
        DashboardCardItem(id: "widget-5", label: "Edge Score", icon: "gauge.with.dots.needle.bottom.50percent", size: .medium, group: "visuals"),
        DashboardCardItem(id: "widget-6", label: "Cumulative P&L", icon: "chart.line.uptrend.xyaxis", size: .medium, group: "visuals"),
        DashboardCardItem(id: "widget-7", label: "Daily P&L", icon: "chart.bar.xaxis", size: .medium, group: "visuals"),
        DashboardCardItem(id: "widget-8", label: "Calendar", icon: "calendar", size: .wide, group: "detail"),
        DashboardCardItem(id: "widget-9", label: "Activity", icon: "list.bullet.rectangle", size: .medium, group: "detail"),
        DashboardCardItem(id: "widget-10", label: "Max drawdown", icon: "chart.line.downtrend.xyaxis", size: .small, group: "secondary"),
        DashboardCardItem(id: "widget-11", label: "Streaks", icon: "flame", size: .small, group: "secondary"),
        DashboardCardItem(id: "widget-12", label: "Expectancy / trade", icon: "sum", size: .small, group: "secondary"),
        DashboardCardItem(id: "widget-13", label: "Avg duration", icon: "timer", size: .small, group: "secondary"),
        DashboardCardItem(id: "widget-14", label: "Best / worst day", icon: "trophy", size: .small, group: "secondary"),
        DashboardCardItem(id: "widget-15", label: "Trade time performance", icon: "clock", size: .full, group: "full")
    ]
    
    public static let defaultOrder: [String] = allCards.map(\.id)
    
    public static func size(for id: String) -> DashboardCardSize {
        allCards.first(where: { $0.id == id })?.size ?? .medium
    }
    
    public static func item(for id: String) -> DashboardCardItem? {
        allCards.first(where: { $0.id == id })
    }
}

/// Dashboard Customizer Sheet ported 1:1 from `components/dashboard-customizer.tsx`
/// and `components/dashboard-saved-layouts.tsx`.
/// Features:
/// - 4 Canonical Presets: Overview, Trading day, Performance, Risk review
/// - Interactive Drag-and-Drop Reordering with Apple HIG `.onMove` grabbers
/// - Searchable card visibility toggles
public struct DashboardCustomizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var hiddenCardIds: Set<String>
    @Binding var cardOrder: [String]
    @Binding var activePreset: DashboardPreset
    
    @State private var selectedTab: CustomizerTab = .visibility
    @State private var searchQuery: String = ""
    
    public enum CustomizerTab: String, CaseIterable, Identifiable {
        case visibility = "Visibility"
        case reorder = "Reorder & Presets"
        
        public var id: String { rawValue }
    }
    
    public init(
        hiddenCardIds: Binding<Set<String>>,
        cardOrder: Binding<[String]>? = nil,
        activePreset: Binding<DashboardPreset>? = nil
    ) {
        self._hiddenCardIds = hiddenCardIds
        self._cardOrder = cardOrder ?? .constant(DashboardCardRegistry.defaultOrder)
        self._activePreset = activePreset ?? .constant(.overview)
    }
    
    private var filteredCards: [DashboardCardItem] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DashboardCardRegistry.allCards
        }
        return DashboardCardRegistry.allCards.filter {
            $0.label.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    private var visibleCount: Int {
        DashboardCardRegistry.allCards.count - hiddenCardIds.count
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Tab Switcher (Apple HIG Sliding Bar)
                Picker("Tab", selection: $selectedTab) {
                    ForEach(CustomizerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.cardBackground)
                
                Divider().background(AppColors.border)
                
                if selectedTab == .visibility {
                    visibilityTabView
                } else {
                    reorderAndPresetsTabView
                }
            }
            .background(AppColors.background)
            .navigationTitle("Dashboard cards")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Done") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Visibility Tab
    
    private var visibilityTabView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                
                TextField("Search cards...", text: $searchQuery)
                    .font(AppTypography.inputText)
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.cardBackground)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Quick Action Bar: Visible Count & Show all / Restore
            HStack {
                Text("\(visibleCount) of \(DashboardCardRegistry.allCards.count) visible")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                Button("Show all") {
                    withAnimation {
                        hiddenCardIds.removeAll()
                        activePreset = .custom
                    }
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brand)
                
                Text("·")
                    .foregroundColor(AppColors.secondaryText)
                
                Button("Restore default") {
                    withAnimation {
                        hiddenCardIds.removeAll()
                        cardOrder = DashboardCardRegistry.defaultOrder
                        activePreset = .overview
                    }
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider().background(AppColors.border)
            
            // Card list with switches
            List {
                ForEach(filteredCards) { card in
                    HStack(spacing: 12) {
                        Image(systemName: card.icon)
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.brand)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.label)
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.primaryText)
                            Text("\(card.size.rawValue.capitalized) card · \(card.group)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { !hiddenCardIds.contains(card.id) },
                            set: { isVisible in
                                #if canImport(UIKit)
                                UISelectionFeedbackGenerator().selectionChanged()
                                #endif
                                withAnimation {
                                    if isVisible {
                                        hiddenCardIds.remove(card.id)
                                    } else {
                                        hiddenCardIds.insert(card.id)
                                    }
                                    activePreset = .custom
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(AppColors.brand)
                    }
                    .listRowBackground(AppColors.cardBackground)
                    .listRowSeparatorTint(AppColors.border.opacity(0.6))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
    
    // MARK: - Reorder & Presets Tab
    
    private var reorderAndPresetsTabView: some View {
        VStack(spacing: 0) {
            // Presets Header Section
            VStack(alignment: .leading, spacing: 8) {
                Text("PRESETS")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DashboardPreset.allCases.filter { $0 != .custom }) { preset in
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    activePreset = preset
                                    cardOrder = preset.canonicalOrder
                                    hiddenCardIds = preset.canonicalHidden
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 12))
                                    Text(preset.name)
                                        .font(AppTypography.captionBold)
                                    if activePreset == preset {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(height: 28)
                                .background(activePreset == preset ? AppColors.brand : AppColors.cardBackground)
                                .foregroundColor(activePreset == preset ? .white : AppColors.primaryText)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(activePreset == preset ? Color.clear : AppColors.border, lineWidth: 0.5)
                                )
                            }
                            .fixedSize()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                Text(activePreset.description)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            .background(AppColors.cardBackground)
            
            Divider().background(AppColors.border)
            
            // Reorder Instructions
            HStack {
                Text("DRAG TO REORDER CARDS")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                
                Spacer()
                
                Button("Restore order") {
                    withAnimation {
                        cardOrder = DashboardCardRegistry.defaultOrder
                        activePreset = .overview
                    }
                }
                .font(AppTypography.captionBold)
                .foregroundColor(AppColors.brand)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Sortable List with Native iOS Drag Grabbers
            List {
                ForEach(cardOrder, id: \.self) { cardId in
                    if let card = DashboardCardRegistry.item(for: cardId) {
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(AppColors.secondaryText)
                                .font(.system(size: 14))
                            
                            Image(systemName: card.icon)
                                .font(.system(size: 14))
                                .foregroundColor(hiddenCardIds.contains(card.id) ? AppColors.secondaryText.opacity(0.5) : AppColors.brand)
                                .frame(width: 22)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.label)
                                    .font(AppTypography.body)
                                    .foregroundColor(hiddenCardIds.contains(card.id) ? AppColors.secondaryText : AppColors.primaryText)
                                Text("\(card.size.rawValue.capitalized) card")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            
                            Spacer()
                            
                            if hiddenCardIds.contains(card.id) {
                                Text("Hidden")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.secondaryBackground)
                                    .cornerRadius(4)
                            }
                        }
                        .listRowBackground(AppColors.cardBackground)
                        .listRowSeparatorTint(AppColors.border.opacity(0.6))
                    }
                }
                .onMove { source, destination in
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    cardOrder.move(fromOffsets: source, toOffset: destination)
                    activePreset = .custom
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }
}
