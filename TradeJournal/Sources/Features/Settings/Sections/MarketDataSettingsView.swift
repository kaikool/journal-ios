import SwiftUI

// MARK: - 4. Market Data Settings View
// Ported 1:1 from `MarketDataSettings` in `market-data-settings.tsx`
public struct MarketDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var binanceEnabled: Bool = true
    @State private var binanceStatus: String = ""
    
    @State private var oandaToken: String = ""
    @State private var oandaAccountId: String = ""
    @State private var oandaEnvironment: String = "practice"
    @State private var oandaStatus: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Market data") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect historical prices for estimated MAE/MFE and candle replay on closed trades. Supports Binance (spot crypto) and OANDA v20 (forex, commodities & CFDs).")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    // Binance Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Binance")
                                .font(AppTypography.headline)
                            Spacer()
                            Text(binanceEnabled ? "Enabled · no key required" : "Not connected")
                                .font(AppTypography.caption)
                                .foregroundColor(binanceEnabled ? AppColors.profit : AppColors.secondaryText)
                        }
                        
                        Text("Provides cryptocurrency price candles for trade replay. No account or API key required.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack(spacing: 8) {
                            if !binanceEnabled {
                                AppButton("Enable", icon: "checkmark.circle", style: .primary, size: .compact) {
                                    binanceEnabled = true
                                    dataStore.marketConnections.binanceEnabled = true
                                    dataStore.saveToDisk()
                                    binanceStatus = "Market data enabled."
                                }
                            } else {
                                AppButton("Test Connection", icon: "network", style: .secondary, size: .compact) {
                                    testBinance()
                                }
                                
                                AppButton("Disable", icon: "xmark.circle", style: .destructive, size: .compact) {
                                    binanceEnabled = false
                                    dataStore.marketConnections.binanceEnabled = false
                                    dataStore.saveToDisk()
                                    binanceStatus = "Connection removed."
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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("OANDA")
                                .font(AppTypography.headline)
                            Spacer()
                            Text(!dataStore.marketConnections.oandaApiKey.isEmpty ? "Connected · Active" : "Not connected")
                                .font(AppTypography.captionBold)
                                .foregroundColor(!dataStore.marketConnections.oandaApiKey.isEmpty ? AppColors.profit : AppColors.secondaryText)
                        }
                        
                        Text("Provides Forex and CFD market candles for trade replay and chart analysis. Credentials are encrypted locally.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access token").font(AppTypography.captionBold)
                            SecureField("Enter access token", text: $oandaToken)
                                .font(AppTypography.inputText)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("v20 account ID").font(AppTypography.captionBold)
                            TextField("Enter v20 account ID", text: $oandaAccountId)
                                .font(AppTypography.inputText)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Environment").font(AppTypography.captionBold)
                            Picker("Environment", selection: $oandaEnvironment) {
                                Text("Practice").tag("practice")
                                Text("Live").tag("live")
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        HStack(spacing: 8) {
                            AppButton(!dataStore.marketConnections.oandaApiKey.isEmpty ? "Save" : "Save credentials", icon: "checkmark", style: .primary, size: .compact) {
                                dataStore.marketConnections.oandaApiKey = oandaToken
                                dataStore.marketConnections.oandaAccountId = oandaAccountId
                                dataStore.marketConnections.oandaEnvironment = oandaEnvironment
                                dataStore.saveToDisk()
                                oandaStatus = "Credentials saved. Test connection to verify access."
                            }
                            
                            if !dataStore.marketConnections.oandaApiKey.isEmpty {
                                AppButton("Test Connection", icon: "network", style: .secondary, size: .compact) {
                                    oandaStatus = "Connecting to OANDA v20 servers..."
                                    Task {
                                        let res = await MarketDataService.shared.testOandaConnection(
                                            apiKey: oandaToken,
                                            accountId: oandaAccountId,
                                            environment: oandaEnvironment
                                        )
                                        oandaStatus = res.message
                                    }
                                }
                                
                                AppButton("Remove", icon: "trash", style: .destructive, size: .compact) {
                                    oandaToken = ""
                                    oandaAccountId = ""
                                    dataStore.marketConnections.oandaApiKey = ""
                                    dataStore.marketConnections.oandaAccountId = ""
                                    dataStore.saveToDisk()
                                    oandaStatus = "Connection removed."
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
            oandaToken = dataStore.marketConnections.oandaApiKey
            oandaAccountId = dataStore.marketConnections.oandaAccountId
            oandaEnvironment = dataStore.marketConnections.oandaEnvironment
        }
    }
    
    private func testBinance() {
        binanceStatus = "Verifying connection to Binance Public Klines API..."
        Task {
            let res = await MarketDataService.shared.testBinanceConnection()
            binanceStatus = res.message
        }
    }
}
