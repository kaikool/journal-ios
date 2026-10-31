import SwiftUI

/// Unified Modern Top Navigation Bar conforming to Apple Human Interface Guidelines:
/// - Brand logo emblem button as the primary drawer navigation trigger
/// - Clean, confident page identity title (18pt bold rounded typography)
/// - Quick AI Scanner action button for instant pre-trade analysis from any screen
/// - Sleek, understated Apple background with hairline bottom separator
public struct ShellHeaderView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showPreTradeAnalysis: Bool = false
    
    public init() {}
    
    private var currentTabTitle: String {
        switch env.selectedTab {
        case .dashboard: return "Dashboard"
        case .calendar: return "Calendar"
        case .journal: return "Daily Journal"
        case .trades: return "Trades"
        case .reports: return "Analytics"
        case .propFirms: return "Prop Firms"
        case .notebook: return "Notebook"
        case .playbooks: return "Playbooks"
        case .progress: return "Progress"
        case .missed: return "Missed Trades"
        case .importTrades: return "Import Trades"
        case .accounts: return "Accounts"
        case .settings: return "Settings"
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Leading: App Brand Logo Button as Drawer Menu Trigger
                Button {
                    NativeHaptics.lightImpact()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        env.isDrawerOpen.toggle()
                    }
                } label: {
                    LogoMarkView(size: 26)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ApplePressableButtonStyle())
                .accessibilityLabel("Open navigation menu")
                
                // Current Page Title: Clean rounded typography
                Text(currentTabTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                
                Spacer(minLength: 6)
                
                // Dynamic Trailing Actions by Page Purpose
                trailingActionSlot
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            
            // Row 2: Dynamic Sub-Bar Slot (Seamlessly inside the same frosted glass container)
            if hasSubBar {
                subBarSlot
            }
            
            // Row 3: Collapsible In-Header Search Bar (Expands smoothly on demand)
            if env.isSearchActive && hasSearchCapability {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                    TextField("Search...", text: $env.searchQuery)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(AppColors.primaryText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !env.searchQuery.isEmpty {
                        Button {
                            env.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(AppColors.secondaryBackground.opacity(0.85))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppColors.border.opacity(0.9), lineWidth: 1.0)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.border.opacity(0.35))
                .frame(height: 0.5)
        }
        .sheet(isPresented: $showPreTradeAnalysis) {
            PreTradeAnalysisSheet(initialSymbol: "XAUUSD")
        }
    }
    
    private var hasSubBar: Bool {
        switch env.selectedTab {
        case .settings, .reports, .propFirms, .notebook, .calendar, .accounts:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Sub-Bar Slots (100% Unified Translucency)
    
    @ViewBuilder
    private var subBarSlot: some View {
        switch env.selectedTab {
        case .calendar:
            calendarMonthSubBar
        case .settings:
            settingsSegmentedSubBar
        case .reports:
            reportsSegmentedSubBar
        case .accounts:
            accountsSegmentedSubBar
        case .propFirms:
            propFirmsSegmentedSubBar
        case .notebook:
            notebookFoldersSubBar
        default:
            EmptyView()
        }
    }
    
    private var calendarMonthSubBar: some View {
        HStack {
            Button {
                NativeHaptics.lightImpact()
                env.changeCalendarMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 32, height: 32)
                    .background(AppColors.secondaryBackground.opacity(0.75))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.border.opacity(0.6), lineWidth: 0.5))
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Previous month")
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.brand)
                Text(Formatters.formatMonthYear(env.calendarCurrentMonth, timeZone: env.currentTimeZone))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(AppColors.secondaryBackground.opacity(0.75))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AppColors.border.opacity(0.6), lineWidth: 0.6)
            )
            
            Spacer()
            
            Button {
                NativeHaptics.lightImpact()
                env.changeCalendarMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 32, height: 32)
                    .background(AppColors.secondaryBackground.opacity(0.75))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.border.opacity(0.6), lineWidth: 0.5))
            }
            .buttonStyle(ApplePressableButtonStyle())
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var settingsSegmentedSubBar: some View {
        AppleSlidingSegmentedBar(
            selection: $env.settingsActiveSection,
            items: SettingsSection.allCases,
            titleFor: { $0.label },
            iconFor: { $0.iconName },
            isScrollable: true
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
    
    private var reportsSegmentedSubBar: some View {
        AppleSlidingSegmentedBar(
            selection: $env.reportsActiveMode,
            items: ReportMode.allCases,
            titleFor: { $0.rawValue },
            iconFor: { $0.iconName },
            isScrollable: true
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
    
    private var accountsSegmentedSubBar: some View {
        AppleSlidingSegmentedBar(
            selection: $env.accountFilterTab,
            items: AccountFilterTab.allCases,
            titleFor: { $0.rawValue },
            badgeCountFor: { tab in
                switch tab {
                case .default: return dataStore.accounts.filter { $0.id == dataStore.defaultAccountId }.count
                case .active: return dataStore.accounts.filter { $0.archivedAt == nil }.count
                case .visible: return dataStore.visibleAccounts.count
                case .all: return dataStore.accounts.count
                }
            }
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
    
    private var propFirmsSegmentedSubBar: some View {
        AppleSlidingSegmentedBar(
            selection: $env.propLedgerTab,
            items: PropLedgerTab.allCases,
            titleFor: { $0.rawValue }
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
    
    private var notebookFoldersSubBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dataStore.notebookFolders) { folder in
                    let isSelected = (env.notebookFolderId == folder.id) || (env.notebookFolderId == nil && folder.id == NotebookEngine.systemFolderAll)
                    Button {
                        NativeHaptics.selection()
                        env.notebookFolderId = (folder.id == NotebookEngine.systemFolderAll) ? nil : folder.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isSelected ? "folder.fill" : "folder")
                                .font(.system(size: 11))
                            Text(folder.name)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSelected ? AppColors.brand : AppColors.secondaryBackground.opacity(0.75))
                        .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSelected ? AppColors.brand : AppColors.border.opacity(0.6), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Trailing Action Slot by Page Context
    
    private var hasSearchCapability: Bool {
        env.selectedTab == .trades || env.selectedTab == .notebook || env.selectedTab == .missed || env.selectedTab == .journal
    }
    
    @ViewBuilder
    private var trailingActionSlot: some View {
        HStack(spacing: 8) {
            // Optional Search Toggle Button for Searchable Screens
            if hasSearchCapability {
                searchToggleButton
            }
            
            switch env.selectedTab {
            case .dashboard:
                syncActionButton
                aiScannerButton
                
            case .trades:
                syncActionButton
                
            case .journal:
                primaryActionButton(title: "Today", icon: "sun.max.fill") {
                    env.requestOpenTodayJournal = true
                }
                
            case .playbooks:
                primaryActionButton(title: "Playbook", icon: "plus") {
                    env.requestNewPlaybook = true
                }
                
            case .notebook:
                primaryActionButton(title: "Note", icon: "plus") {
                    env.requestNewNote = true
                }
                
            case .missed:
                primaryActionButton(title: "Missed", icon: "plus") {
                    env.requestNewMissedTrade = true
                }
                
            case .accounts:
                primaryActionButton(title: "Account", icon: "plus") {
                    env.requestNewAccount = true
                }
                
            case .progress:
                primaryActionButton(title: "Routine", icon: "plus") {
                    env.requestNewRoutine = true
                }
                
            case .reports:
                primaryActionButton(title: "Ask AI", icon: "sparkles") {
                    showPreTradeAnalysis = true
                }
                
            case .propFirms:
                syncActionButton
                
            default:
                aiScannerButton
            }
        }
    }
    
    // MARK: - Reusable Standardized Buttons
    
    private func primaryActionButton(title: String, icon: String = "plus", action: @escaping () -> Void) -> some View {
        Button {
            NativeHaptics.mediumImpact()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(AppColors.brand)
            .clipShape(Capsule())
            .shadow(color: AppColors.brand.opacity(0.3), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
    
    private var syncActionButton: some View {
        Button {
            NativeHaptics.mediumImpact()
            Task {
                await dataStore.performGlobalSync()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(dataStore.isSyncing ? 360 : 0))
                    .animation(dataStore.isSyncing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: dataStore.isSyncing)
                Text(dataStore.isSyncing ? "Syncing" : "Sync")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(AppColors.brand)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(AppColors.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AppColors.brand.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(ApplePressableButtonStyle())
        .disabled(dataStore.isSyncing)
    }
    
    private var searchToggleButton: some View {
        Button {
            NativeHaptics.lightImpact()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                env.isSearchActive.toggle()
                if !env.isSearchActive {
                    env.searchQuery = ""
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(env.isSearchActive ? AppColors.brand.opacity(0.18) : AppColors.cardBackground)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(env.isSearchActive ? AppColors.brand : AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                Image(systemName: env.isSearchActive ? "xmark" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(env.isSearchActive ? AppColors.brand : AppColors.secondaryText)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
    }
    
    // MARK: - Trailing Action Buttons
    
    private var aiScannerButton: some View {
        Button {
            NativeHaptics.mediumImpact()
            showPreTradeAnalysis = true
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.secondaryBackground.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                    )
                
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.brand)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ApplePressableButtonStyle())
        .accessibilityLabel("Open AI Pre-Trade Analysis")
    }
}
