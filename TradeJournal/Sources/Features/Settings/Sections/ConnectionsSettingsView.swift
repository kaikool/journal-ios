import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 5. Connections Settings View
public struct ConnectionsSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var the5ers = The5ersService.shared
    @ObservedObject private var ctrader = CTraderService.shared
    @ObservedObject private var exness = ExnessService.shared
    
    @State private var the5ersStatus: String = ""
    @State private var isConnectingThe5ers: Bool = false
    @State private var showAdvancedThe5ers: Bool = false
    @State private var manualMcpToken: String = ""
    
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
    
    @State private var exnessHost: String = "https://api.exness.com"
    @State private var exnessAccountId: String = ""
    @State private var exnessApiKey: String = ""
    @State private var exnessPrivateKey: String = ""
    @State private var exnessStatus: String = ""
    @State private var isTestingExness: Bool = false
    @State private var isSyncingExness: Bool = false
    
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
                                manualMcpToken = ""
                                the5ersStatus = "Disconnected from The5ers."
                            }
                        }
                    }
                    
                    DisclosureGroup(isExpanded: $showAdvancedThe5ers) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("If OAuth login is unavailable, paste your Bearer token directly:")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            
                            SecureField("The5ers MCP Bearer Token", text: $manualMcpToken)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(AppColors.secondaryBackground)
                                .cornerRadius(8)
                            
                            HStack(spacing: 8) {
                                AppButton("Save & Ping", icon: "checkmark.circle", style: .secondary, size: .compact, fullWidth: true) {
                                    saveManualTokenAndPing()
                                }
                                
                                AppButton("Ping MCP", icon: "antenna.radiowaves.left.and.right", style: .secondary, size: .compact, fullWidth: true) {
                                    pingMcp()
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Manual Token (Advanced)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.brand)
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
            
            // Card 4: Exness REST API Connection
            SettingsCard(title: "Exness") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exness REST API")
                                .font(AppTypography.headline)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(exness.isConnected ? AppColors.profit : AppColors.secondaryText)
                                    .frame(width: 8, height: 8)
                                Text(exness.isConnected ? "Đã kết nối" : "Chưa kết nối")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(exness.isConnected ? AppColors.profit : AppColors.secondaryText)
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingExness) {
                                saveAndTestExness()
                            }
                            
                            AppButton("Sync", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, isLoading: isSyncingExness) {
                                syncExnessNow()
                            }
                            .disabled(!exness.isConnected)
                        }
                    }
                    
                    if exness.isConnected {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Số dư")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("$\(exness.balance.description)")
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Equity")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("$\(exness.equity.description)")
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.primaryText)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Đòn bẩy")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Text("1:\(exness.leverage)")
                                    .font(AppTypography.subheadlineBold)
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                    }
                    
                    if !exnessStatus.isEmpty {
                        Text(exnessStatus)
                            .font(AppTypography.caption)
                            .foregroundColor(exnessStatus.contains("Lỗi") || exnessStatus.contains("thất bại") ? AppColors.loss : AppColors.secondaryText)
                    }
                    
                    if let lastSync = exness.lastSyncDate {
                        Text("Sync lần cuối: \(Formatters.formatDateTime(lastSync))")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
        .onAppear {
            manualMcpToken = the5ers.mcpToken
            ctraderToken = ctrader.accessToken
            ctraderClientId = ctrader.clientId
            ctraderClientSecret = ctrader.clientSecret
            ctraderIsLive = ctrader.isLive
            exnessHost = exness.apiHost
            exnessAccountId = exness.accountId
            exnessApiKey = exness.apiKey
            exnessPrivateKey = exness.getStoredPrivateKey()
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
    }
    
    // MARK: - Actions
    
    private func loginThe5ersOAuth() {
        isConnectingThe5ers = true
        the5ersStatus = "Opening The5ers Hub authorization page..."
        Task {
            do {
                let token = try await the5ers.startOAuthLogin()
                await MainActor.run {
                    self.manualMcpToken = token
                    self.isConnectingThe5ers = false
                    self.the5ersStatus = "The5ers Hub authorization successful! Connected to MCP Server."
                }
            } catch {
                await MainActor.run {
                    self.isConnectingThe5ers = false
                    let nsError = error as NSError
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ||
                       (nsError.domain == ASWebAuthenticationSessionErrorDomain && nsError.code == 1) {
                        self.the5ersStatus = "Login cancelled by user."
                    } else {
                        self.the5ersStatus = "OAuth error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func saveManualTokenAndPing() {
        let clean = manualMcpToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            the5ersStatus = "Please enter a valid Bearer token."
            return
        }
        the5ers.configure(token: clean)
        the5ersStatus = "Token saved. Testing connection..."
        pingMcp()
    }
    
    private func pingMcp() {
        guard the5ers.isConfigured else {
            the5ersStatus = "The5ers MCP is not configured. Please log in or enter a token."
            return
        }
        the5ersStatus = "Sending tools/list request to The5ers MCP Server..."
        Task {
            do {
                let res = try await the5ers.pingMcpConnection()
                await MainActor.run {
                    self.the5ersStatus = res.message
                }
            } catch {
                await MainActor.run {
                    self.the5ersStatus = "MCP connection error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func syncThe5ers() {
        guard the5ers.isConfigured else {
            the5ersStatus = "Not connected to The5ers. Please connect first."
            return
        }
        the5ersStatus = "Starting synchronization with The5ers MCP Hub..."
        currentThe5ersSyncTask?.cancel()
        currentThe5ersSyncTask = Task {
            do {
                let count = try await dataStore.syncWithThe5ers()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self.the5ers.isCancelledByUser {
                        self.the5ersStatus = "Synchronization cancelled by user."
                    } else if count > 0 {
                        self.the5ersStatus = "Successfully synced \(count) accounts, expenses & payouts from The5ers!"
                    } else {
                        self.the5ersStatus = self.the5ers.lastStatus
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
    
    // MARK: - Exness Actions
    
    private func saveAndTestExness() {
        exness.loadSettings()
        isTestingExness = true
        exnessStatus = "Đang ping Exness API..."
        
        Task {
            do {
                let res = try await exness.testConnection()
                await MainActor.run {
                    self.isTestingExness = false
                    self.exnessStatus = res.message
                }
            } catch {
                await MainActor.run {
                    self.isTestingExness = false
                    self.exnessStatus = "Lỗi: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func syncExnessNow() {
        exness.loadSettings()
        isSyncingExness = true
        exnessStatus = "Đang đồng bộ dữ liệu giao dịch từ Exness API..."
        
        Task {
            do {
                let count = try await exness.syncTrades()
                await MainActor.run {
                    self.isSyncingExness = false
                    self.exnessStatus = "Đồng bộ hoàn tất qua Exness API! Cập nhật trạng thái tài khoản."
                }
            } catch {
                await MainActor.run {
                    self.isSyncingExness = false
                    self.exnessStatus = "Đồng bộ thất bại: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func disconnectExness() {
        exness.disconnect()
        exnessAccountId = ""
        exnessApiKey = ""
        exnessPrivateKey = ""
        exnessStatus = "Đã ngắt kết nối Exness API và xóa Private Key khỏi Keychain."
    }
}
