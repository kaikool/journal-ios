import SwiftUI

// MARK: - 8. Market Data Settings View
// Simple Apple HIG settings view: Binance Public Feed & OANDA Candles.
public struct MarketDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var binanceEnabled: Bool = true
    @State private var binanceStatus: String = ""
    @State private var oandaStatus: String = ""
    
    public init() {}
    
    private var isOandaConfigured: Bool {
        let key = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? dataStore.marketConnections.oandaApiKey
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            SettingsCard(title: "Market Data Feeds") {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Binance Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Binance (Crypto)")
                                    .font(AppTypography.headline)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(binanceEnabled ? AppColors.profit : AppColors.secondaryText)
                                        .frame(width: 8, height: 8)
                                    Text(binanceEnabled ? "Đã kết nối" : "Tắt")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(binanceEnabled ? AppColors.profit : AppColors.secondaryText)
                                }
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Toggle("", isOn: $binanceEnabled)
                                    .labelsHidden()
                                    .onChange(of: binanceEnabled) {
                                        dataStore.marketConnections.binanceEnabled = binanceEnabled
                                        dataStore.saveToDisk()
                                    }
                                
                                AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact) {
                                    testBinance()
                                }
                            }
                        }
                        
                        if !binanceStatus.isEmpty {
                            Text(binanceStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    
                    // OANDA Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("OANDA (Forex & Vàng)")
                                    .font(AppTypography.headline)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(isOandaConfigured ? AppColors.profit : AppColors.secondaryText)
                                        .frame(width: 8, height: 8)
                                    Text(isOandaConfigured ? "Đã kết nối" : "Chưa kết nối")
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(isOandaConfigured ? AppColors.profit : AppColors.secondaryText)
                                }
                            }
                            Spacer()
                            AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact) {
                                oandaStatus = "Đang ping..."
                                Task {
                                    let key = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? dataStore.marketConnections.oandaApiKey
                                    let acc = UserDefaults.standard.string(forKey: "oanda_account_id") ?? AppSecretsLoader.loadSecret(named: "OANDA_ACCOUNT_ID") ?? dataStore.marketConnections.oandaAccountId
                                    let res = await MarketDataService.shared.testOandaConnection(
                                        apiKey: key,
                                        accountId: acc,
                                        environment: dataStore.marketConnections.oandaEnvironment
                                    )
                                    oandaStatus = res.message
                                }
                            }
                        }
                        
                        if !oandaStatus.isEmpty {
                            Text(oandaStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                }
            }
        }
        .onAppear {
            binanceEnabled = dataStore.marketConnections.binanceEnabled
        }
    }
    
    private func testBinance() {
        binanceStatus = "Đang ping..."
        Task {
            let res = await MarketDataService.shared.testBinanceConnection()
            binanceStatus = res.message
        }
    }
}
