import Foundation

/// Represents an authorized cTrader trading account retrieved from the cTrader Open API.
public struct CTraderAccount: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let ctidTraderAccountId: Int64
    public var id: Int64 { ctidTraderAccountId }
    public let traderLogin: Int64
    public let isLive: Bool
    public var brokerTitleShort: String
    public var balance: Decimal
    public var currency: String
    public var leverage: Int
    public var isSelected: Bool
    
    public init(
        ctidTraderAccountId: Int64,
        traderLogin: Int64,
        isLive: Bool,
        brokerTitleShort: String,
        balance: Decimal = 0,
        currency: String = "USD",
        leverage: Int = 100,
        isSelected: Bool = true
    ) {
        self.ctidTraderAccountId = ctidTraderAccountId
        self.traderLogin = traderLogin
        self.isLive = isLive
        self.brokerTitleShort = brokerTitleShort
        self.balance = balance
        self.currency = currency
        self.leverage = leverage
        self.isSelected = isSelected
    }
}

/// Represents an execution deal retrieved from the cTrader Open API.
public struct CTraderDeal: Identifiable, Codable, Sendable {
    public let dealId: Int64
    public var id: Int64 { dealId }
    public let orderId: Int64
    public let positionId: Int64
    public let volume: Int64
    public let filledVolume: Int64
    public let symbolId: Int64
    public var symbolName: String
    public let executionPrice: Double
    public let tradeSide: String
    public let executionTimestamp: Int64
    public let commission: Int64
    public let closePositionDetail: CTraderCloseDetail?
    public let moneyDigits: Int?
}

/// Closing position detail for deals that offset or close an open position.
public struct CTraderCloseDetail: Codable, Sendable {
    public let entryPrice: Double
    public let grossProfit: Int64
    public let swap: Int64
    public let commission: Int64
    public let balance: Int64
    public let closedVolume: Int64
    public let moneyDigits: Int?
}

/// Open position retrieved from cTrader reconcile endpoint.
public struct CTraderPosition: Identifiable, Codable, Sendable {
    public let positionId: Int64
    public var id: Int64 { positionId }
    public let symbolId: Int64
    public var symbolName: String
    public let volume: Int64
    public let tradeSide: String
    public let price: Double
    public let stopLoss: Double?
    public let takeProfit: Double?
    public let openTimestamp: Int64?
    public let swap: Int64
    public let commission: Int64
}

/// Summary report of a cTrader synchronization run.
public struct CTraderSyncSummary: Equatable, Sendable {
    public let accountsSynced: Int
    public let dealsImported: Int
    public let tradesRebuilt: Int
    public let message: String
}
