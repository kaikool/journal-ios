import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 5. Connections Settings View
public struct ConnectionsSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var the5ers = The5ersService.shared
    @ObservedObject private var ctrader = CTraderService.shared
    
    @State private var mcpToken: String = The5ersService.shared.mcpToken
    @State private var the5ersStatus: String = ""
    @State private var isConnectingThe5ers: Bool = false
    
    @State private var ctraderToken: String = CTraderService.shared.accessToken
    @State private var ctraderClientId: String = CTraderService.shared.clientId
    @State private var ctraderClientSecret: String = CTraderService.shared.clientSecret
    @State private var ctraderIsLive: Bool = CTraderService.shared.isLive
    @State private var ctraderStatus: String = ""
    @State private var isTestingCTrader: Bool = false
    @State private var isSyncingCTrader: Bool = false
    @State private var showAdvancedCTrader: Bool = false
    @State private var currentThe5ersSyncTask: Task<Void, Never>? = nil
    @State private var currentCTraderSyncTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Sync Center Hub
            SettingsCard(title: "Sync Center") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select time horizons, filter specific accounts, and manage multi-source synchronization.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
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
            }
            
            // Card 2: The5ers Prop Firm Connection
            SettingsCard(title: "The5ers") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("The5ers Account Sync")
                            .font(AppTypography.headline)
                        Spacer()
                        Text(the5ers.isConnected ? "Connected · Active" : "Not connected")
                            .font(AppTypography.captionBold)
                            .foregroundColor(the5ers.isConnected ? AppColors.profit : AppColors.secondaryText)
                    }
                    
                    Text("Connect your The5ers account to automatically sync challenges, funded accounts, trades, and payout history.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    if !the5ers.isConnected {
                        AppButton("Connect The5ers", icon: "person.badge.key.fill", style: .primary, size: .compact, fullWidth: true, isLoading: isConnectingThe5ers) {
                            loginThe5ersOAuth()
                        }
                    } else if the5ers.isSyncing || dataStore.isSyncing {
                        AppButton("Stop Sync", icon: "stop.fill", style: .destructive, size: .compact, fullWidth: true) {
                            currentThe5ersSyncTask?.cancel()
                            currentThe5ersSyncTask = nil
                            the5ers.cancelSync()
                            dataStore.cancelSync()
                            the5ersStatus = "Synchronization cancelled by user."
                        }
                    } else {
                        HStack(spacing: 8) {
                            AppButton("Sync Now", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, fullWidth: true) {
                                syncThe5ers()
                            }
                            
                            AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact, fullWidth: true) {
                                the5ers.disconnect()
                                mcpToken = ""
                                the5ersStatus = "Disconnected from The5ers."
                            }
                        }
                    }
                    
                    if !the5ersStatus.isEmpty {
                        Text(the5ersStatus)
                            .font(AppTypography.caption)
                            .foregroundColor(the5ersStatus.contains("Error") || the5ersStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                    }
                    
                    HStack {
                        Text("The5ers accounts: \(dataStore.propAccounts.filter { $0.firm.contains("The5ers") }.count)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("Synced trades: \(dataStore.trades.filter { $0.tags.contains("the5ers") }.count)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                }
            }
            
            // Card 3: cTrader Connection
            SettingsCard(title: "cTrader") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("cTrader Account Sync")
                            .font(AppTypography.headline)
                        Spacer()
                        Text(ctrader.isConfigured ? (ctrader.isConnected ? "Connected · Active" : "Configured") : "Not configured")
                            .font(AppTypography.captionBold)
                            .foregroundColor(ctrader.isConfigured ? AppColors.profit : AppColors.secondaryText)
                    }
                    
                    Text("Sync trading accounts, historical orders, and open positions directly from cTrader.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    // Account Type (Live vs Demo)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Account Type:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Picker("Environment", selection: $ctraderIsLive) {
                            Text("Live Accounts").tag(true)
                            Text("Demo Accounts").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Access Token Field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Access Token:")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            #if canImport(UIKit)
                            Button("Paste") {
                                if let str = UIPasteboard.general.string {
                                    ctraderToken = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.brand)
                            #endif
                        }
                        
                        SecureField("Paste cTrader Access Token...", text: $ctraderToken)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        
                        Text("Obtain your Access Token from openapi.ctrader.com → Applications.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    // Optional Advanced App Credentials
                    DisclosureGroup(isExpanded: $showAdvancedCTrader) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client ID:")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                TextField("Enter Client ID", text: $ctraderClientId)
                                    .font(AppTypography.inputText)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client Secret:")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                SecureField("Enter Client Secret", text: $ctraderClientSecret)
                                    .font(AppTypography.inputText)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Custom App Credentials (Optional)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.brand)
                    }
                    
                    // Discovered Accounts List
                    if !ctrader.discoveredAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Linked Trading Accounts (\(ctrader.discoveredAccounts.count)):")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            
                            ForEach(ctrader.discoveredAccounts) { acc in
                                let isSelected = ctrader.selectedAccountIds.contains(acc.ctidTraderAccountId)
                                Button {
                                    if isSelected {
                                        ctrader.selectedAccountIds.remove(acc.ctidTraderAccountId)
                                    } else {
                                        ctrader.selectedAccountIds.insert(acc.ctidTraderAccountId)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Account: \(acc.traderLogin) • \(acc.brokerTitleShort)")
                                                .font(AppTypography.bodyBold)
                                                .foregroundColor(AppColors.primaryText)
                                            Text("\(acc.isLive ? "Live" : "Demo") • Balance: \(Formatters.formatCurrency(acc.balance, currency: acc.currency)) • 1:\(acc.leverage)")
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(AppColors.cardBackground)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        if isSyncingCTrader || ctrader.isSyncing {
                            AppButton(
                                "Stop Sync",
                                icon: "stop.fill",
                                style: .destructive,
                                size: .compact,
                                fullWidth: true
                            ) {
                                currentCTraderSyncTask?.cancel()
                                currentCTraderSyncTask = nil
                                ctrader.cancelSync()
                                isSyncingCTrader = false
                                ctraderStatus = "Synchronization cancelled."
                            }
                        } else {
                            AppButton(
                                "Sync cTrader",
                                icon: "arrow.triangle.2.circlepath",
                                style: .primary,
                                size: .compact,
                                fullWidth: true
                            ) {
                                syncCTrader()
                            }
                            .disabled(ctraderToken.trimmingCharacters(in: .whitespaces).isEmpty || isSyncingCTrader)
                        }
                        
                        AppButton(
                            "Fetch Accounts",
                            icon: "person.crop.circle.badge.checkmark",
                            style: .secondary,
                            size: .compact,
                            fullWidth: true,
                            isLoading: isTestingCTrader
                        ) {
                            testCTraderConnection()
                        }
                        .disabled(ctraderToken.trimmingCharacters(in: .whitespaces).isEmpty || isTestingCTrader || isSyncingCTrader || ctrader.isSyncing)
                        
                        if !ctraderToken.isEmpty {
                            AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact, fullWidth: true) {
                                ctraderToken = ""
                                ctraderClientId = ""
                                ctraderClientSecret = ""
                                ctrader.accessToken = ""
                                ctrader.clientId = ""
                                ctrader.clientSecret = ""
                                ctrader.disconnect()
                                ctraderStatus = "cTrader disconnected."
                            }
                        }
                    }
                    
                    if !ctraderStatus.isEmpty {
                        Text(ctraderStatus)
                            .font(AppTypography.caption)
                            .foregroundColor(ctraderStatus.contains("Error") || ctraderStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                    }
                    
                    if let lastSync = ctrader.lastSyncDate {
                        Text("Last synchronized: \(Formatters.formatDateTime(lastSync))")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
        .onAppear {
            mcpToken = the5ers.mcpToken
            ctraderToken = ctrader.accessToken
            ctraderClientId = ctrader.clientId
            ctraderClientSecret = ctrader.clientSecret
            ctraderIsLive = ctrader.isLive
        }
        .onChange(of: ctraderToken) { val in
            ctrader.accessToken = val
        }
        .onChange(of: ctraderClientId) { val in
            ctrader.clientId = val
        }
        .onChange(of: ctraderClientSecret) { val in
            ctrader.clientSecret = val
        }
        .onChange(of: ctraderIsLive) { val in
            ctrader.isLive = val
        }
        .onChange(of: mcpToken) { val in
            the5ers.configure(token: val)
        }
    }
    
    // MARK: - Actions
    
    private func loginThe5ersOAuth() {
        isConnectingThe5ers = true
        the5ersStatus = "Opening The5ers Hub authorization page..."
        Task {
            do {
                let token = try await the5ers.startOAuthLogin()
                await MainActor.run {
                    self.mcpToken = token
                    self.isConnectingThe5ers = false
                    self.the5ersStatus = "The5ers Hub authorization successful! Connected to MCP Server."
                }
            } catch {
                await MainActor.run {
                    self.isConnectingThe5ers = false
                    self.the5ersStatus = "OAuth error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func pingMcp() {
        the5ers.configure(token: mcpToken)
        the5ersStatus = "Sending tools/list request to The5ers MCP Server..."
        Task {
            do {
                let res = try await the5ers.pingMcpConnection()
                the5ersStatus = res.message
            } catch {
                the5ersStatus = "MCP connection error: \(error.localizedDescription)"
            }
        }
    }
    
    private func syncThe5ers() {
        the5ers.configure(token: mcpToken)
        the5ersStatus = "Starting synchronization with The5ers MCP Hub..."
        currentThe5ersSyncTask?.cancel()
        currentThe5ersSyncTask = Task {
            do {
                let count = try await dataStore.syncWithThe5ers()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self.the5ers.isCancelledByUser {
                        self.the5ersStatus = "Synchronization cancelled by user."
                    } else {
                        self.the5ersStatus = "Successfully synced \(count) accounts, expenses & payouts from The5ers!"
                    }
                }
                if SupabaseService.shared.isConfigured && !Task.isCancelled {
                    await dataStore.syncWithSupabase(isBackground: true)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if TradeDataStore.isCancellation(error) {
                        self.the5ersStatus = "Synchronization cancelled by user."
                    } else {
                        self.the5ersStatus = "Sync failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func testCTraderConnection() {
        ctrader.accessToken = ctraderToken
        ctrader.clientId = ctraderClientId
        ctrader.clientSecret = ctraderClientSecret
        ctrader.isLive = ctraderIsLive
        
        isTestingCTrader = true
        ctraderStatus = "Connecting to cTrader Open API..."
        
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
                if res.success && !res.accounts.isEmpty {
                    await MainActor.run {
                        self.syncCTrader()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTestingCTrader = false
                    self.ctraderStatus = "cTrader error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func syncCTrader() {
        ctrader.accessToken = ctraderToken
        ctrader.clientId = ctraderClientId
        ctrader.clientSecret = ctraderClientSecret
        ctrader.isLive = ctraderIsLive
        
        isSyncingCTrader = true
        ctraderStatus = "Starting cTrader synchronization..."
        
        currentCTraderSyncTask?.cancel()
        currentCTraderSyncTask = Task {
            do {
                let summary = try await dataStore.syncWithCTrader()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isSyncingCTrader = false
                    self.ctraderStatus = summary.message
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isSyncingCTrader = false
                    if TradeDataStore.isCancellation(error) {
                        self.ctraderStatus = "Synchronization cancelled."
                    } else {
                        self.ctraderStatus = "Sync failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
