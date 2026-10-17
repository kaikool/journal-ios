import SwiftUI

public struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    // Interactive drawer state for ultra-smooth fluid navigation
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    private let drawerWidth: CGFloat = 300
    
    public init() {}
    
    public var body: some View {
        let isDrawerActive = env.isDrawerOpen
        let currentOffset: CGFloat = isDrawerActive 
            ? max(-drawerWidth, min(0, dragOffset)) 
            : min(0, -drawerWidth + max(0, dragOffset))
        let progress: CGFloat = max(0, min(1, (drawerWidth + currentOffset) / drawerWidth))
        
        ZStack(alignment: .leading) {
            // Main Application Content Canvas with Layered Parallax Scale
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
            .disabled(progress > 0.1)
            
            // Native Apple Dimmed Frosted Backdrop
            if progress > 0.001 {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(Double(progress))
                    
                    Color.black
                        .opacity(0.4 * Double(progress))
                }
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        env.isDrawerOpen = false
                        dragOffset = 0
                    }
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            }
            
            // Elevated Apple HIG Translucent Drawer with Shadow
            if progress > 0.001 {
                NavigationDrawerView()
                    .frame(width: drawerWidth)
                    .offset(x: currentOffset)
                    .shadow(color: Color.black.opacity(0.3 * Double(progress)), radius: 32, x: 10, y: 0)
                    .ignoresSafeArea(.container, edges: .vertical)
            }
        }
        .preferredColorScheme(env.colorScheme)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged { value in
                    let startX = value.startLocation.x
                    let transX = value.translation.width
                    let transY = value.translation.height
                    
                    if !isDragging {
                        if !env.isDrawerOpen {
                            if startX <= 45 && transX > 10 && abs(transX) > abs(transY) * 1.2 {
                                isDragging = true
                            }
                        } else {
                            if transX < -10 && abs(transX) > abs(transY) * 1.2 {
                                isDragging = true
                            }
                        }
                    }
                    
                    if isDragging {
                        if !env.isDrawerOpen {
                            dragOffset = max(0, min(drawerWidth, transX))
                        } else {
                            dragOffset = min(0, max(-drawerWidth, transX))
                        }
                    }
                }
                .onEnded { value in
                    guard isDragging else { return }
                    isDragging = false
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    
                    if !env.isDrawerOpen {
                        if dragOffset > drawerWidth * 0.28 || velocity > 150 {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                env.isDrawerOpen = true
                                dragOffset = 0
                            }
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                dragOffset = 0
                            }
                        }
                    } else {
                        if dragOffset < -drawerWidth * 0.22 || velocity < -150 {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                env.isDrawerOpen = false
                                dragOffset = 0
                            }
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                dragOffset = 0
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
