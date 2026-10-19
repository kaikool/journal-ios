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
                
                // Real-time synchronization notification banner
                GlobalSyncBannerView()
                
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
                .simultaneousGesture(
                    // Horizontal swipe across primary tabs with strict horizontal dominance
                    DragGesture(minimumDistance: 35, coordinateSpace: .local)
                        .onEnded { value in
                            guard env.selectedTab.isPrimaryTab, !env.isDrawerOpen else { return }
                            let h = value.translation.width
                            let v = value.translation.height
                            // Must be predominantly horizontal to avoid conflicting with vertical scroll
                            guard abs(h) > 55 && abs(h) > abs(v) * 2.2 else { return }
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            if h < -50 || velocity < -140 {
                                env.navigateToNextTab()
                            } else if h > 50 || velocity > 140 {
                                if env.selectedTab == .dashboard {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        env.isDrawerOpen = true
                                    }
                                } else {
                                    env.navigateToPreviousTab()
                                }
                            }
                        }
                )
                
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
            
            // Dedicated Right Edge Swipe Trigger (Active on primary tabs to advance)
            if !env.isDrawerOpen && env.selectedTab.isPrimaryTab {
                HStack {
                    Spacer()
                    RightEdgeSwipeTrigger {
                        #if canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        if let next = env.selectedTab.nextPrimaryTab {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                env.selectedTab = next
                            }
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                env.isDrawerOpen = true
                            }
                        }
                    }
                }
            }
            
            // Isolated Drawer & Scrim Overlay Component
            // Drag state is isolated here so dragging does NOT re-render the main canvas or run heavy metrics!
            InteractiveDrawerOverlay()
        }
        .preferredColorScheme(env.colorScheme)
        .sheet(isPresented: $env.showSyncCenter) {
            SyncCenterSheet()
        }
    }
    
    private var bottomNavigationBar: some View {
        HStack(spacing: 2) {
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
                    Image(systemName: env.isDrawerOpen ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 15, weight: .semibold))
                        .scaleEffect(env.isDrawerOpen ? 1.05 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: env.isDrawerOpen)
                    
                    Text("Menu")
                        .font(.system(size: 9.5, weight: env.isDrawerOpen ? .bold : .medium, design: .rounded))
                        .lineLimit(1)
                    
                    Circle()
                        .fill(env.isDrawerOpen ? AppColors.brand : Color.clear)
                        .frame(width: 3.5, height: 3.5)
                }
                .foregroundColor(env.isDrawerOpen ? AppColors.brand : AppColors.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(env.isDrawerOpen ? AppColors.brand.opacity(env.colorScheme == .dark ? 0.18 : 0.10) : Color.clear)
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(env.colorScheme == .dark ? 0.22 : 0.45),
                            Color.white.opacity(env.colorScheme == .dark ? 0.05 : 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(env.colorScheme == .dark ? 0.36 : 0.10), radius: 20, x: 0, y: 8)
        .shadow(color: AppColors.brand.opacity(env.colorScheme == .dark ? 0.06 : 0.02), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .gesture(
            DragGesture(minimumDistance: 15, coordinateSpace: .local)
                .onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    guard abs(h) > abs(v) * 1.3 && abs(h) > 20 else { return }
                    
                    if h < -20 {
                        // Swipe Left: Next Tab
                        if let next = env.selectedTab.nextPrimaryTab {
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                env.selectedTab = next
                            }
                        } else {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                env.isDrawerOpen = true
                            }
                        }
                    } else if h > 20 {
                        // Swipe Right: Previous Tab
                        if let prev = env.selectedTab.previousPrimaryTab {
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                env.selectedTab = prev
                            }
                        } else {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                env.isDrawerOpen = true
                            }
                        }
                    }
                }
        )
    }
    
    private func bottomBarItem(tab: AppTab, label: String, icon: String, selectedIcon: String) -> some View {
        let isSelected = env.selectedTab == tab
        
        return Button {
            if !isSelected {
                #if os(iOS)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    env.selectedTab = tab
                }
            } else {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                NotificationCenter.default.post(name: .appScrollToTop, object: tab)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 15.5, weight: isSelected ? .semibold : .regular))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isSelected)
                
                Text(label)
                    .font(.system(size: 9.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                
                Circle()
                    .fill(isSelected ? AppColors.brand : Color.clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AppColors.brand.opacity(env.colorScheme == .dark ? 0.18 : 0.10) : Color.clear)
            )
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
