import Foundation

/// 1:1 port từ bảng `settings` trong `schema.pg.ts`
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
// Port 1:1 từ `TimeZoneSettings` trong `journal-settings.tsx`
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
// Port 1:1 từ `currency-settings.tsx` và `currencies.ts`
public struct CurrencyConversion: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var reportingCurrency: String
    public var rates: [String: Decimal]
    
    public static let `default` = CurrencyConversion(
        enabled: false,
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
    
    public init(enabled: Bool = false, reportingCurrency: String = "USD", rates: [String: Decimal] = [:]) {
        self.enabled = enabled
        self.reportingCurrency = reportingCurrency
        self.rates = rates
    }
    
    public func rate(for currency: String) -> Decimal {
        if currency.uppercased() == reportingCurrency.uppercased() { return 1.0 }
        return rates[currency.uppercased()] ?? 1.0
    }
}

// MARK: - 4. Market Data Connections
// Port 1:1 từ `market-data-settings.tsx` và `market-providers.ts`
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
// Port 1:1 từ `ai-settings.tsx` và `ai-settings.ts`
public struct AiSettingsConfig: Codable, Equatable, Sendable {
    public var provider: String // "anthropic" | "openai"
    public var model: String
    public var anthropicKey: String
    public var openaiKey: String
    
    public static let `default` = AiSettingsConfig(
        provider: "anthropic",
        model: "claude-opus-5",
        anthropicKey: "",
        openaiKey: ""
    )
    
    public init(
        provider: String = "anthropic",
        model: String = "claude-opus-5",
        anthropicKey: String = "",
        openaiKey: String = ""
    ) {
        self.provider = provider
        self.model = model
        self.anthropicKey = anthropicKey
        self.openaiKey = openaiKey
    }
}
