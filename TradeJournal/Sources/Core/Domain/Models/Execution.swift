import Foundation

public typealias AssetClass = String // "equity" | "option" | "futures" | "forex" | "crypto" | "cfd" | "other"
public typealias ExecutionSource = String // "sync" | "import" | "manual"

/// Atomic execution fill model (Execution Fill)
public struct Execution: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let accountId: String
    public let symbol: String
    public let side: ExecutionSide
    public let quantity: Decimal
    public let price: Decimal
    public let fee: Decimal
    public let executedAt: Date
    public let assetClass: AssetClass?
    public let source: ExecutionSource
    public let contentHash: String
    public let importMetadataJson: String?
    
    public init(
        id: String = UUID().uuidString,
        accountId: String,
        symbol: String,
        side: ExecutionSide,
        quantity: Decimal,
        price: Decimal,
        fee: Decimal = 0,
        executedAt: Date,
        assetClass: AssetClass? = nil,
        source: ExecutionSource = "manual",
        contentHash: String? = nil,
        importMetadataJson: String? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.executedAt = executedAt
        self.assetClass = assetClass
        self.source = source
        self.importMetadataJson = importMetadataJson
        
        if let contentHash = contentHash {
            self.contentHash = contentHash
        } else {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoTime = f.string(from: executedAt)
            self.contentHash = JournalIds.executionHash(
                symbol: symbol,
                side: side.rawValue,
                quantity: quantity,
                price: price,
                executedAt: isoTime
            )
        }
    }
}

public enum ExecutionSide: String, Codable, Equatable {
    case buy = "buy"
    case sell = "sell"
}

public enum TradeDirection: String, Codable, Equatable {
    case long = "long"
    case short = "short"
}

public enum TradeStatus: String, Codable, Equatable {
    case open = "open"
    case win = "win"
    case loss = "loss"
    case breakeven = "breakeven"
}

/// Domain specification matching core web repository
public struct ExitAttribution: Codable, Equatable, Hashable {
    public let executionId: String
    public let grossPnl: Decimal
    public let quantity: Decimal
    
    public init(executionId: String, grossPnl: Decimal, quantity: Decimal) {
        self.executionId = executionId
        self.grossPnl = grossPnl
        self.quantity = quantity
    }
}

/// Flat-to-Flat round-trip trade cycle (RoundTrip / Trade)
public struct Trade: Identifiable, Codable, Equatable {
    public var id: String { key }
    public let key: String
    public var accountId: String
    public let symbol: String
    public let assetClass: AssetClass?
    public let direction: TradeDirection
    public var status: TradeStatus
    public let openedAt: Date
    public var closedAt: Date?
    public let quantity: Decimal
    public var openQuantity: Decimal
    public let avgEntry: Decimal
    public var avgExit: Decimal?
    public var grossPnl: Decimal
    public var fees: Decimal
    public var netPnl: Decimal
    public let executionCount: Int
    public let executionIds: [String]
    public var exits: [ExitAttribution]
    public var durationMs: Int64?
    public var contractMultiplier: Decimal?
    
    public var side: String { direction.rawValue }
    public var entryPrice: Decimal { avgEntry }
    
// User-annotated properties (User Annotations)
    public var notes: String?
    public var tags: [String]
    public var mistakes: [String]
    public var playbookId: String?
    public var rating: Int?
    public var stopLoss: Decimal?
    public var profitTarget: Decimal?
    public var reviewedAt: Date?
    
    public init(
        key: String,
        accountId: String,
        symbol: String,
        assetClass: AssetClass? = nil,
        direction: TradeDirection,
        status: TradeStatus,
        openedAt: Date,
        closedAt: Date? = nil,
        quantity: Decimal,
        openQuantity: Decimal,
        avgEntry: Decimal,
        avgExit: Decimal? = nil,
        grossPnl: Decimal,
        fees: Decimal,
        netPnl: Decimal,
        executionCount: Int,
        executionIds: [String],
        exits: [ExitAttribution] = [],
        durationMs: Int64? = nil,
        contractMultiplier: Decimal? = nil,
        notes: String? = nil,
        tags: [String] = [],
        mistakes: [String] = [],
        playbookId: String? = nil,
        rating: Int? = nil,
        stopLoss: Decimal? = nil,
        profitTarget: Decimal? = nil,
        reviewedAt: Date? = nil
    ) {
        self.key = key
        self.accountId = accountId
        self.symbol = symbol
        self.assetClass = assetClass
        self.direction = direction
        self.status = status
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.quantity = quantity
        self.openQuantity = openQuantity
        self.avgEntry = avgEntry
        self.avgExit = avgExit
        self.grossPnl = grossPnl
        self.fees = fees
        self.netPnl = netPnl
        self.executionCount = executionCount
        self.executionIds = executionIds
        self.exits = exits
        self.durationMs = durationMs
        self.contractMultiplier = contractMultiplier
        self.notes = notes
        self.tags = tags
        self.mistakes = mistakes
        self.playbookId = playbookId
        self.rating = rating
        self.stopLoss = stopLoss
        self.profitTarget = profitTarget
        self.reviewedAt = reviewedAt
    }
    
    public var annotations: TradeAnnotations? {
        TradeAnnotations(
            notes: notes,
            tags: tags,
            mistakes: mistakes,
            playbook: playbookId,
            rating: rating,
            stopLoss: stopLoss,
            profitTarget: profitTarget,
            reviewedAt: reviewedAt
        )
    }
}

public struct TradeAnnotations: Codable, Equatable, Sendable {
    public var tags: [String]
    public var mistakes: [String]
    public var playbook: String?
    public var notes: String?
    public var rating: Int?
    public var stopLoss: Decimal?
    public var profitTarget: Decimal?
    public var reviewedAt: Date?
    
    public init(
        notes: String? = nil,
        tags: [String]? = nil,
        mistakes: [String]? = nil,
        playbook: String? = nil,
        rating: Int? = nil,
        stopLoss: Decimal? = nil,
        profitTarget: Decimal? = nil,
        reviewedAt: Date? = nil
    ) {
        self.notes = notes
        self.tags = tags ?? []
        self.mistakes = mistakes ?? []
        self.playbook = playbook
        self.rating = rating
        self.stopLoss = stopLoss
        self.profitTarget = profitTarget
        self.reviewedAt = reviewedAt
    }
}
