import SwiftUI

public struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                // Shell Header Bar matching Shell.tsx mobile header
                ShellHeaderView()
                
                // Screen body based on active route
                ZStack {
                    switch env.selectedTab {
                    case .dashboard:
                        DashboardView()
                    case .calendar:
                        JournalCalendarView()
                    case .journal:
                        DailyJournalListView()
                    case .trades:
                        TradesListView()
                    case .reports:
                        ReportsView()
                    case .propFirms:
                        PropFirmTrackerView()
                    case .notebook:
                        NotebookView()
                    case .playbooks:
                        PlaybooksView()
                    case .progress:
                        ProgressRoutinesView()
                    case .missed:
                        MissedTradesView()
                    case .importTrades:
                        ImportStatementView()
                    case .accounts:
                        AccountsManagerView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Quick Bottom Bar for thumb navigation matching Apple HIG
                bottomNavigationBar
            }
            .background(AppColors.background.ignoresSafeArea())
            
            // Navigation Drawer overlay with all 13 routes from Shell.tsx
            NavigationDrawerView()
        }
        .preferredColorScheme(env.colorScheme)
        .gesture(
            DragGesture(minimumDistance: 15, coordinateSpace: .global)
                .onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    // Ensure primarily horizontal swipe gesture
                    if abs(h) > abs(v) * 1.3 {
                        if !env.isDrawerOpen && value.startLocation.x <= 45 && h > 40 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                env.isDrawerOpen = true
                            }
                        } else if env.isDrawerOpen && h < -40 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                env.isDrawerOpen = false
                            }
                        }
                    }
                }
        )
    }
    
    private var bottomNavigationBar: some View {
        HStack(spacing: 0) {
            bottomBarItem(tab: .dashboard, label: "Dashboard", icon: "square.grid.2x2")
            bottomBarItem(tab: .calendar, label: "Calendar", icon: "calendar")
            bottomBarItem(tab: .journal, label: "Journal", icon: "book.closed")
            bottomBarItem(tab: .trades, label: "Trades", icon: "list.number")
            bottomBarItem(tab: .reports, label: "Reports", icon: "chart.bar.xaxis")
            
            // Menu / More button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Menu")
                        .font(AppTypography.badge)
                }
                .foregroundColor(env.isDrawerOpen ? AppColors.brand : AppColors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 4)
        .background(AppColors.cardBackground)
        .overlay(
            Divider().background(AppColors.border),
            alignment: .top
        )
    }
    
    private func bottomBarItem(tab: AppTab, label: String, icon: String) -> some View {
        let isSelected = env.selectedTab == tab
        
        return Button {
            env.selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                Text(label)
                    .font(isSelected ? AppTypography.captionBold : AppTypography.badge)
            }
            .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
