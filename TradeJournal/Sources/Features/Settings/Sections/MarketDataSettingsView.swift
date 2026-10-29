import SwiftUI

// MARK: - Market Data Settings View (Apple HIG Inset-Grouped Standard)
public struct MarketDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var binanceEnabled: Bool = true
    @State private var binanceStatus: String = ""
    @State private var oandaStatus: String = ""
    @State private var isTestingBinance: Bool = false
    @State private var isTestingOanda: Bool = false
    
    public init() {}
    
    private var isOandaConfigured: Bool {
        let key = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? dataStore.marketConnections.oandaApiKey
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Market Data Feeds", footer: "Market feeds for replay and trade analytics.") {
                VStack(spacing: 12) {
                    // Binance Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Binance")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(binanceEnabled ? AppColors.profit : AppColors.secondaryText)
                                    .frame(width: 7, height: 7)
                                Text(binanceEnabled ? "Connected" : "Disabled")
                                    .font(AppTypography.caption)
                                    .foregroundColor(binanceEnabled ? AppColors.profit : AppColors.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 10) {
                            Toggle("", isOn: $binanceEnabled)
                                .labelsHidden()
                                .onChange(of: binanceEnabled) { val in
                                    dataStore.marketConnections.binanceEnabled = val
                                    dataStore.saveToDisk()
                                }
                            
                            AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingBinance) {
                                testBinance()
                            }
                        }
                    }
                    
                    if !binanceStatus.isEmpty {
                        HStack {
                            Text(binanceStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(binanceStatus.contains("Error") || binanceStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                            Spacer()
                        }
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.4))
                    
                    // OANDA Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OANDA")
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(isOandaConfigured ? AppColors.profit : AppColors.secondaryText)
                                    .frame(width: 7, height: 7)
                                Text(isOandaConfigured ? "Connected" : "Not configured")
                                    .font(AppTypography.caption)
                                    .foregroundColor(isOandaConfigured ? AppColors.profit : AppColors.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingOanda) {
                            testOanda()
                        }
                    }
                    
                    if !oandaStatus.isEmpty {
                        HStack {
                            Text(oandaStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(oandaStatus.contains("Error") || oandaStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            binanceEnabled = dataStore.marketConnections.binanceEnabled
        }
    }
    
    private func testBinance() {
        isTestingBinance = true
        binanceStatus = "Pinging Binance API..."
        Task {
            let res = await MarketDataService.shared.testBinanceConnection()
            await MainActor.run {
                self.isTestingBinance = false
                self.binanceStatus = res.message
            }
        }
    }
    
    private func testOanda() {
        isTestingOanda = true
        oandaStatus = "Pinging OANDA API..."
        Task {
            let key = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? dataStore.marketConnections.oandaApiKey
            let acc = UserDefaults.standard.string(forKey: "oanda_account_id") ?? AppSecretsLoader.loadSecret(named: "OANDA_ACCOUNT_ID") ?? dataStore.marketConnections.oandaAccountId
            let res = await MarketDataService.shared.testOandaConnection(
                apiKey: key,
                accountId: acc,
                environment: dataStore.marketConnections.oandaEnvironment
            )
            await MainActor.run {
                self.isTestingOanda = false
                self.oandaStatus = res.message
            }
        }
    }
}
