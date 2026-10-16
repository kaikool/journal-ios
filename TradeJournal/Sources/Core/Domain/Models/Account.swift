import Foundation

public struct Account: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var broker: String
    public var kind: AccountKind
    public var currency: String
    public var initialBalance: Decimal
    public var profitCalcMethod: ProfitCalcMethod
    public var autoSync: Bool
    public var lastSyncAt: Date?
    public var archivedAt: Date?
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        broker: String = "",
        kind: AccountKind = .manual,
        currency: String = "USD",
        initialBalance: Decimal = 0,
        profitCalcMethod: ProfitCalcMethod = .fifo,
        autoSync: Bool = false,
        lastSyncAt: Date? = nil,
        archivedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.broker = broker
        self.kind = kind
        self.currency = currency
        self.initialBalance = initialBalance
        self.profitCalcMethod = profitCalcMethod
        self.autoSync = autoSync
        self.lastSyncAt = lastSyncAt
        self.archivedAt = archivedAt
        self.createdAt = createdAt
    }
}

public enum AccountKind: String, Codable, Equatable {
    case sync = "sync"
    case `import` = "import"
    case manual = "manual"
}

public enum ProfitCalcMethod: String, Codable, Equatable {
    case fifo = "fifo"
    case lifo = "lifo"
    case wavg = "wavg"
}

public enum FinancialInvariants {
    /// Ngưỡng số học để xác định một vị thế đã phẳng hoàn toàn (tránh sai số số thập phân nhỏ)
    public static let flatEpsilon: Decimal = Decimal(string: "0.000000001")!
    
    /// Bất biến kiểm tra trạng thái hòa vốn
    public static func isBreakeven(netPnl: Decimal) -> Bool {
        return abs(netPnl) <= flatEpsilon
    }
}
