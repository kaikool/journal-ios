import Foundation

/// Abstraction over the market data backend so features depend on a protocol
/// instead of the concrete `MarketDataService` singleton (testable / mockable).
public protocol MarketDataProviding: Sendable {
    func fetchBarsForTrade(
        trade: Trade,
        config: MarketConnectionConfig,
        resolution: String,
        forceRefresh: Bool
    ) async throws -> (provider: String, bars: [MarketBar])

    func fetchBarsForSymbol(
        symbol: String,
        config: MarketConnectionConfig,
        resolution: String,
        count: Int,
        forceRefresh: Bool
    ) async throws -> (provider: String, bars: [MarketBar])

    func testOandaConnection(
        apiKey: String,
        accountId: String,
        environment: String
    ) async -> (success: Bool, message: String)

    func testBinanceConnection() async -> (success: Bool, message: String)
}

extension MarketDataService: MarketDataProviding {}

/// Central service registry. Features resolve collaborators here instead of reaching
/// for `.shared` singletons directly; tests may replace entries with fakes.
public final class AppServices: @unchecked Sendable {
    public static let current = AppServices()

    private let lock = NSLock()
    private var _marketData: any MarketDataProviding = MarketDataService.shared

    public var marketData: any MarketDataProviding {
        get { lock.lock(); defer { lock.unlock() }; return _marketData }
        set { lock.lock(); defer { lock.unlock() }; _marketData = newValue }
    }

    private init() {}
}
