import SwiftUI

public struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .leading) {
            // Main Application Content Canvas with Layered Parallax Scale
            ZStack(alignment: .bottom) {
                // Layer 1: Edge-to-edge Content Canvas with translucent scroll-through header
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
                .transaction { transaction in
                    transaction.animation = nil
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Shell Header Bar with ultraThinMaterial blur (data scrolls underneath)
                    ShellHeaderView()
                }
                
                // Layer 2: Quick Bottom Bar floating with translucent glassmorphism (content glides underneath)
                bottomNavigationBar
            }
            .background(AppColors.background.ignoresSafeArea())
            .simultaneousGesture(
                DragGesture(minimumDistance: 32, coordinateSpace: .local)
                    .onEnded { value in
                        guard !env.isDrawerOpen, env.selectedTab.isPrimaryTab else { return }
                        let h = value.translation.width
                        let v = value.translation.height
                        // Must be a distinct horizontal swipe (at least 1.6x horizontal over vertical, and > 45pt)
                        guard abs(h) > abs(v) * 1.6, abs(h) > 45 else { return }
                        
                        if h < -45 {
                            // Swipe Left: Next Tab (Dashboard -> Calendar -> Journal -> Trades -> Reports)
                            env.navigateToNextTab()
                        } else if h > 45 {
                            // Swipe Right: Previous Tab (Reports -> Trades -> Journal -> Calendar -> Dashboard)
                            if env.selectedTab.previousPrimaryTab != nil {
                                env.navigateToPreviousTab()
                            } else {
                                // On Dashboard (first tab), swiping right smoothly pulls open Drawer
                                NativeHaptics.lightImpact()
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                    env.isDrawerOpen = true
                                }
                            }
                        }
                    }
            )
            
            // Dedicated Right Edge Swipe Trigger (Active on primary tabs to advance)
            HStack {
                Spacer()
                RightEdgeSwipeTrigger {
                    NativeHaptics.selection()
                    if let next = env.selectedTab.nextPrimaryTab {
                        env.selectedTab = next
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            env.isDrawerOpen = true
                        }
                    }
                }
            }
            .allowsHitTesting(!env.isDrawerOpen && env.selectedTab.isPrimaryTab)
            
            // Isolated Interactive Drawer & Scrim Overlay Component (Handles Real-time edge drag to open & drag to close)
            InteractiveDrawerOverlay()
        }
        .preferredColorScheme(env.colorScheme)
        .onAppear {
            env.applyReportingCurrency(TradeDataStore.shared.currencyConversion.reportingCurrency)
        }
        .onReceive(TradeDataStore.shared.$currencyConversion) { conversion in
            env.applyReportingCurrency(conversion.reportingCurrency)
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    env.isDrawerOpen.toggle()
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: env.isDrawerOpen ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 15, weight: .semibold))
                        .scaleEffect(env.isDrawerOpen ? 1.05 : 1.0)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: env.isDrawerOpen)
                    
                    Text("Menu")
                        .font(.system(size: 10, weight: env.isDrawerOpen ? .bold : .medium))
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
            .accessibilityLabel(env.isDrawerOpen ? "Close navigation menu" : "Open navigation menu")
            .accessibilityHint("Opens side drawer with all 13 application routes")
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
                            env.selectedTab = next
                        } else {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                env.isDrawerOpen = true
                            }
                        }
                    } else if h > 20 {
                        // Swipe Right: Previous Tab
                        if let prev = env.selectedTab.previousPrimaryTab {
                            #if canImport(UIKit)
                            UISelectionFeedbackGenerator().selectionChanged()
                            #endif
                            env.selectedTab = prev
                        } else {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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
                env.selectedTab = tab
            } else {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                NotificationCenter.default.post(name: .appScrollToTop, object: tab)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
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
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("\(label) tab")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Isolated Interactive Drawer & Scrim Overlay with Real-time Edge-Drag Tracking.
/// Encapsulating drag offset in this view prevents RootTabView and the active screen
/// from re-rendering their bodies 120 times/second during touch drag interactions.
private struct InteractiveDrawerOverlay: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    private let drawerWidth: CGFloat = 300
    
    private var drawerXOffset: CGFloat {
        if isDragging {
            if env.isDrawerOpen {
                return min(0, max(-drawerWidth, dragOffset))
            } else {
                return min(0, -drawerWidth + max(0, dragOffset))
            }
        } else {
            return env.isDrawerOpen ? 0 : -drawerWidth
        }
    }
    
    private var scrimOpacity: Double {
        if isDragging {
            let progress: CGFloat
            if env.isDrawerOpen {
                progress = max(0, min(1, (drawerWidth + dragOffset) / drawerWidth))
            } else {
                progress = max(0, min(1, dragOffset / drawerWidth))
            }
            return Double(progress) * 0.45
        } else {
            return env.isDrawerOpen ? 0.45 : 0.0
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Scrim backdrop - persistent to eliminate insertion/removal layout hitches
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()
                .animation(isDragging ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: env.isDrawerOpen)
                .contentShape(Rectangle())
                .allowsHitTesting(env.isDrawerOpen || isDragging)
                .onTapGesture {
                    NativeHaptics.lightImpact()
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        env.isDrawerOpen = false
                        dragOffset = 0
                    }
                }
            
            // Drawer View with hardware-accelerated translation
            NavigationDrawerView()
                .frame(width: drawerWidth)
                .offset(x: drawerXOffset)
                .animation(isDragging ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: env.isDrawerOpen)
                .shadow(
                    color: Color.black.opacity(env.isDrawerOpen || isDragging ? 0.22 : 0),
                    radius: 14,
                    x: 4,
                    y: 0
                )
                .ignoresSafeArea(.container, edges: .vertical)
            
            // Left Edge Swipe Sensing Zone (Only active when Drawer is closed)
            if !env.isDrawerOpen {
                Color.clear
                    .frame(width: 28)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { value in
                                let h = value.translation.width
                                let v = value.translation.height
                                guard abs(h) > abs(v) * 1.15, h > 6 else { return }
                                if !isDragging {
                                    isDragging = true
                                    NativeHaptics.lightImpact()
                                }
                                dragOffset = min(drawerWidth, max(0, h))
                            }
                            .onEnded { value in
                                guard isDragging else { return }
                                isDragging = false
                                let h = value.translation.width
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                if h > drawerWidth * 0.28 || velocity > 180 {
                                    NativeHaptics.lightImpact()
                                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                        env.isDrawerOpen = true
                                        dragOffset = 0
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        env.isDrawerOpen = false
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                    .ignoresSafeArea()
            }
        }
        .gesture(
            (env.isDrawerOpen || (isDragging && dragOffset < 0)) ?
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
                    if dragOffset < -drawerWidth * 0.24 || velocity < -150 {
                        NativeHaptics.lightImpact()
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            env.isDrawerOpen = false
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            dragOffset = 0
                        }
                    }
                } : nil
        )
        .allowsHitTesting(env.isDrawerOpen || isDragging || !env.isDrawerOpen)
    }
}
