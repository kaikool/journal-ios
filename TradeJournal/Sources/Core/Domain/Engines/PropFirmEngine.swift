import Foundation

public enum PropProgram: String, CaseIterable, Codable, Sendable {
    case evaluation = "evaluation"
    case verification = "verification"
    case funded = "funded"
    case instantFunded = "instant_funded"
    case live = "live"
    
    public var label: String {
        switch self {
        case .evaluation: return "Đánh giá (Vòng 1)"
        case .verification: return "Xác minh (Vòng 2)"
        case .funded: return "Cấp vốn (Funded)"
        case .instantFunded: return "Cấp vốn tức thì"
        case .live: return "Tài khoản Live"
        }
    }
}

public enum PropStatus: String, CaseIterable, Codable, Sendable {
    case active = "active"
    case inactive = "inactive"
    case passed = "passed"
    case breached = "breached"
    case closed = "closed"
    
    public var label: String {
        switch self {
        case .active: return "Đang hoạt động"
        case .inactive: return "Tạm dừng"
        case .passed: return "Đã đỗ"
        case .breached: return "Phạm quy (Vi phạm)"
        case .closed: return "Đã đóng"
        }
    }
}

public enum PayoutStatus: String, CaseIterable, Codable, Sendable {
    case requested = "requested"
    case approved = "approved"
    case completed = "completed"
    case rejected = "rejected"
    case cancelled = "cancelled"
}

public enum PropExpenseCategory: String, CaseIterable, Codable, Sendable {
    case evaluation = "evaluation"
    case reset = "reset"
    case activation = "activation"
    case subscription = "subscription"
    case platform = "platform"
    case marketData = "market_data"
    case transfer = "transfer"
    case other = "other"
    
    public var label: String {
        switch self {
        case .evaluation: return "Phí thi"
        case .reset: return "Phí reset"
        case .activation: return "Phí kích hoạt"
        case .subscription: return "Đăng ký định kỳ"
        case .platform: return "Nền tảng"
        case .marketData: return "Dữ liệu thị trường"
        case .transfer: return "Phí chuyển tiền"
        case .other: return "Chi phí khác"
        }
    }
}

public struct PropAccountItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var firm: String // Topstep, FTMO, The5ers, FundingPips...
    public var name: String
    public var program: PropProgram
    public var status: PropStatus
    public var currency: String
    public var sizeMinor: Int64? // 50,000 USD = 5,000,000 cents
    public var openedOn: String
    public var closedOn: String?
    public var notes: String
    
    public init(
        id: String = UUID().uuidString,
        firm: String,
        name: String,
        program: PropProgram = .evaluation,
        status: PropStatus = .active,
        currency: String = "USD",
        sizeMinor: Int64? = nil,
        openedOn: String,
        closedOn: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.firm = firm
        self.name = name
        self.program = program
        self.status = status
        self.currency = currency
        self.sizeMinor = sizeMinor
        self.openedOn = openedOn
        self.closedOn = closedOn
        self.notes = notes
    }
}

public struct PropEntryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var accountId: String?
    public var firm: String
    public var kind: String // "expense", "refund", "payout"
    public var category: String
    public var currency: String
    public var amountMinor: Int64
    public var splitBps: Int // 8000 = 80%
    public var feeMinor: Int64
    public var occurredOn: String
    public var dueOn: String?
    public var status: PayoutStatus
    public var reference: String
    public var notes: String
    public var voided: Bool
    
    public init(
        id: String = UUID().uuidString,
        accountId: String? = nil,
        firm: String,
        kind: String,
        category: String,
        currency: String = "USD",
        amountMinor: Int64,
        splitBps: Int = 8000,
        feeMinor: Int64 = 0,
        occurredOn: String,
        dueOn: String? = nil,
        status: PayoutStatus = .completed,
        reference: String = "",
        notes: String = "",
        voided: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.firm = firm
        self.kind = kind
        self.category = category
        self.currency = currency
        self.amountMinor = amountMinor
        self.splitBps = splitBps
        self.feeMinor = feeMinor
        self.occurredOn = occurredOn
        self.dueOn = dueOn
        self.status = status
        self.reference = reference
        self.notes = notes
        self.voided = voided
    }
}

public struct PropReceiptItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var payoutId: String
    public var kind: String // "receipt" | "reversal"
    public var amountMinor: Int64
    public var occurredOn: String
    public var reference: String
    public var notes: String
    public var voided: Bool
    
    public init(
        id: String = UUID().uuidString,
        payoutId: String,
        kind: String = "receipt",
        amountMinor: Int64,
        occurredOn: String,
        reference: String = "",
        notes: String = "",
        voided: Bool = false
    ) {
        self.id = id
        self.payoutId = payoutId
        self.kind = kind
        self.amountMinor = amountMinor
        self.occurredOn = occurredOn
        self.reference = reference
        self.notes = notes
        self.voided = voided
    }
}

public struct CashMovementItem: Identifiable, Sendable {
    public let id: String
    public let entryId: String
    public let accountId: String?
    public let firm: String
    public let currency: String
    public let date: String?
    public let kind: String // "expense" | "refund" | "receipt" | "reversal"
    public let amountMinor: Int64
    public let category: String
    public let reference: String
}

public struct CashSummaryResult: Sendable, Equatable {
    public let spentMinor: Int64
    public let refundsMinor: Int64
    public let netSpendMinor: Int64
    public let receivedMinor: Int64
    public let netMinor: Int64
    public let roi: Double?
}

public struct PayoutProgressResult: Identifiable, Sendable {
    public var id: String { entry.id }
    public let entry: PropEntryItem
    public let actualMinor: Int64
    public let expectedMinor: Int64
    public let remainingMinor: Int64
    public let varianceMinor: Int64
    public let isPartial: Bool
    public let isOverdue: Bool
}

/// Strict minor-unit arithmetic engine porting `lib/prop-firms.ts`
public enum PropFirmEngine {
    
    /// Parses decimal string into minor currency units without float loss (e.g. "120.50" USD -> 12050)
    public static func toMinor(value: String, digits: Int = 2) throws -> Int64 {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let decimal = Decimal(string: trimmed), decimal >= 0 else {
            throw NSError(domain: "PropFirmEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a nonnegative decimal amount."])
        }
        let factor = pow(Decimal(10), digits)
        let minorDecimal = decimal * factor
        return (minorDecimal as NSDecimalNumber).int64Value
    }
    
    /// Formats integer minor units back to decimal string
    public static func fromMinor(_ value: Int64, digits: Int = 2) -> String {
        let factor = pow(10.0, Double(digits))
        let doubleVal = Double(value) / factor
        return String(format: "%.\(digits)f", doubleVal)
    }
    
    /// Exact expected payout formula from source:
    /// `Number((BigInt(entry.amountMinor) * BigInt(entry.splitBps) + 5000n) / 10000n) - entry.feeMinor`
    public static func expectedPayout(entry: PropEntryItem) -> Int64 {
        let amount = entry.amountMinor
        let split = Int64(entry.splitBps)
        let calc = (amount * split + 5000) / 10000
        return calc - entry.feeMinor
    }
    
    /// Sum of all valid receipts minus reversals for a given payout entry
    public static func receivedPayout(id: String, receipts: [PropReceiptItem]) -> Int64 {
        receipts.reduce(0) { sum, row in
            guard !row.voided && row.payoutId == id else { return sum }
            let signed = row.kind == "reversal" ? -row.amountMinor : row.amountMinor
            return sum + signed
        }
    }
    
    /// Reconstructs unified timeline of cash movements (expenses, refunds, payout receipts)
    public static func cashMovements(entries: [PropEntryItem], receipts: [PropReceiptItem]) -> [CashMovementItem] {
        let activeEntries = entries.filter { !$0.voided }
        let entryMap = Dictionary(uniqueKeysWithValues: activeEntries.map { ($0.id, $0) })
        
        let directMovements: [CashMovementItem] = activeEntries
            .filter { $0.kind != "payout" }
            .map { e in
                CashMovementItem(
                    id: e.id,
                    entryId: e.id,
                    accountId: e.accountId,
                    firm: e.firm,
                    currency: e.currency,
                    date: e.occurredOn,
                    kind: e.kind,
                    amountMinor: e.amountMinor,
                    category: e.category,
                    reference: e.reference
                )
            }
        
        let receiptMovements: [CashMovementItem] = receipts.compactMap { r in
            guard let entry = entryMap[r.payoutId], !r.voided else { return nil }
            return CashMovementItem(
                id: r.id,
                entryId: entry.id,
                accountId: entry.accountId,
                firm: entry.firm,
                currency: entry.currency,
                date: r.occurredOn,
                kind: r.kind,
                amountMinor: r.amountMinor,
                category: "payout",
                reference: r.reference
            )
        }
        
        return (directMovements + receiptMovements).sorted {
            let dateA = $0.date ?? ""
            let dateB = $1.date ?? ""
            if dateA != dateB {
                return dateA < dateB
            }
            return $0.id < $1.id
        }
    }
    
    /// Aggregates net cash spend, received payouts, and cash ROI
    public static func cashSummary(rows: [CashMovementItem]) -> CashSummaryResult {
        var spent: Int64 = 0
        var refunds: Int64 = 0
        var received: Int64 = 0
        
        for row in rows {
            if row.kind == "expense" {
                spent += row.amountMinor
            } else if row.kind == "refund" {
                refunds += row.amountMinor
            } else {
                received += row.amountMinor * (row.kind == "reversal" ? -1 : 1)
            }
        }
        
        let netSpend = spent - refunds
        let net = received - netSpend
        let roi: Double? = netSpend > 0 ? Double(net) / Double(netSpend) : nil
        
        return CashSummaryResult(
            spentMinor: spent,
            refundsMinor: refunds,
            netSpendMinor: netSpend,
            receivedMinor: received,
            netMinor: net,
            roi: roi
        )
    }
    
    /// Computes payout progress, remaining balance, and variance
    public static func payoutProgress(
        entries: [PropEntryItem],
        receipts: [PropReceiptItem],
        today: String
    ) -> [PayoutProgressResult] {
        var receivedMap: [String: Int64] = [:]
        for row in receipts where !row.voided {
            let signed = row.kind == "reversal" ? -row.amountMinor : row.amountMinor
            receivedMap[row.payoutId, default: 0] += signed
        }
        
        return entries
            .filter { $0.kind == "payout" && !$0.voided }
            .map { entry in
                let actual = receivedMap[entry.id] ?? 0
                let expected = expectedPayout(entry: entry)
                let isOpen = entry.status == .requested || entry.status == .approved
                let remaining = isOpen ? max(0, expected - actual) : 0
                let variance = actual - expected
                let isPartial = isOpen && actual > 0 && actual < expected
                let isOverdue = isOpen && (entry.dueOn != nil && entry.dueOn! < today) && actual < expected
                
                return PayoutProgressResult(
                    entry: entry,
                    actualMinor: actual,
                    expectedMinor: expected,
                    remainingMinor: remaining,
                    varianceMinor: variance,
                    isPartial: isPartial,
                    isOverdue: isOverdue
                )
            }
    }
}
