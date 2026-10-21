import Foundation

/// 1:1 port from table `market_csv_datasets` in `schema.pg.ts`
public struct MarketCsvDataset: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var symbol: String
    public var resolution: String
    public var currency: String
    public var priceBasis: String
    public var storagePath: String
    public var checksum: String
    public var formatVersion: Int
    public var barCount: Int
    public var firstTime: Int64
    public var lastTime: Int64
    public let importedAt: String
    
    public init(
        id: String = JournalIds.newId(),
        name: String,
        symbol: String,
        resolution: String,
        currency: String = "USD",
        priceBasis: String = "trades",
        storagePath: String,
        checksum: String,
        formatVersion: Int = 1,
        barCount: Int,
        firstTime: Int64,
        lastTime: Int64,
        importedAt: String = JournalIds.nowIso()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.resolution = resolution
        self.currency = currency
        self.priceBasis = priceBasis
        self.storagePath = storagePath
        self.checksum = checksum
        self.formatVersion = formatVersion
        self.barCount = barCount
        self.firstTime = firstTime
        self.lastTime = lastTime
        self.importedAt = importedAt
    }
}

/// 1:1 port from table `trade_excursions` in `schema.pg.ts`
public struct TradeExcursion: Codable, Sendable, Equatable {
    public let tradeKey: String
    public let fingerprint: String
    public let provider: String
    public let symbol: String
    public let resolution: String
    public let fetchedAt: String
    public let datasetId: String?
    public let estimateJson: String
    
    public init(
        tradeKey: String,
        fingerprint: String,
        provider: String,
        symbol: String,
        resolution: String,
        fetchedAt: String = JournalIds.nowIso(),
        datasetId: String? = nil,
        estimateJson: String
    ) {
        self.tradeKey = tradeKey
        self.fingerprint = fingerprint
        self.provider = provider
        self.symbol = symbol
        self.resolution = resolution
        self.fetchedAt = fetchedAt
        self.datasetId = datasetId
        self.estimateJson = estimateJson
    }
}
