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
                    NativeHaptics.light()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        env.isDrawerOpen.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppColors.secondaryBackground.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .stroke(AppColors.border.opacity(0.55), lineWidth: 0.6)
                            )
                        
                        LogoMarkView(size: 24)
                    }
                    .contentShape(Circle())
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
            
            // Collapsible In-Header Search Bar (Expands smoothly on demand)
            if env.isSearchActive && hasSearchCapability {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
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
                .background(AppColors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
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
            NativeHaptics.medium()
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
            NativeHaptics.medium()
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
            NativeHaptics.light()
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
            NativeHaptics.medium()
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
