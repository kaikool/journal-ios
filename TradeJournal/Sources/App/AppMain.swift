import SwiftUI

@main
public struct TradeJournalApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var env = AppEnvironment.shared
    @StateObject private var dataStore = TradeDataStore.shared
    @State private var isAppReady: Bool = false
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(env)
                .environmentObject(dataStore)
                .preferredColorScheme(env.colorScheme)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background {
                        dataStore.saveToDisk(immediate: true)
                        SyncManager.shared.scheduleBackgroundCloudBackup(delaySeconds: 1)
                    }
                }
        }
    }
}
