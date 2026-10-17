import SwiftUI

public struct DashboardCardItem: Identifiable {
    public let id: String
    public let label: String
    public let icon: String
}

public enum DashboardCardRegistry {
    public static let allCards: [DashboardCardItem] = [
        DashboardCardItem(id: "widget-0", label: "Net P&L", icon: "dollarsign.circle"),
        DashboardCardItem(id: "widget-1", label: "Trade win %", icon: "percent"),
        DashboardCardItem(id: "widget-2", label: "Profit factor", icon: "scalemass"),
        DashboardCardItem(id: "widget-3", label: "Day win %", icon: "calendar.badge.clock"),
        DashboardCardItem(id: "widget-4", label: "Avg win / loss", icon: "arrow.up.arrow.down"),
        DashboardCardItem(id: "widget-5", label: "Edge Score", icon: "gauge.with.dots.needle.bottom.50percent"),
        DashboardCardItem(id: "widget-6", label: "Cumulative P&L", icon: "chart.line.uptrend.xyaxis"),
        DashboardCardItem(id: "widget-7", label: "Daily P&L", icon: "chart.bar.xaxis"),
        DashboardCardItem(id: "widget-8", label: "Calendar", icon: "calendar"),
        DashboardCardItem(id: "widget-9", label: "Activity", icon: "list.bullet.rectangle"),
        DashboardCardItem(id: "widget-10", label: "Max drawdown", icon: "chart.line.downtrend.xyaxis"),
        DashboardCardItem(id: "widget-11", label: "Streaks", icon: "flame"),
        DashboardCardItem(id: "widget-12", label: "Expectancy / trade", icon: "sum"),
        DashboardCardItem(id: "widget-13", label: "Avg duration", icon: "timer"),
        DashboardCardItem(id: "widget-14", label: "Best / worst day", icon: "trophy"),
        DashboardCardItem(id: "widget-15", label: "Trade time performance", icon: "clock")
    ]
}

/// Dashboard Customizer Sheet ported 1:1 from `components/dashboard-customizer.tsx`.
/// Allows users to search cards, toggle card visibility, show all, or restore default order.
public struct DashboardCustomizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hiddenCardIds: Set<String>
    
    @State private var searchQuery: String = ""
    
    public init(hiddenCardIds: Binding<Set<String>>) {
        self._hiddenCardIds = hiddenCardIds
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
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextField("Search cards...", text: $searchQuery)
                        .font(AppTypography.body)
                    
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
                .padding(.vertical, 10)
                
                // Quick Action Bar: Visible Count & Show all / Restore
                HStack {
                    Text("\(visibleCount) of \(DashboardCardRegistry.allCards.count) visible")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Spacer()
                    
                    Button("Show all") {
                        withAnimation {
                            hiddenCardIds.removeAll()
                        }
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brand)
                    
                    Text("·")
                        .foregroundColor(AppColors.secondaryText)
                    
                    Button("Restore default") {
                        withAnimation {
                            hiddenCardIds.removeAll()
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
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.brand)
                                .frame(width: 24)
                            
                            Text(card.label)
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.primaryText)
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { !hiddenCardIds.contains(card.id) },
                                set: { isVisible in
                                    withAnimation {
                                        if isVisible {
                                            hiddenCardIds.remove(card.id)
                                        } else {
                                            hiddenCardIds.insert(card.id)
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(AppColors.brand)
                        }
                        .listRowBackground(AppColors.cardBackground)
                        .listRowSeparatorTint(AppColors.border)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(AppColors.background)
            .navigationTitle("Dashboard cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppTypography.bodyBold)
                    .foregroundColor(AppColors.brand)
                }
            }
        }
    }
}
