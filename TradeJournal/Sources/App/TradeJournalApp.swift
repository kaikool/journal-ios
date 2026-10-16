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
            
            TradesHubView()
                .tabItem {
                    Label(AppTab.trades.rawValue, systemImage: AppTab.trades.iconName)
                }
                .tag(AppTab.trades)
            
            JournalHubView()
                .tabItem {
                    Label(AppTab.journal.rawValue, systemImage: AppTab.journal.iconName)
                }
                .tag(AppTab.journal)
            
            AnalyticsHubView()
                .tabItem {
                    Label(AppTab.analytics.rawValue, systemImage: AppTab.analytics.iconName)
                }
                .tag(AppTab.analytics)
            
            SettingsHubView()
                .tabItem {
                    Label(AppTab.settings.rawValue, systemImage: AppTab.settings.iconName)
                }
                .tag(AppTab.settings)
        }
        .tint(AppColors.accent)
    }
}

