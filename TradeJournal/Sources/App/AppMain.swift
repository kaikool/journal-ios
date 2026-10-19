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
                if isAppReady && dataStore.isLoaded {
                    RootTabView()
                        .environmentObject(env)
                        .environmentObject(dataStore)
                        .transition(.opacity)
                } else {
                    SplashScreenView()
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(env.colorScheme)
            .task {
                // Asynchronously await store disk hydration off the main actor
                await dataStore.ensureHydrated()
                
                // Allow a brief, polished splash visibility threshold (300ms)
                // so the user experiences an instant, branded launch without visual stutter
                try? await Task.sleep(nanoseconds: 300_000_000)
                
                withAnimation(.easeOut(duration: 0.35)) {
                    isAppReady = true
                }
            }
        }
    }
}
