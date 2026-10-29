import Foundation

/// 1:1 port from table `settings` in `schema.pg.ts`
public struct JournalSettingRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String { key }
    public let key: String
    public var value: String
    
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key)) ?? ""
        self.value = (try? c.decode(String.self, forKey: .value)) ?? ""
    }
    
    private enum CodingKeys: String, CodingKey {
        case key, value
    }
}

// MARK: - 1. General Settings (TimeZones)
// Ported 1:1 from `TimeZoneSettings` trong `journal-settings.tsx`
public struct GeneralSettingsConfig: Codable, Equatable, Sendable {
    public var displayTimeZone: String
    public var defaultImportTimeZone: String
    
    public static let `default` = GeneralSettingsConfig(
        displayTimeZone: TimeZone.current.identifier,
        defaultImportTimeZone: "UTC"
    )
    
    public init(displayTimeZone: String = TimeZone.current.identifier, defaultImportTimeZone: String = "UTC") {
        self.displayTimeZone = displayTimeZone
        self.defaultImportTimeZone = defaultImportTimeZone
    }
}

// MARK: - 3. Currency Conversion Settings
// Core implementation detail
public struct CurrencyConversion: Codable, Equatable, Sendable {
    /// When true the dashboard and calendar convert account balances into the reporting currency.
    public var enabled: Bool
    /// Currency every aggregated figure is expressed in.
    public var reportingCurrency: String
    /// `rates[code]` = 1 unit of `code` expressed in `reportingCurrency`.
    public var rates: [String: Decimal]
    
    public static let `default` = CurrencyConversion(
        enabled: true,
        reportingCurrency: "USD",
        rates: [
            "EUR": 1.08,
            "GBP": 1.29,
            "JPY": 0.0066,
            "VND": 0.000039,
            "AUD": 0.65,
            "CAD": 0.72,
            "CHF": 1.13
        ]
    )
    
    public init(enabled: Bool = true, reportingCurrency: String = "USD", rates: [String: Decimal] = [:]) {
        self.enabled = enabled
        self.reportingCurrency = reportingCurrency.uppercased()
        self.rates = rates.reduce(into: [String: Decimal]()) { acc, item in
            acc[item.key.uppercased()] = item.value
        }
    }
    
    /// Conversion context used by the financial engines.
    public var context: CurrencyContext {
        CurrencyContext(reportingCurrency: reportingCurrency, rates: rates, isEnabled: enabled)
    }
    
    /// Converts an amount from `currency` into the reporting currency.
    /// Returns `nil` when no rate is available for the requested pair.
    public func convert(_ amount: Decimal, from currency: String) -> Decimal? {
        context.convert(amount, from: currency, to: reportingCurrency)
    }
    
    /// Converts an account balance into the reporting currency.
    /// Falls back to the raw amount when the currency matches the reporting currency or no rate exists.
    public func convertedBalance(_ amount: Decimal, currency: String) -> Decimal {
        let code = currency.uppercased()
        if code == reportingCurrency.uppercased() { return amount }
        guard enabled else { return amount }
        guard let converted = convert(amount, from: code) else {
            AppLogger.warning("No \(code)->\(reportingCurrency) rate configured; balance of \(amount) \(code) could not be converted.")
            return amount
        }
        return converted
    }
    
    public func rate(for currency: String) -> Decimal {
        if currency.uppercased() == reportingCurrency.uppercased() { return 1.0 }
        return rates[currency.uppercased()] ?? 1.0
    }
}

// MARK: - 4. Market Data Connections
// Core implementation detail
public struct MarketConnectionConfig: Codable, Equatable, Sendable {
    public var binanceEnabled: Bool
    public var oandaApiKey: String
    public var oandaAccountId: String
    public var oandaEnvironment: String // "practice" | "live"
    
    public static let `default` = MarketConnectionConfig(
        binanceEnabled: true,
        oandaApiKey: "",
        oandaAccountId: "",
        oandaEnvironment: "practice"
    )
    
    public init(
        binanceEnabled: Bool = true,
        oandaApiKey: String = "",
        oandaAccountId: String = "",
        oandaEnvironment: String = "practice"
    ) {
        self.binanceEnabled = binanceEnabled
        self.oandaApiKey = oandaApiKey
        self.oandaAccountId = oandaAccountId
        self.oandaEnvironment = oandaEnvironment
    }
}

// MARK: - Trader Profile & AI Memory Configuration
public struct TraderProfileConfig: Codable, Equatable, Sendable {
    public var tradingStyle: String
    public var accountObjective: String
    public var primaryPlaybooks: String
    public var maxRiskPerTrade: String
    public var knownPsychologicalLeaks: String
    public var customMemoryNotes: String
    
    public static let `default` = TraderProfileConfig(
        tradingStyle: "Day Trader / Intraday Scalper",
        accountObjective: "Sustainable Compounding & Capital Preservation",
        primaryPlaybooks: "Price Action, Trend Following, Support & Resistance",
        maxRiskPerTrade: "0.5% - 1.0% per trade (Strict Stop Loss)",
        knownPsychologicalLeaks: "Moving Stop Loss, Premature Profit Taking, FOMO re-entry after taking a loss",
        customMemoryNotes: "Focus on risk-to-reward ratio >= 2:1. Protect capital during consolidation. Never revenge trade."
    )
    
    public init(
        tradingStyle: String = "Day Trader / Intraday Scalper",
        accountObjective: String = "The5ers / Prop Firm High Stakes Evaluation & Sustainable Compounding",
        primaryPlaybooks: String = "Liquidity Sweeps, Order Blocks, Market Structure Breaks, Fair Value Gaps",
        maxRiskPerTrade: String = "0.5% - 1.0% per trade (Strict Stop Loss)",
        knownPsychologicalLeaks: String = "Moving Stop Loss, Premature Profit Taking, FOMO re-entry after taking a loss",
        customMemoryNotes: String = "Focus on risk-to-reward ratio >= 2:1. Protect capital during consolidation. Never revenge trade."
    ) {
        self.tradingStyle = tradingStyle
        self.accountObjective = accountObjective
        self.primaryPlaybooks = primaryPlaybooks
        self.maxRiskPerTrade = maxRiskPerTrade
        self.knownPsychologicalLeaks = knownPsychologicalLeaks
        self.customMemoryNotes = customMemoryNotes
    }
}

// MARK: - 6. AI Provider Settings
// Multi-provider AI reflection layer supporting Groq, OpenRouter, Google Gemini, and OpenAI
public struct AiSettingsConfig: Codable, Equatable, Sendable {
    // Environment or user-configured secret resolution (Zero hardcoding in binary)
    public static let defaultGeminiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    public static let defaultGroqKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
    public static let defaultGroqBackupKey = ProcessInfo.processInfo.environment["GROQ_BACKUP_KEY"] ?? ""
    public static let defaultOpenRouterKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
    
    public var provider: String // "groq" | "openrouter" | "gemini" | "openai" | "github" | "anthropic" | "custom"
    public var model: String
    public var githubKey: String
    public var geminiKey: String
    public var groqKey: String
    public var groqBackupKey: String
    public var openrouterKey: String
    public var openaiKey: String
    public var anthropicKey: String
    public var customEndpoint: String
    public var customKey: String
    public var language: String // "vi" | "en"
    public var traderProfile: TraderProfileConfig
    
    public static let `default` = AiSettingsConfig(
        provider: "gemini",
        model: "gemini-3.5-flash-lite",
        githubKey: "",
        geminiKey: "",
        groqKey: "",
        groqBackupKey: "",
        openrouterKey: "",
        openaiKey: "",
        anthropicKey: "",
        customEndpoint: "",
        customKey: "",
        language: "vi",
        traderProfile: .default
    )
    
    public init(
        provider: String = "gemini",
        model: String = "gemini-3.5-flash-lite",
        githubKey: String = "",
        geminiKey: String = "",
        groqKey: String = "",
        groqBackupKey: String = "",
        openrouterKey: String = "",
        openaiKey: String = "",
        anthropicKey: String = "",
        customEndpoint: String = "",
        customKey: String = "",
        language: String = "vi",
        traderProfile: TraderProfileConfig = .default
    ) {
        self.provider = provider
        self.model = model
        self.githubKey = githubKey
        self.geminiKey = geminiKey
        self.groqKey = groqKey
        self.groqBackupKey = groqBackupKey
        self.openrouterKey = openrouterKey
        self.openaiKey = openaiKey
        self.anthropicKey = anthropicKey
        self.customEndpoint = customEndpoint
        self.customKey = customKey
        self.language = language
        self.traderProfile = traderProfile
    }
    
    enum CodingKeys: String, CodingKey {
        case provider, model, githubKey, geminiKey, groqKey, groqBackupKey, openrouterKey, openaiKey, anthropicKey, customEndpoint, customKey, language, traderProfile, opencodeKey
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var prov = try container.decodeIfPresent(String.self, forKey: .provider) ?? "gemini"
        var mdl = try container.decodeIfPresent(String.self, forKey: .model) ?? "gemini-3.5-flash-lite"
        let ghKey = try container.decodeIfPresent(String.self, forKey: .githubKey) ?? ""
        var gKey = try container.decodeIfPresent(String.self, forKey: .geminiKey) ?? ""
        var grKey = try container.decodeIfPresent(String.self, forKey: .groqKey) ?? ""
        let grBackupKey = try container.decodeIfPresent(String.self, forKey: .groqBackupKey) ?? ""
        var orKey = try container.decodeIfPresent(String.self, forKey: .openrouterKey) ?? ""
        let oaiKey = try container.decodeIfPresent(String.self, forKey: .openaiKey) ?? ""
        let antKey = try container.decodeIfPresent(String.self, forKey: .anthropicKey) ?? ""
        let cEndpoint = try container.decodeIfPresent(String.self, forKey: .customEndpoint) ?? ""
        let cKey = try container.decodeIfPresent(String.self, forKey: .customKey) ?? ""
        let lang = try container.decodeIfPresent(String.self, forKey: .language) ?? "vi"
        var profile = try container.decodeIfPresent(TraderProfileConfig.self, forKey: .traderProfile) ?? .default
        if profile.primaryPlaybooks == "Liquidity Sweeps, Order Blocks, Market Structure Breaks, Fair Value Gaps" {
            profile.primaryPlaybooks = "Price Action, Trend Following, Support & Resistance"
        }
        
        // Resolve keys from environment if not explicitly configured in storage
        if gKey.isEmpty { gKey = Self.defaultGeminiKey }
        if grKey.isEmpty { grKey = Self.defaultGroqKey }
        var finalBackupKey = grBackupKey
        if finalBackupKey.isEmpty { finalBackupKey = Self.defaultGroqBackupKey }
        if orKey.isEmpty { orKey = Self.defaultOpenRouterKey }
        
        if prov == "opencode" || prov == "github" || prov.isEmpty {
            prov = "gemini"
            mdl = "gemini-3.5-flash-lite"
        }
        if prov == "gemini" && (mdl.isEmpty || mdl == "auto" || mdl == "default") {
            mdl = "gemini-3.5-flash-lite"
        }
        if prov == "groq" && (mdl.contains("llama-3.3") || mdl.contains("llama-3.1") || mdl.contains("llama-3.2") || mdl == "qwen/qwen3.8-27b" || mdl.isEmpty) {
            mdl = "auto"
        }
        if prov == "openrouter" && (mdl.isEmpty || mdl == "openrouter/free" || mdl.contains("deepseek-r1:free") || mdl.contains("content-safety")) {
            mdl = "nvidia/nemotron-3.5-super-vl:free"
        }
        
        self.provider = prov
        self.model = mdl
        self.githubKey = ghKey
        self.geminiKey = gKey
        self.groqKey = grKey
        self.groqBackupKey = finalBackupKey
        self.openrouterKey = orKey
        self.openaiKey = oaiKey
        self.anthropicKey = antKey
        self.customEndpoint = cEndpoint
        self.customKey = cKey
        self.language = lang
        self.traderProfile = profile
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(githubKey, forKey: .githubKey)
        try container.encode(geminiKey, forKey: .geminiKey)
        try container.encode(groqKey, forKey: .groqKey)
        try container.encode(groqBackupKey, forKey: .groqBackupKey)
        try container.encode(openrouterKey, forKey: .openrouterKey)
        try container.encode(openaiKey, forKey: .openaiKey)
        try container.encode(anthropicKey, forKey: .anthropicKey)
        try container.encode(customEndpoint, forKey: .customEndpoint)
        try container.encode(customKey, forKey: .customKey)
        try container.encode(language, forKey: .language)
        try container.encode(traderProfile, forKey: .traderProfile)
    }
}
