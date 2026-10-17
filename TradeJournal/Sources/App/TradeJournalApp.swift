import SwiftUI

public struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    public var body: some View {
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
            .scaleEffect(env.isDrawerOpen ? 0.98 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: env.isDrawerOpen)
            .disabled(env.isDrawerOpen)
            
            // Dedicated Edge Pan Gesture Strip (Active only when drawer is closed)
            // Intercepts touches exclusively on the 28pt left screen bezel.
            // Never interferes with ScrollView or chart scrubbing!
            if !env.isDrawerOpen {
                LeftEdgeSwipeTrigger {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        env.isDrawerOpen = true
                    }
                }
            }
            
            // Isolated Drawer & Scrim Overlay Component
            // Drag state is isolated here so dragging does NOT re-render the main canvas or run heavy metrics!
            InteractiveDrawerOverlay()
        }
        .preferredColorScheme(env.colorScheme)
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
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
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

/// Dedicated edge swipe trigger along the 28pt left screen bezel.
private struct LeftEdgeSwipeTrigger: View {
    let onOpen: () -> Void
    
    var body: some View {
        Color.clear
            .frame(width: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onEnded { value in
                        if value.translation.width > 24 && abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                            onOpen()
                        }
                    }
            )
            .ignoresSafeArea()
    }
}

/// Isolated Drawer and Scrim Overlay.
/// Encapsulating drag offset in this view prevents RootTabView and the active screen
/// from re-rendering their bodies 120 times/second during touch drag interactions.
private struct InteractiveDrawerOverlay: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    private let drawerWidth: CGFloat = 300
    
    private var drawerXOffset: CGFloat {
        if isDragging {
            return min(0, max(-drawerWidth, dragOffset))
        } else {
            return env.isDrawerOpen ? 0 : -drawerWidth
        }
    }
    
    private var scrimOpacity: Double {
        if isDragging {
            let ratio = (drawerWidth + dragOffset) / drawerWidth
            return max(0, min(0.45, 0.45 * Double(ratio)))
        } else {
            return env.isDrawerOpen ? 0.45 : 0.0
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Scrim backdrop
            if env.isDrawerOpen || isDragging {
                Color.black
                    .opacity(scrimOpacity)
                    .ignoresSafeArea()
                    .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: env.isDrawerOpen)
                    .onTapGesture {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            env.isDrawerOpen = false
                            dragOffset = 0
                        }
                    }
            }
            
            // Drawer View with hardware-accelerated translation
            NavigationDrawerView()
                .frame(width: drawerWidth)
                .offset(x: drawerXOffset)
                .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: env.isDrawerOpen)
                .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: dragOffset)
                .shadow(
                    color: Color.black.opacity(env.isDrawerOpen || isDragging ? 0.30 : 0),
                    radius: 24,
                    x: 6,
                    y: 0
                )
                .ignoresSafeArea(.container, edges: .vertical)
        }
        .allowsHitTesting(env.isDrawerOpen || isDragging)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    guard env.isDrawerOpen else { return }
                    if !isDragging && value.translation.width < -6 {
                        isDragging = true
                    }
                    if isDragging {
                        dragOffset = min(0, max(-drawerWidth, value.translation.width))
                    }
                }
                .onEnded { value in
                    guard isDragging else { return }
                    isDragging = false
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    if dragOffset < -drawerWidth * 0.22 || velocity < -150 {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            env.isDrawerOpen = false
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}
