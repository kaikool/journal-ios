import Foundation

// MARK: - Footprint Session Types
public enum FootprintSessionType: String, Codable, Sendable, CaseIterable {
    case tokyo = "tokyo"
    case london = "london"
    case newYork = "new_york"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    public var title: String {
        switch self {
        case .tokyo: return "Tokyo Session"
        case .london: return "London Session"
        case .newYork: return "New York Session"
        case .daily: return "Daily Profile"
        case .weekly: return "Weekly Profile"
        case .monthly: return "Monthly Profile"
        }
    }

    public var shortCode: String {
        switch self {
        case .tokyo: return "TYO"
        case .london: return "LDN"
        case .newYork: return "NYC"
        case .daily: return "D1"
        case .weekly: return "W1"
        case .monthly: return "MN"
        }
    }
}

// MARK: - Footprint Discrete Price Bin
public struct FootprintBin: Identifiable, Codable, Sendable, Equatable {
    public var id: Int { key }
    public let key: Int
    public let price: Decimal
    public var volume: Decimal

    public init(key: Int, price: Decimal, volume: Decimal) {
        self.key = key
        self.price = price
        self.volume = volume
    }
}

// MARK: - Session Profile Snapshot (Historical & Frozen)
/// Immutable snapshot of a completed session, day, or week.
/// Persisted in Supabase `session_footprint_profiles` to eliminate redundant OANDA API candle requests.
public struct SessionProfileSnapshot: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let symbol: String
    public let sessionType: FootprintSessionType
    public let sessionDate: String // YYYY-MM-DD
    public let startTime: Date
    public let endTime: Date
    public let pocPrice: Decimal
    public let vahPrice: Decimal
    public let valPrice: Decimal
    public let profileHigh: Decimal
    public let profileLow: Decimal
    public let totalVolume: Decimal
    public var isNaked: Bool
    public var mitigatedAt: Date?
    public var priorStepPocPrice: Decimal?
    public let createdAt: Date

    public init(
        id: String = JournalIds.newId(),
        symbol: String,
        sessionType: FootprintSessionType,
        sessionDate: String,
        startTime: Date,
        endTime: Date,
        pocPrice: Decimal,
        vahPrice: Decimal,
        valPrice: Decimal,
        profileHigh: Decimal,
        profileLow: Decimal,
        totalVolume: Decimal,
        isNaked: Bool = true,
        mitigatedAt: Date? = nil,
        priorStepPocPrice: Decimal? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.sessionType = sessionType
        self.sessionDate = sessionDate
        self.startTime = startTime
        self.endTime = endTime
        self.pocPrice = pocPrice
        self.vahPrice = vahPrice
        self.valPrice = valPrice
        self.profileHigh = profileHigh
        self.profileLow = profileLow
        self.totalVolume = totalVolume
        self.isNaked = isNaked
        self.mitigatedAt = mitigatedAt
        self.priorStepPocPrice = priorStepPocPrice
        self.createdAt = createdAt
    }
}

// MARK: - Developing Session Profile (Live / Realtime)
public struct DevelopingProfile: Sendable, Equatable {
    public let sessionType: FootprintSessionType
    public let startTime: Date
    public var currentPoc: Decimal?
    public var currentVah: Decimal?
    public var currentVal: Decimal?
    public var profileHigh: Decimal?
    public var profileLow: Decimal?
    public var totalVolume: Decimal
    public var bins: [FootprintBin]

    public init(
        sessionType: FootprintSessionType,
        startTime: Date,
        currentPoc: Decimal? = nil,
        currentVah: Decimal? = nil,
        currentVal: Decimal? = nil,
        profileHigh: Decimal? = nil,
        profileLow: Decimal? = nil,
        totalVolume: Decimal = .zero,
        bins: [FootprintBin] = []
    ) {
        self.sessionType = sessionType
        self.startTime = startTime
        self.currentPoc = currentPoc
        self.currentVah = currentVah
        self.currentVal = currentVal
        self.profileHigh = profileHigh
        self.profileLow = profileLow
        self.totalVolume = totalVolume
        self.bins = bins
    }
}

// MARK: - Key Level Definition
public enum KeyLevelType: Codable, Sendable, Equatable {
    case sessionPoc(FootprintSessionType)
    case nakedPoc(FootprintSessionType, age: Int)
    case vah(FootprintSessionType)
    case val(FootprintSessionType)
    case pdh
    case pdl
    case pdc
}

public struct KeyLevel: Identifiable, Sendable, Equatable {
    public var id: String { "\(label)_\(price)" }
    public let type: KeyLevelType
    public let price: Decimal
    public let label: String
    public let isNaked: Bool

    public init(type: KeyLevelType, price: Decimal, label: String, isNaked: Bool = false) {
        self.type = type
        self.price = price
        self.label = label
        self.isNaked = isNaked
    }
}

// MARK: - Candlestick Pattern Types
public enum CandlePatternType: String, Codable, Sendable, CaseIterable {
    case bullishPinbar = "Bullish Pinbar"
    case bearishPinbar = "Bearish Pinbar"
    case bullishEngulfing = "Bullish Engulfing"
    case bearishEngulfing = "Bearish Engulfing"
    case marubozuBullish = "Bullish Marubozu"
    case marubozuBearish = "Bearish Marubozu"
    case insideBar = "Inside Bar"
    case doji = "Doji"
    case morningStar = "Morning Star"
    case eveningStar = "Evening Star"
    case tweezerBottom = "Tweezer Bottom"
    case tweezerTop = "Tweezer Top"
    case threeWhiteSoldiers = "Three White Soldiers"
    case threeBlackCrows = "Three Black Crows"

    public var isBullish: Bool {
        switch self {
        case .bullishPinbar, .bullishEngulfing, .marubozuBullish, .morningStar, .tweezerBottom, .threeWhiteSoldiers:
            return true
        default:
            return false
        }
    }

    public var isBearish: Bool {
        switch self {
        case .bearishPinbar, .bearishEngulfing, .marubozuBearish, .eveningStar, .tweezerTop, .threeBlackCrows:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        rawValue
    }
}

// MARK: - Detected Candlestick Pattern with Price Action Context
public struct DetectedCandlePattern: Identifiable, Sendable, Equatable {
    public let id: String
    public let type: CandlePatternType
    public let barTimestamp: Int64
    public let price: Decimal
    public let confluenceKeyLevel: KeyLevel?
    public let summary: String

    public init(
        id: String = JournalIds.newId(),
        type: CandlePatternType,
        barTimestamp: Int64,
        price: Decimal,
        confluenceKeyLevel: KeyLevel? = nil,
        summary: String
    ) {
        self.id = id
        self.type = type
        self.barTimestamp = barTimestamp
        self.price = price
        self.confluenceKeyLevel = confluenceKeyLevel
        self.summary = summary
    }
}
