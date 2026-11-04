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

