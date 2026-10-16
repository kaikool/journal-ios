import SwiftUI

@main
public struct TradeJournalApp: App {
    @StateObject private var env = AppEnvironment.shared
    @StateObject private var dataStore = TradeDataStore.shared
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(env)
                .environmentObject(dataStore)
        }
    }
}
