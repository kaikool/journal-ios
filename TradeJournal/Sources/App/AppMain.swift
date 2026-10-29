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
            ZStack {
                RootTabView()
                    .environmentObject(env)
                    .environmentObject(dataStore)
                    .preferredColorScheme(env.colorScheme)
                
                if !dataStore.isLoaded {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: dataStore.isLoaded)
            .onAppear {
                SyncManager.shared.startPeriodicAutoSync()
                SyncManager.shared.autoSyncIfNeeded(cooldownSeconds: 5, delaySeconds: 1, force: true)
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    // Safe non-blocking background save protected by iOS UIBackgroundTask
                    dataStore.performSaveToDiskAsync(isBackgroundTrigger: true)
                    SyncManager.shared.stopPeriodicAutoSync()
                } else if newPhase == .active {
                    SyncManager.shared.startPeriodicAutoSync()
                    SyncManager.shared.autoSyncIfNeeded(cooldownSeconds: 5, delaySeconds: 0.5, force: true)
                }
            }
        }
    }
}
