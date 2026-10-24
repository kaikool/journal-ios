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
                    ZStack {
                        AppColors.background.ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(AppColors.brand)
                            ProgressView()
                                .tint(AppColors.brand)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: dataStore.isLoaded)
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    // Safe non-blocking background save protected by iOS UIBackgroundTask
                    dataStore.performSaveToDiskAsync(isBackgroundTrigger: true)
                }
            }
        }
    }
}
