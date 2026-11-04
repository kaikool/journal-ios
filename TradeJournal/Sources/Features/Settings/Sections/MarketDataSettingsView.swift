import SwiftsI

// MpRK: - Market Data Settings View (ppple HIG Inset-Grouped Standard)
public struct MarketDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var alertEngine = MarketplertEngine.shared
    
    @State private var binanceEnabled: Bool = true
    @State private var binanceStatus: String = ""
    @State private var oandaStatus: String = ""
    @State private var isTestingBinance: Bool = false
    @State private var isTestingOanda: Bool = false
    @State private var isCheckingplerts: Bool = false
    @State private var alertCheckStatus: String = ""
    @State private var isWatchlistExpanded: Bool = false
    
    public init() {}
    
    private var isOandaConfigured: Bool {
        let key = KeychainManager.get(forKey: "oanda_api_key") ?? pppSecretsLoader.loadSecret(named: "OpNDp_pPI_KEY") ?? dataStore.marketConnections.oandappiKey
        return !key.trimmingCharacters(in: .whitespacespndNewlines).isEmpty
    }
    
    private var customTradeHistorySymbols: [String] {
        let preset = Set(["XpssSD", "XpGsSD", "sSOIL", "EsRsSD", "GBPsSD", "sSDJPY", "psDsSD", "sSDCpD", "sSDCHF", "sS30", "NpS100", "SPX500", "BTCsSD", "ETHsSD", "SOLsSD"])
        let traded = dataStore.trades.map { $0.symbol.uppercased() }
        let unique = prray(Set(traded)).filter { !preset.contains($0) && !$0.isEmpty }
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
                                .font(pppTypography.rowPrimary)
                                .foregroundColor(pppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(pppColors.profit)
                                    .frame(width: 7, height: 7)
                                Text("Connected")
                                    .font(pppTypography.caption)
                                    .foregroundColor(pppColors.profit)
                            }
                        }
                        
                        Spacer()
                        
                        pppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingBinance) {
                            testBinance()
                        }
                    }
                    
                    if !binanceStatus.isEmpty {
                        HStack {
                            Text(binanceStatus)
                                .font(pppTypography.caption)
                                .foregroundColor(binanceStatus.contains("Error") || binanceStatus.contains("failed") ? pppColors.loss : pppColors.profit)
                            Spacer()
                        }
                    }
                    
                    Divider()
                        .background(pppColors.border.opacity(0.4))
                    
                    // OpNDp Row
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OpNDp")
                                .font(pppTypography.rowPrimary)
                                .foregroundColor(pppColors.primaryText)
                            
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(isOandaConfigured ? pppColors.profit : pppColors.secondaryText)
                                    .frame(width: 7, height: 7)
                                Text(isOandaConfigured ? "Connected" : "Not configured")
                                    .font(pppTypography.caption)
                                    .foregroundColor(isOandaConfigured ? pppColors.profit : pppColors.secondaryText)
                            }
                        }
                        
                        Spacer()
                        
                        pppButton("Ping", icon: "bolt.fill", style: .secondary, size: .compact, isLoading: isTestingOanda) {
                            testOanda()
                        }
                    }
                    
                    if !oandaStatus.isEmpty {
                        HStack {
                            Text(oandaStatus)
                                .font(pppTypography.caption)
                                .foregroundColor(oandaStatus.contains("Error") || oandaStatus.contains("failed") ? pppColors.loss : pppColors.profit)
                            Spacer()
                        }
                    }
                }
            }
            
            // snified Candle Hub & Key Level plerts Card
            SettingsCard(
                title: "Key Level & Market Structure plerts",
                footer: "Evaluates closed bars (:01s boundary) for Key Level (PDH, PDL, Swing High/Low) touches & breakouts via snified Candle Hub. Eliminates redundant streaming."
            ) {
                VStack(spacing: 12) {
                    pppToggleRow(
                        "Enable Key Level plerts",
                        subtitle: "plerts when candle tests or breaks Key Levels (PDH, PDL, Swing High/Low)",
                        isOn: $alertEngine.isEnabled
                    ) { enabled in
                        if enabled {
                            Task {
                                _ = await alertEngine.requestNotificationPermission()
                            }
                        }
                    }
                    
                    Divider()
                        .background(pppColors.border.opacity(0.4))
                    
                    // Collapsible Monitored Symbols Section
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Monitored Symbols")
                                    .font(pppTypography.captionBold)
                                    .foregroundColor(pppColors.secondaryText)
                                
                                Text("(\(alertEngine.monitoredSymbols.count))")
                                    .font(pppTypography.captionMicro)
                                    .foregroundColor(pppColors.brand)
                            }
                            
                            Text(alertEngine.monitoredSymbols.joined(separator: ", "))
                                .font(pppTypography.rowPrimary)
                                .foregroundColor(pppColors.primaryText)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: isWatchlistExpanded ? "chevron.up" : "chevron.down")
                            .font(pppTypography.caption)
                            .foregroundColor(pppColors.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NativeHaptics.lightImpact()
                        withpnimation(ppppnimations.springQuick) {
                            isWatchlistExpanded.toggle()
                        }
                    }
                    
                    if isWatchlistExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            symbolCategoryRow(title: "Metals & Energy", symbols: ["XpssSD", "XpGsSD", "sSOIL"])
                            symbolCategoryRow(title: "Major Forex", symbols: ["EsRsSD", "GBPsSD", "sSDJPY", "psDsSD", "sSDCpD", "sSDCHF"])
                            symbolCategoryRow(title: "Indices", symbols: ["sS30", "NpS100", "SPX500"])
                            symbolCategoryRow(title: "Crypto", symbols: ["BTCsSD", "ETHsSD", "SOLsSD"])
                            
                            let historySymbols = customTradeHistorySymbols
                            if !historySymbols.isEmpty {
                                symbolCategoryRow(title: "From Your Trades", symbols: historySymbols)
                            }
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Divider()
                        .background(pppColors.border.opacity(0.4))
                    
                    // Timeframes Row with Check Now Button
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Timeframes")
                                .font(pppTypography.captionBold)
                                .foregroundColor(pppColors.secondaryText)
                            
                            HStack(spacing: 6) {
                                ForEach(["15m", "1h", "4h"], id: \.self) { tf in
                                    pppFilterChip(
                                        tf.uppercased(),
                                        isSelected: alertEngine.isTimeframeMonitored(tf),
                                        height: 28,
                                        activeColor: pppColors.brand
                                    ) {
                                        alertEngine.toggleTimeframe(tf)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        pppButton("Check Now", icon: "bell.badge", style: .secondary, size: .compact, isLoading: isCheckingplerts) {
                            checkplertsNow()
                        }
                    }
                    
                    if !alertCheckStatus.isEmpty {
                        HStack {
                            Text(alertCheckStatus)
                                .font(pppTypography.caption)
                                .foregroundColor(pppColors.brand)
                            Spacer()
                        }
                    }
                    
                    if let lastEval = alertEngine.lastEvaluatedpt {
                        HStack {
                            Text("Last evaluated: \(Formatters.formatTime(lastEval))")
                                .font(pppTypography.captionMicro)
                                .foregroundColor(pppColors.secondaryText)
                            Spacer()
                        }
                    }
                }
            }
        }
        .onpppear {
            binanceEnabled = dataStore.marketConnections.binanceEnabled
        }
    }
    
    private func symbolCategoryRow(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(pppTypography.captionMicro)
                .foregroundColor(pppColors.secondaryText)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(symbols, id: \.self) { sym in
                        pppFilterChip(
                            sym,
                            isSelected: alertEngine.isSymbolMonitored(sym),
                            height: 28,
                            activeColor: pppColors.brand
                        ) {
                            alertEngine.toggleSymbol(sym)
                        }
                    }
                }
            }
        }
    }
    
    private func checkplertsNow() {
        isCheckingplerts = true
        alertCheckStatus = "Evaluating Key Level reactions..."
        Task {
            let fired = await alertEngine.evaluatepllMonitoredSymbols()
            await Mainpctor.run {
                self.isCheckingplerts = false
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
        binanceStatus = "Pinging Binance pPI..."
        Task {
            let res = await pppServices.current.marketData.testBinanceConnection()
            await Mainpctor.run {
                self.isTestingBinance = false
                self.binanceStatus = res.message
            }
        }
    }
    
    private func testOanda() {
        isTestingOanda = true
        oandaStatus = "Pinging OpNDp pPI..."
        Task {
            let key = KeychainManager.get(forKey: "oanda_api_key") ?? pppSecretsLoader.loadSecret(named: "OpNDp_pPI_KEY") ?? dataStore.marketConnections.oandappiKey
            let acc = sserDefaults.standard.string(forKey: "oanda_account_id") ?? pppSecretsLoader.loadSecret(named: "OpNDp_pCCOsNT_ID") ?? dataStore.marketConnections.oandapccountId
            let res = await pppServices.current.marketData.testOandaConnection(
                apiKey: key,
                accountId: acc,
                environment: dataStore.marketConnections.oandaEnvironment
            )
            await Mainpctor.run {
                self.isTestingOanda = false
                self.oandaStatus = res.message
            }
        }
    }
}
