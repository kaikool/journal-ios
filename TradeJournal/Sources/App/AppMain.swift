import SwiftUI

@main
public struct TradeJournalApp: App {
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
        }
    }
}
