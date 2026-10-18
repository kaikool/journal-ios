import SwiftUI

@main
public struct TradeJournalApp: App {
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
                
                if !isAppReady {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .preferredColorScheme(env.colorScheme)
            .task {
                // Yield main thread so the primary tab canvas renders smoothly before dismissing splash
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.easeOut(duration: 0.35)) {
                    isAppReady = true
                }
            }
        }
    }
}
