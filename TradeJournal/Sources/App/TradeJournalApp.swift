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

/// Isolated Interactive Drawer & Scrim Overlay with Glitch-Free Edge-Drag Tracking.
private struct InteractiveDrawerOverlay: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var dragOffset: CGFloat = 0
    
    private let drawerWidth: CGFloat = 300
    
    // Unified offset: strictly continuous from finger position to target state
    private var drawerOffset: CGFloat {
        if env.isDrawerOpen {
            // Open: dragOffset is <= 0 (user swiping left to close)
            return min(0, max(-drawerWidth, dragOffset))
        } else {
            // Closed: dragOffset is >= 0 (user dragging right to open)
            return min(0, -drawerWidth + max(0, dragOffset))
        }
    }
    
    private var scrimOpacity: Double {
        if env.isDrawerOpen {
            let progress = max(0, min(1, (drawerWidth + dragOffset) / drawerWidth))
            return Double(progress) * 0.45
        } else {
            let progress = max(0, min(1, dragOffset / drawerWidth))
            return Double(progress) * 0.45
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Scrim backdrop
            Color.black
                .opacity(scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .allowsHitTesting(env.isDrawerOpen || dragOffset > 0)
                .onTapGesture {
                    NativeHaptics.lightImpact()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        env.isDrawerOpen = false
                        dragOffset = 0
                    }
                }
            
            // Drawer View with hardware-accelerated translation
            NavigationDrawerView()
                .frame(width: drawerWidth)
                .offset(x: drawerOffset)
                .shadow(
                    color: Color.black.opacity((env.isDrawerOpen || dragOffset > 0) ? 0.22 : 0),
                    radius: 14,
                    x: 4,
                    y: 0
                )
                .ignoresSafeArea(.container, edges: .vertical)
            
            // Left Edge Swipe Sensing Strip (Only active when Drawer is closed)
            if !env.isDrawerOpen {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12, coordinateSpace: .local)
                            .onChanged { value in
                                let h = value.translation.width
                                let v = value.translation.height
                                guard h > 0, abs(h) > abs(v) * 1.15 else { return }
                                dragOffset = min(drawerWidth, max(0, h))
                            }
                            .onEnded { value in
                                let h = value.translation.width
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                let shouldOpen = h > drawerWidth * 0.25 || velocity > 180
                                if shouldOpen {
                                    NativeHaptics.lightImpact()
                                }
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    env.isDrawerOpen = shouldOpen
                                    dragOffset = 0
                                }
                            }
                    )
                    .ignoresSafeArea()
            }
        }
        // Swipe to Close gesture when drawer is open
        .gesture(
            env.isDrawerOpen ?
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    guard abs(h) > abs(v) * 1.1 else { return }
                    dragOffset = min(0, max(-drawerWidth, h))
                }
                .onEnded { value in
                    let h = value.translation.width
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let shouldClose = h < -drawerWidth * 0.22 || velocity < -160
                    if shouldClose {
                        NativeHaptics.lightImpact()
                    }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        env.isDrawerOpen = !shouldClose
                        dragOffset = 0
                    }
                } : nil
        )
        .allowsHitTesting(env.isDrawerOpen || dragOffset > 0 || !env.isDrawerOpen)
    }
}
