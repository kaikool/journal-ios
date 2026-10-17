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
            bottomBarItem(tab: .dashboard, label: "Dashboard", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill")
            bottomBarItem(tab: .calendar, label: "Calendar", icon: "calendar", selectedIcon: "calendar.badge.clock")
            bottomBarItem(tab: .journal, label: "Journal", icon: "book.closed", selectedIcon: "book.closed.fill")
            bottomBarItem(tab: .trades, label: "Trades", icon: "list.bullet.rectangle", selectedIcon: "list.bullet.rectangle.fill")
            bottomBarItem(tab: .reports, label: "Reports", icon: "chart.bar", selectedIcon: "chart.bar.xaxis")
            
            // Menu / More button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Menu")
                        .font(.system(size: 10, weight: env.isDrawerOpen ? .bold : .medium))
                }
                .foregroundColor(env.isDrawerOpen ? AppColors.brand : AppColors.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(AppColors.border.opacity(0.4)),
            alignment: .top
        )
    }
    
    private func bottomBarItem(tab: AppTab, label: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = env.selectedTab == tab
        
        return Button {
            if !isSelected {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    env.selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSelected)
                
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
}
