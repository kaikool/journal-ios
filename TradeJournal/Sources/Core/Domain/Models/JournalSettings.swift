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

// MARK: - 6. AI Provider Settings
// Core implementation detail
public struct AiSettingsConfig: Codable, Equatable, Sendable {
    public var provider: String // "opencode" | "anthropic" | "openai"
    public var model: String
    public var opencodeKey: String
    public var anthropicKey: String
    public var openaiKey: String
    
    public static let `default` = AiSettingsConfig(
        provider: "opencode",
        model: "deepseek-v4.1-flash-free",
        opencodeKey: "",
        anthropicKey: "",
        openaiKey: ""
    )
    
    public init(
        provider: String = "opencode",
        model: String = "deepseek-v4.1-flash-free",
        opencodeKey: String = "",
        anthropicKey: String = "",
        openaiKey: String = ""
    ) {
        self.provider = provider
        self.model = model
        self.opencodeKey = opencodeKey
        self.anthropicKey = anthropicKey
        self.openaiKey = openaiKey
    }
    
    enum CodingKeys: String, CodingKey {
        case provider, model, opencodeKey, anthropicKey, openaiKey
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var prov = try container.decodeIfPresent(String.self, forKey: .provider) ?? "opencode"
        var mdl = try container.decodeIfPresent(String.self, forKey: .model) ?? "deepseek-v4.1-flash-free"
        let openKey = try container.decodeIfPresent(String.self, forKey: .opencodeKey) ?? ""
        let antKey = try container.decodeIfPresent(String.self, forKey: .anthropicKey) ?? ""
        let oaiKey = try container.decodeIfPresent(String.self, forKey: .openaiKey) ?? ""
        
        // If legacy default was unconfigured, upgrade to opencode free tier
        if prov == "anthropic" && antKey.isEmpty {
            prov = "opencode"
            mdl = "deepseek-v4.1-flash-free"
        } else if prov == "opencode" && (mdl.hasPrefix("claude-") || mdl.hasPrefix("gpt-")) {
            mdl = "deepseek-v4.1-flash-free"
        }
        
        self.provider = prov
        self.model = mdl
        self.opencodeKey = openKey
        self.anthropicKey = antKey
        self.openaiKey = oaiKey
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(opencodeKey, forKey: .opencodeKey)
        try container.encode(anthropicKey, forKey: .anthropicKey)
        try container.encode(openaiKey, forKey: .openaiKey)
    }
}
