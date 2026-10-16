import SwiftUI

public struct RootTabView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $env.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(AppTab.dashboard.rawValue, systemImage: AppTab.dashboard.iconName)
                }
                .tag(AppTab.dashboard)
            
            TradesListView()
                .tabItem {
                    Label(AppTab.trades.rawValue, systemImage: AppTab.trades.iconName)
                }
                .tag(AppTab.trades)
            
            ImportStatementView()
                .tabItem {
                    Label(AppTab.importStatement.rawValue, systemImage: AppTab.importStatement.iconName)
                }
                .tag(AppTab.importStatement)
            
            JournalCalendarView()
                .tabItem {
                    Label(AppTab.journal.rawValue, systemImage: AppTab.journal.iconName)
                }
                .tag(AppTab.journal)
            
            PropFirmLedgerView()
                .tabItem {
                    Label(AppTab.propFirm.rawValue, systemImage: AppTab.propFirm.iconName)
                }
                .tag(AppTab.propFirm)
            
            SettingsView()
                .tabItem {
                    Label(AppTab.settings.rawValue, systemImage: AppTab.settings.iconName)
                }
                .tag(AppTab.settings)
        }
        .tint(AppColors.accent)
    }
}

