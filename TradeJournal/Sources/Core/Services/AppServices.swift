import Foundation

// MARK: - Protocols for Core Networking & Services (Item 2: Dependency Injection)

/// Protocol abstracting AI reflection, coaching, and market analysis services.
public protocol AIReflectionProviding: Sendable {
    func requestReflection(
        action: AIReflectionAction,
        prompt: String?,
        metrics: TradeMetrics?,
        edgeScore: Double?,
        supabaseUrl: String?,
        authToken: String?,
        overrideConfig: AiSettingsConfig?,
        language: String?,
        chartImageBase64: String?,
        chartImagesBase64: [String]?,
        sessionSummary: AIAccountSessionSummary?,
        conversationHistory: [AICoachMessage]?
    ) async throws -> String

    func testConnection(config: AiSettingsConfig) async throws -> String

    func requestTradeCoaching(
        trade: Trade,
        overrideConfig: AiSettingsConfig?,
        prompt: String?,
        conversationHistory: [AICoachMessage]?
    ) async throws -> String

    func requestPreTradeMarketAnalysis(
        symbol: String,
        direction: TradeDirection,
        plannedEntry: Double?,
        plannedStopLoss: Double?,
        plannedTakeProfit: Double?,
        timeframe: String,
        notes: String,
        overrideConfig: AiSettingsConfig?
    ) async throws -> String
}

public extension AIReflectionProviding {
    func requestReflection(
        action: AIReflectionAction,
        prompt: String? = nil,
        metrics: TradeMetrics? = nil,
        edgeScore: Double? = nil,
        supabaseUrl: String? = nil,
        authToken: String? = nil,
        overrideConfig: AiSettingsConfig? = nil,
        language: String? = nil,
        chartImageBase64: String? = nil,
        chartImagesBase64: [String]? = nil,
        sessionSummary: AIAccountSessionSummary? = nil,
        conversationHistory: [AICoachMessage]? = nil
    ) async throws -> String {
        try await requestReflection(
            action: action,
            prompt: prompt,
            metrics: metrics,
            edgeScore: edgeScore,
            supabaseUrl: supabaseUrl,
            authToken: authToken,
            overrideConfig: overrideConfig,
            language: language,
            chartImageBase64: chartImageBase64,
            chartImagesBase64: chartImagesBase64,
            sessionSummary: sessionSummary,
            conversationHistory: conversationHistory
        )
    }

    func requestTradeCoaching(
        trade: Trade,
        overrideConfig: AiSettingsConfig? = nil,
        prompt: String? = nil,
        conversationHistory: [AICoachMessage]? = nil
    ) async throws -> String {
        try await requestTradeCoaching(
            trade: trade,
            overrideConfig: overrideConfig,
            prompt: prompt,
            conversationHistory: conversationHistory
        )
    }

    func requestPreTradeMarketAnalysis(
        symbol: String,
        direction: TradeDirection,
        plannedEntry: Double? = nil,
        plannedStopLoss: Double? = nil,
        plannedTakeProfit: Double? = nil,
        timeframe: String = "15m",
        notes: String = "",
        overrideConfig: AiSettingsConfig? = nil
    ) async throws -> String {
        try await requestPreTradeMarketAnalysis(
            symbol: symbol,
            direction: direction,
            plannedEntry: plannedEntry,
            plannedStopLoss: plannedStopLoss,
            plannedTakeProfit: plannedTakeProfit,
            timeframe: timeframe,
            notes: notes,
            overrideConfig: overrideConfig
        )
    }
}

/// Protocol abstracting Supabase cloud database, auth, and synchronization backend.
public protocol SupabaseProviding: AnyObject, Sendable {
    var supabaseUrl: String { get set }
    var supabaseAnonKey: String { get set }
    var accessToken: String? { get set }

    func configure(url: String, anonKey: String, token: String?)
    func pingConnection() async throws -> (success: Bool, message: String)
    func checkDatabaseTables() async -> (allExist: Bool, missing: [String])
    func loginWithEmail(email: String, password: String) async throws -> String
    func logout()
    func startWebOAuthLogin(provider: String) async throws -> String
}

public extension SupabaseProviding {
    func configure(url: String, anonKey: String) {
        configure(url: url, anonKey: anonKey, token: nil)
    }

    func startWebOAuthLogin() async throws -> String {
        try await startWebOAuthLogin(provider: "google")
    }
}

/// Protocol abstracting The5ers prop firm MCP & sync integration.
public protocol The5ersServiceProviding: AnyObject, Sendable {
    func configure(token: String)
    func disconnect()
    func cancelSync()
    func startOAuthLogin() async throws -> String
    func refreshAccessTokenIfNeeded() async throws -> String?
    func ensureInitialized() async throws
    func pingMcpConnection() async throws -> (success: Bool, message: String)
    func refreshAvailableTools() async
    func callMcpTool(name: String, arguments: [String: Any]) async throws -> [String: Any]
}

public extension The5ersServiceProviding {
    func callMcpTool(name: String) async throws -> [String: Any] {
        try await callMcpTool(name: name, arguments: [:])
    }
}

/// Protocol abstracting Exness broker trade reconciliation and API sync.
public protocol ExnessServiceProviding: AnyObject, Sendable {
    func loadSettings()
    func saveCredentials(host: String, accountId: String, apiKey: String, privateKey: String)
    func getStoredPrivateKey() -> String
    func disconnect()
    func syncServerTimeIfNeeded() async
    func resolveAccessPoint() async -> String
    func syncAccountWithDataStore()
    func testConnection() async throws -> (success: Bool, message: String)
}

/// Protocol abstracting economic calendar data retrieval.
public protocol ForexFactoryProviding: AnyObject, Sendable {
    func fetchEventsIfNeeded(force: Bool) async
    func fetchEvents() async
    func syncWithSupabase() async
}

public extension ForexFactoryProviding {
    func fetchEventsIfNeeded() async {
        await fetchEventsIfNeeded(force: false)
    }
}

// MARK: - Central Service Registry (DI Container)

/// Central service registry providing dependency injection across the app.
/// Features resolve collaborators here instead of reaching for hardcoded `.shared` singletons.
/// Unit tests can inject test doubles/mocks.
public final class AppServices: @unchecked Sendable {
    public static let current = AppServices()

    private let lock = NSLock()
    private var _marketData: any MarketDataProviding = MarketDataService.shared
    private var _aiReflection: any AIReflectionProviding = AIReflectionService.shared
    private var _supabase: any SupabaseProviding = SupabaseService.shared
    private var _the5ers: any The5ersServiceProviding = The5ersService.shared
    private var _exness: any ExnessServiceProviding = ExnessService.shared
    private var _forexFactory: any ForexFactoryProviding = ForexFactoryService.shared

    public var marketData: any MarketDataProviding {
        get { lock.lock(); defer { lock.unlock() }; return _marketData }
        set { lock.lock(); defer { lock.unlock() }; _marketData = newValue }
    }

    public var aiReflection: any AIReflectionProviding {
        get { lock.lock(); defer { lock.unlock() }; return _aiReflection }
        set { lock.lock(); defer { lock.unlock() }; _aiReflection = newValue }
    }

    public var supabase: any SupabaseProviding {
        get { lock.lock(); defer { lock.unlock() }; return _supabase }
        set { lock.lock(); defer { lock.unlock() }; _supabase = newValue }
    }

    public var the5ers: any The5ersServiceProviding {
        get { lock.lock(); defer { lock.unlock() }; return _the5ers }
        set { lock.lock(); defer { lock.unlock() }; _the5ers = newValue }
    }

    public var exness: any ExnessServiceProviding {
        get { lock.lock(); defer { lock.unlock() }; return _exness }
        set { lock.lock(); defer { lock.unlock() }; _exness = newValue }
    }

    public var forexFactory: any ForexFactoryProviding {
        get { lock.lock(); defer { lock.unlock() }; return _forexFactory }
        set { lock.lock(); defer { lock.unlock() }; _forexFactory = newValue }
    }

    private init() {}
}
