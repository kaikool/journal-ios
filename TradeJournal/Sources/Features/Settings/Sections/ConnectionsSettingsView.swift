import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Connections Settings View (Apple HIG Inset-Grouped Standard)
// Clean 1-card layout matching Market Data Feeds: 1 row The5ers, 1 row cTrader, 1 row Exness.
// No manual token inputs (managed via GitHub Secrets & Keychain). The5ers Connect uses native OAuth.
public struct ConnectionsSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var the5ers = The5ersService.shared
    @ObservedObject private var ctrader = CTraderService.shared
    @ObservedObject private var exness = ExnessService.shared
    
    // Status & Loading State
    @State private var the5ersStatus: String = ""
    @State private var isConnectingThe5ers: Bool = false
    @State private var isPingingThe5ers: Bool = false
    
    @State private var ctraderStatus: String = ""
    @State private var isTestingCTrader: Bool = false
    
    @State private var exnessStatus: String = ""
    @State private var isTestingExness: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Card 1: Sync Center
            SettingsCard(title: "Sync Center", footer: "Manage multi-source broker synchronization and horizon filters.") {
                HStack(spacing: 8) {
                    AppButton(
                        "Open Sync Center",
                        icon: "slider.horizontal.3",
                        style: .primary,
                        size: .compact,
                        fullWidth: true
                    ) {
                        env.showSyncCenter = true
                    }
                    
                    if SyncManager.shared.isSyncing {
                        AppButton(
                            "Stop Sync",
                            icon: "stop.fill",
                            style: .destructive,
                            size: .compact,
                            fullWidth: true
                        ) {
                            SyncManager.shared.cancelSync()
                        }
                    } else {
                        AppButton(
                            "Quick Sync",
                            icon: "arrow.triangle.2.circlepath",
                            style: .secondary,
                            size: .compact,
                            fullWidth: true
                        ) {
                            Task {
                                await SyncManager.shared.performQuickSync()
                            }
                        }
                    }
                }
            }
            
            // Card 2: Broker & Prop Connections (Market Data Feed Style)
            SettingsCard(title: "Connections", footer: "Broker APIs, cTrader accounts, and prop firm feeds.") {
                VStack(spacing: 12) {
                    
                    // Row 1: The5ers
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("The5ers")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(the5ers.isConnected ? AppColors.profit : AppColors.secondaryText)
                                    .frame(width: 7, height: 7)
                                Text(the5ers.isConnected ? "Connected" : "Not connected")
                                    .font(AppTypography.caption)
                                    .foregroundColor(the5ers.isConnected ? AppColors.profit : AppColors.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if the5ers.isConnected {
                                AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact) {
                                    the5ers.disconnect()
                                    the5ersStatus = "Disconnected from The5ers."
                                }
                            } else {
                                AppButton("Connect", icon: "person.badge.key.fill", style: .primary, size: .compact, isLoading: isConnectingThe5ers) {
                                    loginThe5ersOAuth()
                                }
                            }
                            
                            AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isPingingThe5ers) {
                                pingThe5ers()
                            }
                        }
                    }
                    
                    if !the5ersStatus.isEmpty {
                        HStack {
                            Text(the5ersStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(the5ersStatus.contains("Error") || the5ersStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                            Spacer()
                        }
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.4))
                    
                    // Row 2: cTrader
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("cTrader")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                let isOnline = ctrader.isConfigured && ctrader.isConnected
                                Circle()
                                    .fill(isOnline ? AppColors.profit : (ctrader.isConfigured ? AppColors.brand : AppColors.secondaryText))
                                    .frame(width: 7, height: 7)
                                Text(isOnline ? "Connected" : (ctrader.isConfigured ? "Configured" : "Not connected"))
                                    .font(AppTypography.caption)
                                    .foregroundColor(isOnline ? AppColors.profit : (ctrader.isConfigured ? AppColors.brand : AppColors.secondaryText))
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if ctrader.isConnected {
                                AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact) {
                                    ctrader.disconnect()
                                    ctraderStatus = "cTrader disconnected."
                                }
                            } else {
                                AppButton("Connect", icon: "link", style: .primary, size: .compact, isLoading: isTestingCTrader) {
                                    testCTraderConnection()
                                }
                            }
                            
                            AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingCTrader) {
                                testCTraderConnection()
                            }
                        }
                    }
                    
                    if !ctraderStatus.isEmpty {
                        HStack {
                            Text(ctraderStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(ctraderStatus.contains("Error") || ctraderStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                            Spacer()
                        }
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.4))
                    
                    // Row 3: Exness
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Exness")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(exness.isConnected ? AppColors.profit : (exness.isConfigured ? AppColors.brand : AppColors.secondaryText))
                                    .frame(width: 7, height: 7)
                                Text(exness.isConnected ? "Connected" : (exness.isConfigured ? "Configured" : "Not connected"))
                                    .font(AppTypography.caption)
                                    .foregroundColor(exness.isConnected ? AppColors.profit : (exness.isConfigured ? AppColors.brand : AppColors.secondaryText))
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if exness.isConnected {
                                AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact) {
                                    exness.disconnect()
                                    exnessStatus = "Disconnected from Exness API."
                                }
                            } else {
                                AppButton("Connect", icon: "link", style: .primary, size: .compact, isLoading: isTestingExness) {
                                    testExnessConnection()
                                }
                            }
                            
                            AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingExness) {
                                testExnessConnection()
                            }
                        }
                    }
                    
                    if !exnessStatus.isEmpty {
                        HStack {
                            Text(exnessStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(exnessStatus.contains("Error") || exnessStatus.contains("failed") || exnessStatus.contains("Failed") ? AppColors.loss : AppColors.profit)
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            exness.loadSettings()
        }
    }
    
    // MARK: - Actions
    
    private func loginThe5ersOAuth() {
        isConnectingThe5ers = true
        the5ersStatus = "Opening The5ers authorization page..."
        Task {
            do {
                _ = try await the5ers.startOAuthLogin()
                await MainActor.run {
                    self.isConnectingThe5ers = false
                    self.the5ersStatus = "The5ers authorization successful."
                }
            } catch {
                await MainActor.run {
                    self.isConnectingThe5ers = false
                    let nsError = error as NSError
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ||
                       (nsError.domain == ASWebAuthenticationSessionErrorDomain && nsError.code == 1) {
                        self.the5ersStatus = "Login cancelled."
                    } else {
                        self.the5ersStatus = "OAuth error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func pingThe5ers() {
        guard the5ers.isConfigured else {
            the5ersStatus = "Not connected. Tap Connect to authorize."
            return
        }
        isPingingThe5ers = true
        the5ersStatus = "Pinging The5ers Hub..."
        Task {
            do {
                let res = try await the5ers.pingMcpConnection()
                await MainActor.run {
                    self.isPingingThe5ers = false
                    self.the5ersStatus = res.message
                }
            } catch {
                await MainActor.run {
                    self.isPingingThe5ers = false
                    self.the5ersStatus = "MCP connection error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func testCTraderConnection() {
        guard ctrader.isConfigured else {
            ctraderStatus = "cTrader token not configured."
            return
        }
        isTestingCTrader = true
        ctraderStatus = "Pinging cTrader Open API..."
        
        Task {
            do {
                let res = try await ctrader.testConnection()
                await MainActor.run {
                    self.isTestingCTrader = false
                    self.ctraderStatus = res.message
                    if self.ctrader.selectedAccountIds.isEmpty {
                        self.ctrader.selectedAccountIds = Set(res.accounts.map { $0.ctidTraderAccountId })
                    }
                    self.dataStore.objectWillChange.send()
                }
            } catch {
                await MainActor.run {
                    self.isTestingCTrader = false
                    self.ctraderStatus = "cTrader error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func testExnessConnection() {
        exness.loadSettings()
        guard exness.isConfigured else {
            exnessStatus = "Exness credentials not found in secrets."
            return
        }
        isTestingExness = true
        exnessStatus = "Connecting & syncing Exness..."
        
        Task {
            do {
                let res = try await exness.testConnection()
                let syncedCount = (try? await exness.syncTrades()) ?? 0
                await MainActor.run {
                    self.isTestingExness = false
                    if syncedCount > 0 {
                        self.exnessStatus = "\(res.message) • \(syncedCount) trades synced"
                    } else {
                        self.exnessStatus = res.message
                    }
                    self.dataStore.objectWillChange.send()
                }
            } catch {
                await MainActor.run {
                    self.isTestingExness = false
                    self.exnessStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
