import SwiftUI

// MARK: - Market Data Settings View (Apple HIG Inset-Grouped Standard)
public struct MarketDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var alertEngine = MarketAlertEngine.shared
    
    @State private var binanceEnabled: Bool = true
    @State private var binanceStatus: String = ""
    @State private var oandaStatus: String = ""
    @State private var isTestingBinance: Bool = false
    @State private var isTestingOanda: Bool = false
    @State private var isCheckingAlerts: Bool = false
    @State private var alertCheckStatus: String = ""
    @State private var isWatchlistExpanded: Bool = false
    
    public init() {}
    
    private var isOandaConfigured: Bool {
        let key = KeychainManager.get(forKey: "oanda_api_key") ?? AppSecretsLoader.loadSecret(named: "OANDA_API_KEY") ?? dataStore.marketConnections.oandaApiKey
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var customTradeHistorySymbols: [String] {
        let preset = Set(["XAUUSD", "XAGUSD", "USOIL", "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "US30", "NAS100", "SPX500", "BTCUSD", "ETHUSD", "SOLUSD"])
        let traded = dataStore.trades.map { $0.symbol.uppercased() }
        let unique = Array(Set(traded)).filter { !preset.contains($0) && !$0.isEmpty }
        return unique.sorted()
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Market Data Feeds", footer: "Market feeds for replay and trade analytics.") {
                VStack(spacing: 12) {
                    // Binance Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Binance")
                                .font(AppTypography.rowPrimary)
                                .foregroundColor(AppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(AppColors.profit)
                                    .frame(width: 7, height: 7)
                                Text("Connected")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.profit)
                            }
                        }
                        
                        Spacer()
                        
                        AppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingBinance) {
                            testBinance()
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
                                .font(AppTypography.rowPrimary)
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
            
            // Unified Candle Hub & Key Level Alerts Card
            SettingsCard(
                title: "Key Level & Market Structure Alerts",
                footer: "Evaluates closed bars (:01s boundary) for Key Level (PDH, PDL, Swing High/Low) touches & breakouts via Unified Candle Hub. Eliminates redundant streaming."
            ) {
                VStack(spacing: 12) {
                    AppToggleRow(
                        "Enable Key Level Alerts",
                        subtitle: "Alerts when candle tests or breaks Key Levels (PDH, PDL, Swing High/Low)",
                        isOn: $alertEngine.isEnabled
                    ) { enabled in
                        if enabled {
                            Task {
                                _ = await alertEngine.requestNotificationPermission()
                            }
                        }
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.4))
                    
                    // Collapsible Monitored Symbols Section
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Monitored Symbols")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                Text("(\(alertEngine.monitoredSymbols.count))")
                                    .font(AppTypography.captionMicro)
                                    .foregroundColor(AppColors.brand)
                            }
                            
                            Text(alertEngine.monitoredSymbols.joined(separator: ", "))
                                .font(AppTypography.rowPrimary)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: isWatchlistExpanded ? "chevron.up" : "chevron.down")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NativeHaptics.lightImpact()
                        withAnimation(AppAnimations.springQuick) {
                            isWatchlistExpanded.toggle()
                        }
                    }
                    
                    if isWatchlistExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            symbolCategoryRow(title: "Metals & Energy", symbols: ["XAUUSD", "XAGUSD", "USOIL"])
                            symbolCategoryRow(title: "Major Forex", symbols: ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF"])
                            symbolCategoryRow(title: "Indices", symbols: ["US30", "NAS100", "SPX500"])
                            symbolCategoryRow(title: "Crypto", symbols: ["BTCUSD", "ETHUSD", "SOLUSD"])
                            
                            let historySymbols = customTradeHistorySymbols
                            if !historySymbols.isEmpty {
                                symbolCategoryRow(title: "From Your Trades", symbols: historySymbols)
                            }
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Divider()
                        .background(AppColors.border.opacity(0.4))
                    
                    // Timeframes Row with Check Now Button
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Timeframes")
                                .font(AppTypography.captionBold)
                                .foregroundColor(AppColors.secondaryText)
                            
                            HStack(spacing: 6) {
                                ForEach(["15m", "1h", "4h"], id: \.self) { tf in
                                    AppFilterChip(
                                        tf.uppercased(),
                                        isSelected: alertEngine.isTimeframeMonitored(tf),
                                        height: 28,
                                        activeColor: AppColors.brand
                                    ) {
                                        alertEngine.toggleTimeframe(tf)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        AppButton("Check Now", icon: "bell.badge", style: .secondary, size: .compact, isLoading: isCheckingAlerts) {
                            checkAlertsNow()
                        }
                    }
                    
                    if !alertCheckStatus.isEmpty {
                        HStack {
                            Text(alertCheckStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.brand)
                            Spacer()
                        }
                    }
                    
                    if let lastEval = alertEngine.lastEvaluatedAt {
                        HStack {
                            Text("Last evaluated: \(Formatters.formatTime(lastEval))")
                                .font(AppTypography.captionMicro)
                                .foregroundColor(AppColors.secondaryText)
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
    
    private func symbolCategoryRow(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.captionMicro)
                .foregroundColor(AppColors.secondaryText)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(symbols, id: \.self) { sym in
                        AppFilterChip(
                            sym,
                            isSelected: alertEngine.isSymbolMonitored(sym),
                            height: 28,
                            activeColor: AppColors.brand
                        ) {
                            alertEngine.toggleSymbol(sym)
                        }
                    }
                }
            }
        }
    }
    
    private func checkAlertsNow() {
        isCheckingAlerts = true
        alertCheckStatus = "Evaluating Key Level reactions..."
        Task {
            let fired = await alertEngine.evaluateAllMonitoredSymbols()
            await MainActor.run {
                self.isCheckingAlerts = false
                if fired.isEmpty {
                    self.alertCheckStatus = "Checked: No Key Level touches on last closed bars."
                } else {
                    self.alertCheckStatus = "Detected \(fired.count) Key Level alerts! Notifications dispatched."
                }
            }
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
