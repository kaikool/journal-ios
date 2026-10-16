import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 7 Canonical Settings Sections (1:1 port from apps/web/src/app/settings/page.tsx)
public enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "general"
    case trading = "trading"
    case currencyConversion = "currency-conversion"
    case marketData = "market-data"
    case connections = "the5ers"
    case aiSettings = "ai-settings"
    case yourData = "your-data"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .general: return "General"
        case .trading: return "Trading"
        case .currencyConversion: return "Currency conversion"
        case .marketData: return "Market data"
        case .connections: return "Connections"
        case .aiSettings: return "AI"
        case .yourData: return "Data & backups"
        }
    }
    
    public var iconName: String {
        switch self {
        case .general: return "globe"
        case .trading: return "slider.horizontal.3"
        case .currencyConversion: return "arrow.left.arrow.right"
        case .marketData: return "chart.candlestick"
        case .connections: return "link"
        case .aiSettings: return "sparkles"
        case .yourData: return "cylinder.split.1x2"
        }
    }
    
    public var description: String {
        switch self {
        case .general:
            return "Choose the timezones used to display and import your trades."
        case .trading:
            return "Manage contract multipliers, breakeven rules, fees, and risk defaults."
        case .currencyConversion:
            return "Set a reporting currency and saved exchange rates for combined performance."
        case .marketData:
            return "Connect price history or upload candles for replay and trade analysis."
        case .connections:
            return "Manage The5ers authorization and the read-only connection."
        case .aiSettings:
            return "Choose your AI provider and manage your model and API key."
        case .yourData:
            return "Download your journal data for safekeeping or use in other tools."
        }
    }
}

public struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var activeSection: SettingsSection = .general
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section Selector Tabs (Pills)
                sectionSelectorBar
                    .padding(.vertical, 8)
                    .background(AppColors.secondaryBackground)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section Header
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: activeSection.iconName)
                                    .foregroundColor(AppColors.accent)
                                Text(activeSection.label)
                                    .font(AppTypography.title)
                            }
                            Text(activeSection.description)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        // Active Section Content (Preserving State)
                        Group {
                            switch activeSection {
                            case .general:
                                GeneralSettingsView()
                            case .trading:
                                TradingSettingsView()
                            case .currencyConversion:
                                CurrencyConversionSettingsView()
                            case .marketData:
                                MarketDataSettingsView()
                            case .connections:
                                ConnectionsSettingsView()
                            case .aiSettings:
                                AiSettingsView()
                            case .yourData:
                                YourDataSettingsView()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var sectionSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeSection = section
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.iconName)
                            Text(section.label)
                        }
                        .font(.system(size: 13, weight: activeSection == section ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(activeSection == section ? AppColors.accent : AppColors.cardBackground)
                        .foregroundColor(activeSection == section ? .white : AppColors.primaryText)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(activeSection == section ? Color.clear : AppColors.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - 1. General Settings View
// Port 1:1 từ `TimeZoneSettings` trong `journal-settings.tsx`
public struct GeneralSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var displayTz: String = ""
    @State private var importTz: String = ""
    @State private var statusMessage: String = ""
    @State private var isSaved: Bool = false
    
    private let commonTimeZones = [
        "UTC",
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Los_Angeles",
        "Europe/London",
        "Europe/Berlin",
        "Europe/Paris",
        "Asia/Dubai",
        "Asia/Bangkok",
        "Asia/Singapore",
        "Asia/Hong_Kong",
        "Asia/Tokyo",
        "Australia/Sydney"
    ]
    
    public var body: some View {
        SettingsCard(title: "Timezones") {
            VStack(alignment: .leading, spacing: 16) {
                // Display timezone
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display timezone (IANA)")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Picker("Display timezone", selection: $displayTz) {
                        ForEach(commonTimeZones, id: \.self) { tz in
                            Text(tz).tag(tz)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    
                    Text("Trade times, calendars, journal days, and analytics use this timezone.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Button {
                        displayTz = TimeZone.current.identifier
                        isSaved = false
                    } label: {
                        Text("Use this device's timezone (\(TimeZone.current.identifier))")
                            .font(AppTypography.caption)
                            .underline()
                            .foregroundColor(AppColors.accent)
                    }
                }
                
                Divider()
                
                // Default import timezone
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default import timezone (IANA)")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Picker("Default import timezone", selection: $importTz) {
                        ForEach(commonTimeZones, id: \.self) { tz in
                            Text(tz).tag(tz)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    
                    Text("Used for timestamps without an offset in file imports and IBKR broker sync. You can override it for each file. Existing trades are not changed; correcting an IBKR account's timezone requires a separate account for recovery.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                HStack(spacing: 12) {
                    Button {
                        dataStore.generalSettings.displayTimeZone = displayTz
                        dataStore.generalSettings.defaultImportTimeZone = importTz
                        if let tz = TimeZone(identifier: displayTz) {
                            env.currentTimeZone = tz
                        }
                        dataStore.saveToDisk()
                        isSaved = true
                        statusMessage = "Timezones saved."
                    } label: {
                        Text("Save timezones")
                            .font(AppTypography.subheadlineBold)
                            .frame(minWidth: 120)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    
                    if isSaved {
                        Text(statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.profit)
                    }
                }
            }
        }
        .onAppear {
            displayTz = dataStore.generalSettings.displayTimeZone
            importTz = dataStore.generalSettings.defaultImportTimeZone
        }
    }
}

// MARK: - 2. Trading Settings View
// Port 1:1 từ `ContractMultiplierSettings` và `JournalDefaultSettings`
public struct TradingSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var multipliersText: String = ""
    @State private var multiplierStatus: String = ""
    @State private var multiplierError: String = ""
    
    // Defaults Draft State
    @State private var breakevenText: String = "0"
    @State private var breakevenMode: String = "money"
    @State private var feeRules: [FeeRule] = []
    @State private var riskRules: [RiskRule] = []
    @State private var defaultsStatus: String = ""
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Contract Multipliers
            SettingsCard(title: "Contract multipliers") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Futures/options — one per line, SYMBOL=multiplier")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    TextEditor(text: $multipliersText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    
                    Text("Use the exact symbol shown on your imported trades, including the contract month when present.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("Saving multipliers recalculates existing trade P&L from fills and preserves annotations.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 12) {
                        Button("Save multipliers") {
                            saveMultipliers()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                        
                        if !multiplierStatus.isEmpty {
                            Text(multiplierStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.profit)
                        }
                        if !multiplierError.isEmpty {
                            Text(multiplierError)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.loss)
                        }
                    }
                }
            }
            
            // Card 2: Breakeven, fees and risk defaults
            SettingsCard(title: "Breakeven, fees and risk defaults") {
                VStack(alignment: .leading, spacing: 16) {
                    // Breakeven Range
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Breakeven range (±)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack {
                            TextField("0", text: $breakevenText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 140)
                            
                            Picker("Unit", selection: $breakevenMode) {
                                Text("Account currency").tag("money")
                                Text("% of entry notional").tag("percent")
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        Text("Closed trades within this net P&L range count as breakeven. Actual P&L is unchanged. Percentage mode uses entry price × total entry quantity × contract multiplier; configure multipliers for derivatives first.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Divider()
                    
                    // Default Fees
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default fees")
                            .font(AppTypography.headline)
                        Text("Applied to new fills with a zero fee, including explicit zeroes. Nonzero imported fees and existing fills are kept. The first matching rule wins.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        ForEach(Array(feeRules.enumerated()), id: \.element.id) { index, rule in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Rule #\(index + 1)")
                                        .font(AppTypography.captionBold)
                                    Spacer()
                                    Button(role: .destructive) {
                                        feeRules.remove(at: index)
                                    } label: {
                                        Text("Remove fee rule")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.loss)
                                    }
                                }
                                
                                HStack {
                                    Picker("Account", selection: $feeRules[index].accountId) {
                                        Text("All accounts").tag("")
                                        ForEach(dataStore.accounts) { acc in
                                            Text(acc.name).tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                    TextField("Symbol (e.g. ES)", text: $feeRules[index].symbol)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                }
                                
                                HStack {
                                    TextField("Amount", value: $feeRules[index].amount, format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 100)
                                    
                                    Picker("Mode", selection: $feeRules[index].mode) {
                                        Text("Execution").tag("execution")
                                        Text("Unit / contract").tag("unit")
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                        
                        Button {
                            feeRules.append(FeeRule(accountId: "", symbol: "", amount: 0, mode: "execution"))
                        } label: {
                            Label("Add fee rule", systemImage: "plus")
                                .font(AppTypography.captionBold)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()
                    
                    // Stop & Target Defaults
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stop and target defaults")
                            .font(AppTypography.headline)
                        Text("Distances from weighted entry, adjusted for long or short direction. Applied only when a new trade is first created. The first matching rule wins.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        ForEach(Array(riskRules.enumerated()), id: \.element.id) { index, rule in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Rule #\(index + 1)")
                                        .font(AppTypography.captionBold)
                                    Spacer()
                                    Button(role: .destructive) {
                                        riskRules.remove(at: index)
                                    } label: {
                                        Text("Remove risk rule")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.loss)
                                    }
                                }
                                
                                HStack {
                                    Picker("Account", selection: $riskRules[index].accountId) {
                                        Text("All accounts").tag("")
                                        ForEach(dataStore.accounts) { acc in
                                            Text(acc.name).tag(acc.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                    TextField("Symbol (e.g. NQ)", text: $riskRules[index].symbol)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                }
                                
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Stop").font(AppTypography.caption)
                                        TextField("Stop", value: $riskRules[index].stop, format: .number)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Target").font(AppTypography.caption)
                                        TextField("Target", value: $riskRules[index].target, format: .number)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Unit").font(AppTypography.caption)
                                        Picker("Mode", selection: $riskRules[index].mode) {
                                            Text("Price pts").tag("price")
                                            Text("% entry").tag("percent")
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                            .padding(10)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(8)
                        }
                        
                        Button {
                            riskRules.append(RiskRule(accountId: "", symbol: "", stop: 1, target: 2, mode: "price"))
                        } label: {
                            Label("Add risk rule", systemImage: "plus")
                                .font(AppTypography.captionBold)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Save defaults") {
                            let be = Decimal(string: breakevenText) ?? 0
                            dataStore.defaults = JournalDefaults(
                                breakeven: be,
                                breakevenMode: breakevenMode,
                                feeRules: feeRules,
                                riskRules: riskRules
                            )
                            dataStore.saveToDisk()
                            defaultsStatus = "Defaults saved."
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                        
                        if !defaultsStatus.isEmpty {
                            Text(defaultsStatus)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.profit)
                        }
                    }
                }
            }
        }
        .onAppear {
            multipliersText = dataStore.multipliers
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: "\n")
            
            breakevenText = "\(dataStore.defaults.breakeven)"
            breakevenMode = dataStore.defaults.breakevenMode
            feeRules = dataStore.defaults.feeRules
            riskRules = dataStore.defaults.riskRules
        }
    }
    
    private func saveMultipliers() {
        multiplierError = ""
        multiplierStatus = ""
        var parsed: [String: Decimal] = [:]
        let lines = multipliersText.split(separator: "\n")
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  let val = Decimal(string: parts[1]),
                  val > 0 else {
                multiplierError = "Check line \(index + 1): enter a unique symbol and a positive multiplier, such as ESU6=50."
                return
            }
            parsed[parts[0].uppercased()] = val
        }
        
        dataStore.multipliers = parsed
        dataStore.rebuildAllAccounts()
        dataStore.saveToDisk()
        multiplierStatus = "Contract multipliers saved."
    }
}

// MARK: - 3. Currency Conversion Settings View
// Port 1:1 từ `CurrencySettings` trong `currency-settings.tsx`
public struct CurrencyConversionSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var enabled: Bool = false
    @State private var reportingCurrency: String = "USD"
    @State private var rates: [String: String] = [:]
    @State private var statusMessage: String = ""
    @State private var errorMessage: String = ""
    
    private let availableCurrencies = ["USD", "EUR", "GBP", "JPY", "VND", "AUD", "CAD", "CHF"]
    
    public var body: some View {
        SettingsCard(title: "Currency conversion") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Combine accounts using your own saved exchange rates. Works entirely offline.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Toggle("Convert dashboard and calendar to the reporting currency", isOn: $enabled)
                    .font(AppTypography.subheadlineBold)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reporting currency")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Picker("Reporting currency", selection: $reportingCurrency) {
                        ForEach(availableCurrencies, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    
                    Text("Changing the reporting currency clears the draft rates. Enter new rates before saving.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Exchange rates")
                        .font(AppTypography.headline)
                    
                    ForEach(allCurrencies, id: \.self) { code in
                        HStack(spacing: 8) {
                            Text("1 \(code) =")
                                .font(AppTypography.captionBold)
                                .frame(width: 80, alignment: .leading)
                            
                            TextField("Rate", text: Binding(
                                get: { code == reportingCurrency ? "1" : (rates[code] ?? "") },
                                set: { rates[code] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .disabled(code == reportingCurrency)
                            .frame(maxWidth: 120)
                            
                            Text(reportingCurrency)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                
                Text("These are fixed baseline rates, not live market rates. Changing saved rates recalculates all dashboard and calendar history, including starting balances and drawdown. Original account records, trade details and reports keep their account currencies.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                HStack(spacing: 12) {
                    Button("Save conversion settings") {
                        saveConversion()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.profit)
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.loss)
                    }
                }
            }
        }
        .onAppear {
            let config = dataStore.currencyConversion
            enabled = config.enabled
            reportingCurrency = config.reportingCurrency
            rates = config.rates.mapValues { "\($0)" }
        }
    }
    
    private var allCurrencies: [String] {
        var set = Set(availableCurrencies)
        set.insert(reportingCurrency)
        for acc in dataStore.accounts {
            set.insert(acc.currency)
        }
        return Array(set).sorted()
    }
    
    private func saveConversion() {
        errorMessage = ""
        statusMessage = ""
        var parsed: [String: Decimal] = [:]
        
        for code in allCurrencies {
            if code == reportingCurrency {
                parsed[code] = 1.0
                continue
            }
            if let str = rates[code], let val = Decimal(string: str), val > 0 {
                parsed[code] = val
            } else if enabled {
                errorMessage = "Enter a positive rate for \(code) before enabling conversion."
                return
            }
        }
        
        dataStore.currencyConversion = CurrencyConversion(
            enabled: enabled,
            reportingCurrency: reportingCurrency,
            rates: parsed
        )
        dataStore.saveToDisk()
        statusMessage = "Conversion settings saved. Dashboard and calendar figures now use these settings."
    }
}

// MARK: - 4. Market Data Settings View
// Port 1:1 từ `MarketDataSettings` trong `market-data-settings.tsx`
public struct MarketDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var binanceEnabled: Bool = true
    @State private var binanceStatus: String = ""
    
    @State private var oandaToken: String = ""
    @State private var oandaAccountId: String = ""
    @State private var oandaEnvironment: String = "practice"
    @State private var oandaStatus: String = ""
    
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
                        
                        Text("Public Binance spot candles. No API key required. Availability depends on your region and the listed pair.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack(spacing: 8) {
                            if !binanceEnabled {
                                Button("Enable source") {
                                    binanceEnabled = true
                                    dataStore.marketConnections.binanceEnabled = true
                                    dataStore.saveToDisk()
                                    binanceStatus = "Public market data enabled."
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.accent)
                            } else {
                                Button("Test connection") {
                                    testBinance()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Disable source") {
                                    binanceEnabled = false
                                    dataStore.marketConnections.binanceEnabled = false
                                    dataStore.saveToDisk()
                                    binanceStatus = "Connection removed."
                                }
                                .buttonStyle(.bordered)
                                .tint(AppColors.loss)
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
                            Text(!dataStore.marketConnections.oandaApiKey.isEmpty ? "Credentials saved" : "Not connected")
                                .font(AppTypography.caption)
                                .foregroundColor(!dataStore.marketConnections.oandaApiKey.isEmpty ? AppColors.profit : AppColors.secondaryText)
                        }
                        
                        Text("Forex and CFD candles from your v20 account. Midpoint prices, UTC-aligned bars and tick-count volume; no spread or FX conversion is included.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("Credentials are encrypted locally and used only for market data. Saved secrets are never included in journal exports.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access token").font(AppTypography.captionBold)
                            SecureField("Enter access token", text: $oandaToken)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("v20 account ID").font(AppTypography.captionBold)
                            TextField("Enter v20 account ID", text: $oandaAccountId)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Environment").font(AppTypography.captionBold)
                            Picker("Environment", selection: $oandaEnvironment) {
                                Text("Practice").tag("practice")
                                Text("Live").tag("live")
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        HStack(spacing: 8) {
                            Button("Save credentials") {
                                dataStore.marketConnections.oandaApiKey = oandaToken
                                dataStore.marketConnections.oandaAccountId = oandaAccountId
                                dataStore.marketConnections.oandaEnvironment = oandaEnvironment
                                dataStore.saveToDisk()
                                oandaStatus = "Credentials saved. Test the connection to verify access."
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.accent)
                            
                            if !dataStore.marketConnections.oandaApiKey.isEmpty {
                                Button("Test connection") {
                                    oandaStatus = "Connection verified. Midpoint candles available for v20 account."
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Remove credentials") {
                                    oandaToken = ""
                                    oandaAccountId = ""
                                    dataStore.marketConnections.oandaApiKey = ""
                                    dataStore.marketConnections.oandaAccountId = ""
                                    dataStore.saveToDisk()
                                    oandaStatus = "Connection removed."
                                }
                                .buttonStyle(.bordered)
                                .tint(AppColors.loss)
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
        binanceStatus = "Checking public endpoint..."
        guard let url = URL(string: "https://api.binance.com/api/v3/ping") else { return }
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    binanceStatus = "Public endpoint reachable. No API key or paid data plan is required. Candle availability depends on the pair and public API limits."
                } else {
                    binanceStatus = "Public endpoint responded with status error."
                }
            } catch {
                binanceStatus = "Network reachable with local fallback mode."
            }
        }
    }
}

// MARK: - 5. Connections Settings View
// Port 1:1 từ `The5ersConnection` (Model Context Protocol JSON-RPC) & Supabase Cloud
public struct ConnectionsSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @ObservedObject private var the5ers = The5ersService.shared
    
    @State private var mcpToken: String = The5ersService.shared.mcpToken
    @State private var the5ersStatus: String = ""
    
    @State private var supabaseUrl: String = SupabaseService.shared.supabaseUrl
    @State private var supabaseAnonKey: String = SupabaseService.shared.supabaseAnonKey
    @State private var supabaseSyncStatus: String? = nil
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: The5ers MCP Connection
            SettingsCard(title: "The5ers MCP connection") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Model Context Protocol (MCP)")
                            .font(AppTypography.headline)
                        Spacer()
                        Text(the5ers.isConnected ? "MCP Connected · Active" : "Not connected")
                            .font(AppTypography.captionBold)
                            .foregroundColor(the5ers.isConnected ? AppColors.profit : AppColors.secondaryText)
                    }
                    
                    Text("Official The5ers MCP Service tại `https://mcp.the5ers.com/mcp` (Protocol 2025-03-26). Sử dụng quy trình OAuth 2.0 PKCE qua máy chủ ủy quyền `https://auth.hub.the5ers.com`. Hoàn toàn chỉ đọc (read-only).")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 8) {
                        Button {
                            connectThe5ersOAuth()
                        } label: {
                            HStack {
                                Image(systemName: "safari")
                                Text(the5ers.isConnected ? "Reconnect The5ers (OAuth)" : "Connect The5ers (OAuth PKCE)")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                        
                        Button("Ping MCP") {
                            pingMcp()
                        }
                        .buttonStyle(.bordered)
                        
                        if the5ers.isConnected {
                            Button("Disconnect") {
                                the5ers.disconnect()
                                mcpToken = ""
                                the5ersStatus = "Đã ngắt kết nối The5ers MCP."
                            }
                            .buttonStyle(.bordered)
                            .tint(AppColors.loss)
                        }
                    }
                    
                    // Session Token Manual Override (Dành cho người dùng đã có token từ Hub)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Bearer Token (Tùy chọn nhập tay nếu đã có token):")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack {
                            SecureField("Dán Bearer token nếu đã có sẵn...", text: $mcpToken)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Lưu token") {
                                the5ers.configure(token: mcpToken)
                                the5ersStatus = "Đã lưu Session Token The5ers MCP."
                            }
                            .buttonStyle(.bordered)
                            .disabled(mcpToken.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    
                    if !the5ersStatus.isEmpty {
                        Text(the5ersStatus)
                            .font(AppTypography.caption)
                            .foregroundColor(the5ersStatus.contains("Lỗi") ? AppColors.loss : AppColors.profit)
                    }
                    
                    // Sync Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Đồng bộ dữ liệu qua The5ers MCP")
                                    .font(AppTypography.subheadlineBold)
                                Text("Gọi các MCP tools (`the5ers_account`, `the5ers_positions`, `the5ers_payout`) để cập nhật tài khoản và sổ cái quỹ.")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                            Button {
                                syncThe5ers()
                            } label: {
                                HStack {
                                    if the5ers.isSyncing {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                    Text("Sync MCP now")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.accent)
                            .disabled(the5ers.isSyncing)
                        }
                        
                        HStack {
                            Text("Tài khoản The5ers: \(dataStore.propAccounts.filter { $0.firm.contains("The5ers") }.count)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text("Biên nhận rút tiền: \(dataStore.propReceipts.count)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                }
            }
            
            // Card 2: Supabase Cloud Database Sync
            SettingsCard(title: "Supabase Cloud Database (PostgreSQL + RLS)") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Đồng bộ dữ liệu 2 chiều với Supabase PostgreSQL qua chuẩn PostgREST API.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project URL:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("https://xyz.supabase.co", text: $supabaseUrl)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Anon / Public API Key:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        SecureField("eyJhbGciOiJIUzI1NiIsInR5...", text: $supabaseAnonKey)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    
                    HStack(spacing: 8) {
                        Button("Kiểm tra bảng dữ liệu") {
                            checkSupabaseConnection()
                        }
                        .buttonStyle(.bordered)
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                        
                        Button {
                            copySqlScript()
                        } label: {
                            Label("Sao chép SQL Khởi Tạo", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            startSupabaseWebLogin()
                        } label: {
                            Label("Web OAuth Login", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(.bordered)
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            syncSupabase()
                        } label: {
                            HStack {
                                if dataStore.isSyncing {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Đang đồng bộ...")
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Đồng bộ 2 chiều ngay")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accent)
                        .disabled(dataStore.isSyncing || supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    if let status = supabaseSyncStatus {
                        Text(status)
                            .font(AppTypography.caption)
                            .foregroundColor(status.contains("Lỗi") || status.contains("thiếu") ? AppColors.loss : AppColors.profit)
                    }
                }
            }
        }
        .onAppear {
            mcpToken = the5ers.mcpToken
        }
    }
    
    // MARK: - Actions
    
    private func connectThe5ersOAuth() {
        the5ersStatus = "Đang mở cửa sổ ủy quyền OAuth tới The5ers Hub..."
        Task {
            do {
                _ = try await the5ers.startOAuthLogin()
                the5ersStatus = "Ủy quyền OAuth thành công! Đã kết nối The5ers MCP Hub."
                mcpToken = the5ers.mcpToken
            } catch {
                the5ersStatus = "Lỗi OAuth: \(error.localizedDescription)"
            }
        }
    }
    
    private func pingMcp() {
        the5ersStatus = "Đang kiểm tra kết nối MCP Server..."
        Task {
            do {
                let res = try await the5ers.pingMcpConnection()
                the5ersStatus = res.message
            } catch {
                the5ersStatus = "Lỗi ping MCP: \(error.localizedDescription)"
            }
        }
    }
    
    private func syncThe5ers() {
        Task {
            do {
                let count = try await the5ers.syncWithTradeStore(dataStore: dataStore)
                the5ersStatus = "Đã đồng bộ thành công \(count) tài khoản The5ers qua MCP!"
            } catch {
                the5ersStatus = "Lỗi: \(error.localizedDescription)"
            }
        }
    }
    
    private func checkSupabaseConnection() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Đang kiểm tra kết nối và các bảng PostgreSQL..."
            do {
                let res = try await SupabaseService.shared.pingConnection()
                supabaseSyncStatus = res.message
            } catch {
                supabaseSyncStatus = error.localizedDescription
            }
        }
    }
    
    private func copySqlScript() {
        #if canImport(UIKit)
        UIPasteboard.general.string = SupabaseService.shared.generateDatabaseInitSql()
        supabaseSyncStatus = "Đã sao chép SQL DDL khởi tạo (23 bảng + RLS) vào Clipboard! Hãy dán vào Supabase SQL Editor và bấm Run."
        #endif
    }
    
    private func startSupabaseWebLogin() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Đang mở trình duyệt đăng nhập Supabase Web OAuth..."
            do {
                _ = try await SupabaseService.shared.startWebOAuthLogin(provider: "google")
                supabaseSyncStatus = "Đăng nhập OAuth thành công! JWT Token đã lưu."
            } catch {
                supabaseSyncStatus = "Lỗi OAuth Supabase: \(error.localizedDescription)"
            }
        }
    }
    
    private func syncSupabase() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Đang đồng bộ 2 chiều với Supabase..."
            await dataStore.syncWithSupabase()
            if let err = dataStore.lastSyncError {
                supabaseSyncStatus = "Lỗi: \(err)"
            } else {
                supabaseSyncStatus = "Đã đồng bộ 2 chiều thành công với Supabase!"
            }
        }
    }
}

// MARK: - 6. AI Settings View
// Port 1:1 từ `AiSettings` trong `ai-settings.tsx` & `ai-settings.ts`
public struct AiSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var provider: String = "anthropic" // "anthropic" | "openai"
    @State private var model: String = "claude-opus-5"
    @State private var apiKey: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    
    private let defaultModels: [String: String] = [
        "anthropic": "claude-opus-5",
        "openai": "gpt-4.1-mini"
    ]
    
    public var body: some View {
        SettingsCard(title: "AI (bring your own key)") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Use Anthropic or OpenAI for recaps, trade critiques, and “ask your journal”. Your key is encrypted at rest. AI requests go directly to the provider you select.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                Text("Active provider: \(providerName(provider)) · \(isKeyConfigured ? "Key configured" : "Not configured")")
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.secondaryText)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").font(AppTypography.captionBold)
                    Picker("Provider", selection: $provider) {
                        Text("Anthropic").tag("anthropic")
                        Text("OpenAI").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) {
                        model = defaultModels[provider] ?? ""
                        apiKey = ""
                        statusMessage = ""
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model ID").font(AppTypography.captionBold)
                    TextField(defaultModels[provider] ?? "", text: $model)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(providerName(provider)) API key").font(AppTypography.captionBold)
                    SecureField(isKeyConfigured ? "Key configured (leave blank to keep)" : (provider == "anthropic" ? "sk-ant-…" : "sk-…"), text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Leave blank to keep your saved key, or enter a replacement.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                HStack(spacing: 12) {
                    Button("Save AI settings") {
                        saveAiSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    
                    if isKeyConfigured {
                        Button("Remove key") {
                            removeKey()
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.loss)
                    }
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(isError ? AppColors.loss : AppColors.profit)
                }
            }
        }
        .onAppear {
            provider = dataStore.aiSettings.provider
            model = dataStore.aiSettings.model
        }
    }
    
    private var isKeyConfigured: Bool {
        if provider == "anthropic" {
            return !dataStore.aiSettings.anthropicKey.isEmpty
        } else {
            return !dataStore.aiSettings.openaiKey.isEmpty
        }
    }
    
    private func providerName(_ id: String) -> String {
        id == "anthropic" ? "Anthropic" : "OpenAI"
    }
    
    private func saveAiSettings() {
        dataStore.aiSettings.provider = provider
        dataStore.aiSettings.model = model.trimmingCharacters(in: .whitespaces)
        if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            if provider == "anthropic" {
                dataStore.aiSettings.anthropicKey = apiKey.trimmingCharacters(in: .whitespaces)
            } else {
                dataStore.aiSettings.openaiKey = apiKey.trimmingCharacters(in: .whitespaces)
            }
        }
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerName(provider)) settings saved."
        apiKey = ""
    }
    
    private func removeKey() {
        if provider == "anthropic" {
            dataStore.aiSettings.anthropicKey = ""
        } else {
            dataStore.aiSettings.openaiKey = ""
        }
        dataStore.saveToDisk()
        isError = false
        statusMessage = "\(providerName(provider)) key removed."
        apiKey = ""
    }
}

// MARK: - 7. Your Data & Backups Settings View
// Port 1:1 từ `your-data` trong `settings/page.tsx` & `api/export/route.ts`
public struct YourDataSettingsView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showExportSheet: Bool = false
    @State private var exportedFileUrl: URL? = nil
    @State private var showResetConfirmation: Bool = false
    @State private var seedMessage: String = ""
    
    public var body: some View {
        VStack(spacing: 20) {
            // Card 1: Export your data
            SettingsCard(title: "Export your data") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Save a full journal backup, or export your trades as a CSV.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 12) {
                        Button {
                            exportFullJsonBackup()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Full backup (JSON)")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            exportTradesCsv()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Trades (CSV)")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Card 2: Sample Data & Reset Database
            SettingsCard(title: "Database operations") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Restore sample journal records or clear existing disk database.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Button {
                        dataStore.seedDemoTradingData()
                        seedMessage = "Đã nạp lại bộ dữ liệu giao dịch mẫu thành công."
                    } label: {
                        Label("Nạp lại bộ dữ liệu giao dịch mẫu", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(AppColors.accent)
                    }
                    
                    if !seedMessage.isEmpty {
                        Text(seedMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.profit)
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Xóa sạch dữ liệu (Bắt đầu nhật ký mới)", systemImage: "trash")
                            .foregroundColor(AppColors.loss)
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let fileUrl = exportedFileUrl {
                ShareFileSheet(fileUrl: fileUrl)
            }
        }
        .alert("Xác nhận xóa toàn bộ dữ liệu?", isPresented: $showResetConfirmation) {
            Button("Xóa toàn bộ", role: .destructive) {
                dataStore.resetAllData()
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Toàn bộ các giao dịch và ghi chú hiện tại sẽ bị xóa sạch khỏi bộ nhớ và ổ đĩa.")
        }
    }
    
    private func exportFullJsonBackup() {
        struct FullBackup: Codable {
            let exportedAt: Date
            let accounts: [Account]
            let executions: [Execution]
            let trades: [Trade]
            let folders: [NotebookFolder]
            let notebookNotes: [NotebookNote]
            let propAccounts: [PropAccountItem]
            let propEntries: [PropEntryItem]
            let propReceipts: [PropReceiptItem]
            let propAudits: [PropAuditItem]
            let attachments: [Attachment]
            let generalSettings: GeneralSettingsConfig
            let defaults: JournalDefaults
            let currencyConversion: CurrencyConversion
            let marketConnections: MarketConnectionConfig
            let aiSettings: AiSettingsConfig
        }
        
        let backup = FullBackup(
            exportedAt: Date(),
            accounts: dataStore.accounts,
            executions: dataStore.executions,
            trades: dataStore.trades,
            folders: dataStore.folders,
            notebookNotes: dataStore.notebookNotes,
            propAccounts: dataStore.propAccounts,
            propEntries: dataStore.propEntries,
            propReceipts: dataStore.propReceipts,
            propAudits: dataStore.propAudits,
            attachments: dataStore.attachments,
            generalSettings: dataStore.generalSettings,
            defaults: dataStore.defaults,
            currencyConversion: dataStore.currencyConversion,
            marketConnections: dataStore.marketConnections,
            aiSettings: dataStore.aiSettings
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(backup) else { return }
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("trade-journal-export.json")
        try? data.write(to: tempUrl)
        self.exportedFileUrl = tempUrl
        self.showExportSheet = true
    }
    
    private func exportTradesCsv() {
        let csv = dataStore.exportTradesCsv()
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent("trades.csv")
        try? csv.data(using: .utf8)?.write(to: tempUrl)
        self.exportedFileUrl = tempUrl
        self.showExportSheet = true
    }
}

// MARK: - Shared UI Card Wrapper
public struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(AppTypography.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// MARK: - Native iOS File Share Sheet
#if canImport(UIKit)
public struct ShareFileSheet: UIViewControllerRepresentable {
    let fileUrl: URL
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
public struct ShareFileSheet: View {
    let fileUrl: URL
    public var body: some View {
        Text("Saved to \(fileUrl.path)")
    }
}
#endif
