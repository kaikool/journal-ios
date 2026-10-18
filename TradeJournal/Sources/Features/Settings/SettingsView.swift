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
        case .marketData: return "chart.xyaxis.line"
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
    @Namespace private var settingsSectionNamespace
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                title: "Settings",
                showFilters: false
            )
            
            // Section Selector Tabs (Apple HIG Sliding Bar)
            sectionSelectorBar
                .padding(.vertical, 8)
                .background(AppColors.cardBackground)
            
            Divider().background(AppColors.border.opacity(0.5))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section Header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: activeSection.iconName)
                                .foregroundColor(AppColors.brand)
                                .font(.system(size: 14))
                            Text(activeSection.label)
                                .font(AppTypography.pageTitle)
                                .foregroundColor(AppColors.primaryText)
                        }
                        Text(activeSection.description)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(AppColors.background)
    }
    
    private var sectionSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    let isSelected = activeSection == section
                    Button {
                        if activeSection != section {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                activeSection = section
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.iconName)
                                .font(.system(size: 11))
                            Text(section.label)
                                .font(AppTypography.captionBold)
                        }
                        .foregroundColor(isSelected ? AppColors.brand : AppColors.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppColors.cardBackground)
                                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1.5)
                                    .matchedGeometryEffect(id: "SettingsSectionPill", in: settingsSectionNamespace)
                            }
                        }
                    }
                    .buttonStyle(ApplePressableButtonStyle())
                }
            }
            .padding(4)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - 1. General Settings View
// Ported 1:1 from `TimeZoneSettings` in `journal-settings.tsx`
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
                    
                    AppleMenuChip(title: "Timezone", selectionText: displayTz, icon: "globe") {
                        ForEach(commonTimeZones, id: \.self) { tz in
                            Button(tz) {
                                displayTz = tz
                                isSaved = false
                            }
                        }
                    }
                    
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
                    
                    AppleMenuChip(title: "Import timezone", selectionText: importTz, icon: "clock") {
                        ForEach(commonTimeZones, id: \.self) { tz in
                            Button(tz) {
                                importTz = tz
                                isSaved = false
                            }
                        }
                    }
                    
                    Text("Used for timestamps without an offset in file imports and IBKR broker sync. You can override it for each file. Existing trades are not changed; correcting an IBKR account's timezone requires a separate account for recovery.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                HStack(spacing: 12) {
                    AppButton("Save timezones", icon: "checkmark", style: .primary, size: .compact) {
                        dataStore.generalSettings.displayTimeZone = displayTz
                        dataStore.generalSettings.defaultImportTimeZone = importTz
                        if let tz = TimeZone(identifier: displayTz) {
                            env.currentTimeZone = tz
                        }
                        dataStore.saveToDisk()
                        isSaved = true
                        statusMessage = "Timezones saved."
                    }
                    
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
// Ported 1:1 from `ContractMultiplierSettings` and `JournalDefaultSettings`
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
                        .padding(8)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 0.5)
                        )
                    
                    Text("Use the exact symbol shown on your imported trades, including the contract month when present.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    Text("Saving multipliers recalculates existing trade P&L from fills and preserves annotations.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    HStack(spacing: 12) {
                        AppButton("Save multipliers", icon: "checkmark", style: .primary, size: .compact) {
                            saveMultipliers()
                        }
                        
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Breakeven range (±)")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        TextField("0", text: $breakevenText)
                            .font(AppTypography.inputText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Range unit", selection: $breakevenMode) {
                            Text("Account currency").tag("money")
                            Text("% of entry notional").tag("percent")
                        }
                        .pickerStyle(.segmented)
                        
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
                                        .font(AppTypography.inputText)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                }
                                
                                HStack {
                                    TextField("Amount", value: $feeRules[index].amount, format: .number)
                                        .font(AppTypography.inputText)
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
                        
                        AppButton("Add fee rule", icon: "plus", style: .outline, size: .compact) {
                            feeRules.append(FeeRule(accountId: "", symbol: "", amount: 0, mode: "execution"))
                        }
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
                                        .font(AppTypography.inputText)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                }
                                
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Stop").font(AppTypography.caption)
                                        TextField("Stop", value: $riskRules[index].stop, format: .number)
                                            .font(AppTypography.inputText)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Target").font(AppTypography.caption)
                                        TextField("Target", value: $riskRules[index].target, format: .number)
                                            .font(AppTypography.inputText)
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
                        
                        AppButton("Add risk rule", icon: "plus", style: .outline, size: .compact) {
                            riskRules.append(RiskRule(accountId: "", symbol: "", stop: 1, target: 2, mode: "price"))
                        }
                    }
                    
                    HStack(spacing: 12) {
                        AppButton("Save defaults", icon: "checkmark", style: .primary, size: .compact) {
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
        dataStore.rebuildAllAccounts(forceRebuildTrades: true)
        dataStore.saveToDisk()
        multiplierStatus = "Contract multipliers saved."
    }
}

// MARK: - 3. Currency Conversion Settings View
// Ported 1:1 from `CurrencySettings` in `currency-settings.tsx`
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
                    
                    AppleMenuChip(title: "Reporting currency", selectionText: reportingCurrency, icon: "dollarsign.circle") {
                        ForEach(availableCurrencies, id: \.self) { c in
                            Button(c) {
                                reportingCurrency = c
                            }
                        }
                    }
                    
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
                            .font(AppTypography.inputText)
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
                    AppButton("Save rates", icon: "checkmark", style: .primary, size: .compact) {
                        saveConversion()
                    }
                    
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
// Ported 1:1 from `MarketDataSettings` in `market-data-settings.tsx`
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
                                AppButton("Enable", icon: "checkmark.circle", style: .primary, size: .compact) {
                                    binanceEnabled = true
                                    dataStore.marketConnections.binanceEnabled = true
                                    dataStore.saveToDisk()
                                    binanceStatus = "Public market data enabled."
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

// MARK: - 5. Connections Settings View
// Ported 1:1 from `The5ersConnection` (Model Context Protocol JSON-RPC) & Supabase Cloud
public struct ConnectionsSettingsView: View {
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
    
    @State private var supabaseUrl: String = SupabaseService.shared.supabaseUrl
    @State private var supabaseAnonKey: String = SupabaseService.shared.supabaseAnonKey
    @State private var supabaseSyncStatus: String? = nil
    @State private var showWipeConfirmation: Bool = false
    @State private var isWipingSupabase: Bool = false
    
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
                    
                    Text("Official The5ers MCP Service at `https://mcp.the5ers.com/mcp` (2025-03-26 Protocol). Authenticates via The5ers Hub OAuth 2.0 PKCE to sync prop accounts, positions, and payout history.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    // Main Action: OAuth Login vs Connected Actions
                    if !the5ers.isConnected {
                        HStack(spacing: 8) {
                            AppButton("Log in with The5ers", icon: "person.badge.key.fill", style: .primary, size: .compact, fullWidth: true, isLoading: isConnectingThe5ers) {
                                loginThe5ersOAuth()
                            }
                            
                            if !mcpToken.trimmingCharacters(in: .whitespaces).isEmpty {
                                AppButton("Test Connection", icon: "network", style: .secondary, size: .compact, fullWidth: true) {
                                    pingMcp()
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            AppButton("Sync all data", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, fullWidth: true, isLoading: the5ers.isSyncing || dataStore.isSyncing) {
                                syncThe5ers()
                            }
                            
                            AppButton("Test Connection", icon: "network", style: .secondary, size: .compact, fullWidth: true) {
                                pingMcp()
                            }
                            
                            AppButton("Disconnect", icon: "xmark.circle", style: .destructive, size: .compact, fullWidth: true) {
                                the5ers.disconnect()
                                mcpToken = ""
                                the5ersStatus = "Disconnected from The5ers MCP."
                            }
                        }
                    }
                    
                    if !the5ersStatus.isEmpty {
                        Text(the5ersStatus)
                            .font(AppTypography.caption)
                            .foregroundColor(the5ersStatus.contains("Error") || the5ersStatus.contains("failed") ? AppColors.loss : AppColors.profit)
                    }
                    
                    // Sync Info Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("The5ers accounts: \(dataStore.propAccounts.filter { $0.firm.contains("The5ers") }.count)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text("Synced trades: \(dataStore.trades.filter { $0.tags.contains("the5ers") }.count)")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                }
            }
            
            // Card 2: cTrader Open API Connection
            SettingsCard(title: "cTrader Open API") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("cTrader Cloud Sync")
                            .font(AppTypography.headline)
                        Spacer()
                        Text(ctrader.isConfigured ? (ctrader.isConnected ? "Active · Connected" : "Configured") : "Not configured")
                            .font(AppTypography.captionBold)
                            .foregroundColor(ctrader.isConfigured ? AppColors.profit : AppColors.secondaryText)
                    }
                    
                    Text("Direct high-speed synchronization with cTrader Open API via JSON WebSocket on port 5036. Imports accounts, historical deals, execution fills, and open positions.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    // Environment Picker (Live vs Demo)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gateway Environment:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Picker("Environment", selection: $ctraderIsLive) {
                            Text("Live Accounts (wss://live.ctraderapi.com:5036)").tag(true)
                            Text("Demo Accounts (wss://demo.ctraderapi.com:5036)").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Access Token Field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("cTrader Access Token:")
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
                        
                        Text("Obtain your Access Token from openapi.ctrader.com → Applications → Playground or OAuth.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    // Advanced App Credentials (Client ID & Secret)
                    DisclosureGroup(isExpanded: $showAdvancedCTrader) {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client ID:")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                TextField("Enter cTrader App Client ID", text: $ctraderClientId)
                                    .font(AppTypography.inputText)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client Secret:")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(AppColors.secondaryText)
                                SecureField("Enter cTrader App Client Secret", text: $ctraderClientSecret)
                                    .font(AppTypography.inputText)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Application Credentials (Client ID & Secret)")
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
                        AppButton(
                            "Sync cTrader",
                            icon: "arrow.triangle.2.circlepath",
                            style: .primary,
                            size: .compact,
                            fullWidth: true,
                            isLoading: isSyncingCTrader || ctrader.isSyncing
                        ) {
                            syncCTrader()
                        }
                        .disabled(ctraderToken.trimmingCharacters(in: .whitespaces).isEmpty || isSyncingCTrader)
                        
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
                        .disabled(ctraderToken.trimmingCharacters(in: .whitespaces).isEmpty || isTestingCTrader)
                        
                        if !ctraderToken.isEmpty {
                            AppButton("Clear", icon: "xmark.circle", style: .destructive, size: .compact, fullWidth: true) {
                                ctraderToken = ""
                                ctraderClientId = ""
                                ctraderClientSecret = ""
                                ctrader.accessToken = ""
                                ctrader.clientId = ""
                                ctrader.clientSecret = ""
                                ctrader.disconnect()
                                ctraderStatus = "cTrader credentials cleared."
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
            
            // Card 3: Supabase Cloud Database Sync
            SettingsCard(title: "Supabase connection") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Cloud database sync with Supabase PostgreSQL via PostgREST API.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project URL:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        TextField("https://xyz.supabase.co", text: $supabaseUrl)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Supabase API Key:")
                            .font(AppTypography.captionBold)
                            .foregroundColor(AppColors.secondaryText)
                        SecureField("Paste API key (service_role or anon)...", text: $supabaseAnonKey)
                            .font(AppTypography.inputText)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        
                        Text("Use your Project URL and API Key from Supabase Dashboard → Project Settings → API.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    HStack(spacing: 8) {
                        AppButton("Sync Supabase", icon: "arrow.triangle.2.circlepath", style: .primary, size: .compact, fullWidth: true, isLoading: dataStore.isSyncing) {
                            syncSupabase()
                        }
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        
                        AppButton("Test Connection", icon: "network", style: .secondary, size: .compact, fullWidth: true) {
                            checkSupabaseConnection()
                        }
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        
                        AppButton("Wipe Data", icon: "trash", style: .destructive, size: .compact, fullWidth: true, isLoading: isWipingSupabase) {
                            showWipeConfirmation = true
                        }
                        .disabled(supabaseUrl.trimmingCharacters(in: .whitespaces).isEmpty || supabaseAnonKey.trimmingCharacters(in: .whitespaces).isEmpty || isWipingSupabase)
                    }
                    
                    if let status = supabaseSyncStatus {
                        Text(status)
                            .font(AppTypography.caption)
                            .foregroundColor(status.contains("Error") || status.contains("missing") ? AppColors.loss : AppColors.profit)
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
            supabaseUrl = SupabaseService.shared.supabaseUrl
            supabaseAnonKey = SupabaseService.shared.supabaseAnonKey
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
        .onChange(of: supabaseUrl) { val in
            SupabaseService.shared.configure(url: val, anonKey: supabaseAnonKey)
        }
        .onChange(of: supabaseAnonKey) { val in
            SupabaseService.shared.configure(url: supabaseUrl, anonKey: val)
        }
        .onChange(of: mcpToken) { val in
            the5ers.configure(token: val)
        }
        .alert("Wipe All Supabase Remote Data?", isPresented: $showWipeConfirmation) {
            Button("Wipe All Remote Data", role: .destructive) {
                wipeSupabaseData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all application records across all tables in your Supabase database and reset local cache. You can then perform a fresh sync.")
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
        Task {
            await dataStore.performGlobalSync()
            await MainActor.run {
                if let err = dataStore.lastSyncError {
                    self.the5ersStatus = "Sync failed: \(err)"
                } else if let summary = dataStore.lastSyncSummary {
                    self.the5ersStatus = summary
                } else {
                    self.the5ersStatus = "Successfully synchronized with The5ers!"
                }
            }
        }
    }
    
    private func checkSupabaseConnection() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Validating Project URL and Anon Key..."
            do {
                let res = try await SupabaseService.shared.pingConnection()
                supabaseSyncStatus = res.message
            } catch {
                supabaseSyncStatus = error.localizedDescription
            }
        }
    }
    
    private func wipeSupabaseData() {
        isWipingSupabase = true
        supabaseSyncStatus = "Wiping all tables on Supabase cloud database..."
        Task {
            do {
                try await SupabaseService.shared.wipeAllRemoteData()
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.dataStore.resetAllData()
                    self.supabaseSyncStatus = "All Supabase tables and local data wiped successfully. You can sync again."
                }
            } catch {
                await MainActor.run {
                    self.isWipingSupabase = false
                    self.supabaseSyncStatus = "Wipe error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func syncSupabase() {
        SupabaseService.shared.configure(url: supabaseUrl, anonKey: supabaseAnonKey)
        Task {
            supabaseSyncStatus = "Performing bi-directional sync with Supabase..."
            await dataStore.syncWithSupabase()
            await MainActor.run {
                if let err = dataStore.lastSyncError {
                    self.supabaseSyncStatus = "Sync error: \(err)"
                } else if let summary = dataStore.lastSyncSummary {
                    self.supabaseSyncStatus = summary
                } else {
                    self.supabaseSyncStatus = "Bi-directional sync completed successfully!"
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
        
        Task {
            do {
                let summary = try await dataStore.syncWithCTrader()
                await MainActor.run {
                    self.isSyncingCTrader = false
                    self.ctraderStatus = summary.message
                }
            } catch {
                await MainActor.run {
                    self.isSyncingCTrader = false
                    self.ctraderStatus = "Sync failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 6. AI Settings View
// Ported 1:1 from `AiSettings` in `ai-settings.tsx` & `ai-settings.ts`
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
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(providerName(provider)) API key").font(AppTypography.captionBold)
                    SecureField(isKeyConfigured ? "Key configured (leave blank to keep)" : (provider == "anthropic" ? "sk-ant-…" : "sk-…"), text: $apiKey)
                        .font(AppTypography.inputText)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Leave blank to keep your saved key, or enter a replacement.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                HStack(spacing: 12) {
                    AppButton("Save AI", icon: "checkmark", style: .primary, size: .compact) {
                        saveAiSettings()
                    }
                    
                    if isKeyConfigured {
                        AppButton("Remove key", icon: "trash", style: .destructive, size: .compact) {
                            removeKey()
                        }
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
// Ported 1:1 from `your-data` in `settings/page.tsx` & `api/export/route.ts`
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
                        AppButton("Export JSON", icon: "square.and.arrow.up", style: .secondary, size: .compact) {
                            exportFullJsonBackup()
                        }
                        
                        AppButton("Export CSV", icon: "square.and.arrow.up", style: .secondary, size: .compact) {
                            exportTradesCsv()
                        }
                    }
                }
            }
            
            // Card 2: Reset Database
            SettingsCard(title: "Local Database Management") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Manage on-device storage or reset your local database.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
                    AppButton("Reset and delete all local data", icon: "trash", style: .destructive, size: .compact) {
                        showResetConfirmation = true
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let fileUrl = exportedFileUrl {
                ShareFileSheet(fileUrl: fileUrl)
            }
        }
        .alert("Reset all local data?", isPresented: $showResetConfirmation) {
            Button("Delete all data", role: .destructive) {
                dataStore.resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All trades, journal logs, and notes will be permanently erased from this device.")
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.border.opacity(0.6), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
