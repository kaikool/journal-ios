import Foundation
import CryptoKit

// MARK: - Core Enums

public enum PropProgram: String, CaseIterable, Codable, Sendable {
    case evaluation = "evaluation"
    case verification = "verification"
    case funded = "funded"
    case instantFunded = "instant_funded"
    case live = "live"
    
    public var label: String {
        switch self {
        case .evaluation: return "Evaluation"
        case .verification: return "Verification"
        case .funded: return "Funded"
        case .instantFunded: return "Instant funded"
        case .live: return "Live account"
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
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .passed: return "Passed"
        case .breached: return "Breached"
        case .closed: return "Closed"
        }
    }
}

public enum PayoutStatus: String, CaseIterable, Codable, Sendable {
    case requested = "requested"
    case approved = "approved"
    case completed = "completed"
    case rejected = "rejected"
    case cancelled = "cancelled"
    
    public var label: String {
        switch self {
        case .requested: return "Requested"
        case .approved: return "Approved"
        case .completed: return "Completed"
        case .rejected: return "Rejected"
        case .cancelled: return "Cancelled"
        }
    }
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
        case .evaluation: return "Evaluation fee"
        case .reset: return "Reset fee"
        case .activation: return "Activation fee"
        case .subscription: return "Subscription"
        case .platform: return "Platform"
        case .marketData: return "Market data"
        case .transfer: return "Transfer fee"
        case .other: return "Other expense"
        }
    }
}

// MARK: - Domain Models

public struct PropAccountItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var firm: String
    public var name: String
    public var program: PropProgram
    public var status: PropStatus
    public var currency: String
    public var sizeMinor: Int64?
    public var parentId: String?
    public var journalAccountId: String?
    public var openedOn: String
    public var closedOn: String?
    public var renewalOn: String?
    public var renewalMinor: Int64?
    public var notes: String
    public var archived: Bool
    public var revision: Int
    public let createdAt: String
    public var updatedAt: String
    
    public init(
        id: String = JournalIds.newId(),
        firm: String,
        name: String,
        program: PropProgram = .evaluation,
        status: PropStatus = .active,
        currency: String = "USD",
        sizeMinor: Int64? = nil,
        parentId: String? = nil,
        journalAccountId: String? = nil,
        openedOn: String,
        closedOn: String? = nil,
        renewalOn: String? = nil,
        renewalMinor: Int64? = nil,
        notes: String = "",
        archived: Bool = false,
        revision: Int = 0,
        createdAt: String = JournalIds.nowIso(),
        updatedAt: String = JournalIds.nowIso()
    ) {
        self.id = id
        self.firm = firm
        self.name = name
        self.program = program
        self.status = status
        self.currency = currency
        self.sizeMinor = sizeMinor
        self.parentId = parentId
        self.journalAccountId = journalAccountId
        self.openedOn = openedOn
        self.closedOn = closedOn
        self.renewalOn = renewalOn
        self.renewalMinor = renewalMinor
        self.notes = notes
        self.archived = archived
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PropEntryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var accountId: String?
    public var firm: String
    public var kind: String // "expense" | "refund" | "payout"
    public var category: String
    public var currency: String
    public var amountMinor: Int64
    public var splitBps: Int // 8000 = 80%
    public var feeMinor: Int64
    public var occurredOn: String
    public var dueOn: String?
    public var status: PayoutStatus
    public var parentId: String?
    public var reference: String
    public var notes: String
    public var voided: Bool
    public var revision: Int
    public let createdAt: String
    public var updatedAt: String
    
    public init(
        id: String = JournalIds.newId(),
        accountId: String? = nil,
        firm: String,
        kind: String,
        category: String,
        currency: String = "USD",
        amountMinor: Int64,
        splitBps: Int = 10000,
        feeMinor: Int64 = 0,
        occurredOn: String,
        dueOn: String? = nil,
        status: PayoutStatus = .completed,
        parentId: String? = nil,
        reference: String = "",
        notes: String = "",
        voided: Bool = false,
        revision: Int = 0,
        createdAt: String = JournalIds.nowIso(),
        updatedAt: String = JournalIds.nowIso()
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
        self.parentId = parentId
        self.reference = reference
        self.notes = notes
        self.voided = voided
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PropReceiptItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var payoutId: String
    public var kind: String // "receipt" | "reversal"
    public var amountMinor: Int64
    public var occurredOn: String
    public var reference: String
    public var notes: String
    public var voided: Bool
    public let createdAt: String
    
    public init(
        id: String = JournalIds.newId(),
        payoutId: String,
        kind: String = "receipt",
        amountMinor: Int64,
        occurredOn: String,
        reference: String = "",
        notes: String = "",
        voided: Bool = false,
        createdAt: String = JournalIds.nowIso()
    ) {
        self.id = id
        self.payoutId = payoutId
        self.kind = kind
        self.amountMinor = amountMinor
        self.occurredOn = occurredOn
        self.reference = reference
        self.notes = notes
        self.voided = voided
        self.createdAt = createdAt
    }
}

public struct PropAuditItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let entityType: String
    public let entityId: String
    public let beforeJson: String?
    public let afterJson: String
    public let reason: String
    public let createdAt: String
    
    public init(
        id: String = JournalIds.newId(),
        entityType: String,
        entityId: String,
        beforeJson: String?,
        afterJson: String,
        reason: String,
        createdAt: String = JournalIds.nowIso()
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.beforeJson = beforeJson
        self.afterJson = afterJson
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct CashMovementItem: Identifiable, Equatable, Sendable {
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
    
    public init(
        id: String,
        entryId: String,
        accountId: String?,
        firm: String,
        currency: String,
        date: String?,
        kind: String,
        amountMinor: Int64,
        category: String,
        reference: String
    ) {
        self.id = id
        self.entryId = entryId
        self.accountId = accountId
        self.firm = firm
        self.currency = currency
        self.date = date
        self.kind = kind
        self.amountMinor = amountMinor
        self.category = category
        self.reference = reference
    }
}

public struct CashSummaryResult: Sendable, Equatable {
    public let spentMinor: Int64
    public let refundsMinor: Int64
    public let netSpendMinor: Int64
    public let receivedMinor: Int64
    public let netMinor: Int64
    public let roi: Double?
    
    public init(
        spentMinor: Int64,
        refundsMinor: Int64,
        netSpendMinor: Int64,
        receivedMinor: Int64,
        netMinor: Int64,
        roi: Double?
    ) {
        self.spentMinor = spentMinor
        self.refundsMinor = refundsMinor
        self.netSpendMinor = netSpendMinor
        self.receivedMinor = receivedMinor
        self.netMinor = netMinor
        self.roi = roi
    }
}

public struct CashTimelinePoint: Equatable, Sendable {
    public let date: String
    public let netMinor: Int64
    
    public init(date: String, netMinor: Int64) {
        self.date = date
        self.netMinor = netMinor
    }
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

public struct PropCsvImportResult: Sendable {
    public let imported: Int
    public let skipped: Int
    public let sample: [[String: String]]
}

public enum PropFirmError: LocalizedError, Equatable {
    case validation(String)
    case notFound(String)
    case conflict(String)
    
    public var errorDescription: String? {
        switch self {
        case .validation(let msg): return msg
        case .notFound(let msg): return msg
        case .conflict(let msg): return msg
        }
    }
}

// MARK: - Engine Functions & Financial Math

public enum PropFirmEngine {
    
    private static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA",
        "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]
    
    private static let threeDecimalCurrencies: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"
    ]
    
    /// Currencies that are valid but not part of the traded FX set.
    private static let additionalCurrencies: Set<String> = [
        "AED", "AFN", "ALL", "AMD", "ANG", "AWG", "AZN", "BAM", "BOB", "BYN", "BZD",
        "CDF", "CRC", "CVE", "DJF", "ERN", "ETB", "GHS", "GMD", "GNF", "GTQ", "GYD",
        "HNL", "HTG", "IQD", "JMD", "KES", "KGS", "KHR", "KMF", "KPW", "KZT", "LAK",
        "LBP", "LKR", "LRD", "LSL", "LYD", "MGA", "MKD", "MMK", "MNT", "MRO", "MRU",
        "MUR", "MVR", "MWK", "MZN", "NAD", "NIO", "PAB", "PEN", "PGK", "PKR", "PYG",
        "RWF", "SBD", "SCR", "SDG", "SLE", "SLL", "SOS", "SSP", "STN", "SVC", "SYP",
        "SZL", "TJS", "TOP", "TTD", "TWD", "TZS", "UAH", "UGX", "UYU", "UZS", "VES",
        "VND", "VUV", "WST", "XAF", "XCD", "XOF", "YER", "ZMW", "ZWL"
    ]
    
    /// Returns decimal digit precision for currency (0 for JPY, 3 for BHD/KWD, 2 for USD/EUR/etc.)
    public static func currencyDigits(_ currency: String) throws -> Int {
        let code = currency.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw PropFirmError.validation("Choose a supported three-letter currency code.")
        }
        // Fail closed: an unknown currency must never be silently treated as a 2 decimal currency.
        guard AssetContractEngine.currencyCodes.contains(code) || additionalCurrencies.contains(code) else {
            throw PropFirmError.validation("\(code) is not a supported currency code.")
        }
        if zeroDecimalCurrencies.contains(code) { return 0 }
        if threeDecimalCurrencies.contains(code) { return 3 }
        return 2
    }
    
    /// Converts decimal string to minor currency units (cents)
    public static func toMinor(value: Any?, currency: String) throws -> Int64 {
        let digits = try currencyDigits(currency)
        guard let str = value as? String else {
            throw PropFirmError.validation("Enter a nonnegative decimal amount.")
        }
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: "^\\d+(?:\\.\\d+)?$"),
              regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil else {
            throw PropFirmError.validation("Enter a nonnegative decimal amount.")
        }
        
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let wholeStr = String(parts[0])
        let fractionStr = parts.count > 1 ? String(parts[1]) : ""
        
        if fractionStr.count > digits {
            throw PropFirmError.validation("\(currency) accepts \(digits) decimal places.")
        }
        
        guard let whole = Int64(wholeStr) else {
            throw PropFirmError.validation("Amount is too large.")
        }
        
        let paddedFraction = fractionStr.padding(toLength: digits, withPad: "0", startingAt: 0)
        let fraction = Int64(paddedFraction) ?? 0
        let factor = Int64(pow(10.0, Double(digits)))
        let result = whole * factor + fraction
        
        if result > 10_000_000_000 || result < 0 {
            throw PropFirmError.validation("Amount is too large.")
        }
        return result
    }
    
    /// Formats minor currency units back to localized decimal string
    public static func fromMinor(_ value: Int64, currency: String) throws -> String {
        let digits = try currencyDigits(currency)
        let factor = pow(10.0, Double(digits))
        let doubleVal = Double(value) / factor
        return String(format: "%.\(digits)f", doubleVal)
    }
    
    /// Calculates expected net payout taking into account profit split and fees: ((amountMinor * splitBps + 5000) / 10000) - feeMinor
    public static func expectedPayout(entry: PropEntryItem) -> Int64 {
        let amount = entry.amountMinor
        let split = Int64(entry.splitBps)
        let calc = (amount * split + 5000) / 10000
        return calc - entry.feeMinor
    }
    
    /// Computes total received payout factoring in any reversals
    public static func receivedPayout(id: String, receipts: [PropReceiptItem]) -> Int64 {
        receipts.reduce(0) { sum, row in
            guard !row.voided && row.payoutId == id else { return sum }
            let signed = row.kind == "reversal" ? -row.amountMinor : row.amountMinor
            return sum + signed
        }
    }
    
    public static func receiptSettlementDate(receipt: PropReceiptItem) -> String? {
        if receipt.notes.hasPrefix("[settlement-date-unknown]") {
            return nil
        }
        return receipt.occurredOn
    }
    
    /// Normalizes payout IDs by stripping canonical provider prefixes (the5ers_payout_, payout_, the5ers_rcpt_, rcpt_, etc.)
    public static func canonicalPayoutId(_ id: String) -> String {
        var clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["the5ers_payout_", "payout_", "the5ers_rcpt_", "rcpt_", "THE5ERS-", "the5ers_"]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes {
                if clean.hasPrefix(prefix) {
                    clean = String(clean.dropFirst(prefix.count))
                    changed = true
                }
            }
        }
        return clean
    }
    
    /// Constructs unified cash movement timeline combining expenses, payouts, and refunds
    public static func cashMovements(entries: [PropEntryItem], receipts: [PropReceiptItem]) -> [CashMovementItem] {
        let activeEntries = entries.filter { !$0.voided }
        let entryMap = Dictionary(activeEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        
        var movements: [CashMovementItem] = []
        
        // 1. Direct expenses and fee refunds
        for e in activeEntries where e.kind != "payout" {
            movements.append(CashMovementItem(
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
            ))
        }
        
        // 2. Receipt movements (actual payouts cash received)
        var processedPayoutEntryIds = Set<String>()
        for r in receipts where !r.voided {
            let rCanon = canonicalPayoutId(r.payoutId)
            let matchedEntry = entryMap[r.payoutId] ?? activeEntries.first(where: {
                $0.id == r.payoutId ||
                canonicalPayoutId($0.id) == rCanon ||
                $0.id.hasSuffix(r.payoutId) ||
                r.payoutId.hasSuffix($0.id) ||
                $0.id.cleanAccountId == r.payoutId.cleanAccountId
            })
            if let entry = matchedEntry {
                processedPayoutEntryIds.insert(entry.id)
                processedPayoutEntryIds.insert(canonicalPayoutId(entry.id))
                processedPayoutEntryIds.insert(entry.id.cleanAccountId)
                movements.append(CashMovementItem(
                    id: r.id,
                    entryId: entry.id,
                    accountId: entry.accountId,
                    firm: entry.firm,
                    currency: entry.currency,
                    date: receiptSettlementDate(receipt: r),
                    kind: r.kind,
                    amountMinor: r.amountMinor,
                    category: "payout",
                    reference: r.reference
                ))
            } else {
                movements.append(CashMovementItem(
                    id: r.id,
                    entryId: r.payoutId,
                    accountId: nil,
                    firm: "The5ers",
                    currency: "USD",
                    date: receiptSettlementDate(receipt: r),
                    kind: r.kind,
                    amountMinor: r.amountMinor,
                    category: "payout",
                    reference: r.reference
                ))
            }
        }
        
        // 3. Completed payouts that don't have a separate receipt record
        let unreceiptedCompletedPayouts = activeEntries.filter {
            ($0.kind == "payout" || $0.category.lowercased() == "payout") &&
            $0.status == .completed &&
            !processedPayoutEntryIds.contains($0.id) &&
            !processedPayoutEntryIds.contains(canonicalPayoutId($0.id)) &&
            !processedPayoutEntryIds.contains($0.id.cleanAccountId)
        }
        for p in unreceiptedCompletedPayouts {
            let actualNet = expectedPayout(entry: p)
            movements.append(CashMovementItem(
                id: "payout_net_\(p.id)",
                entryId: p.id,
                accountId: p.accountId,
                firm: p.firm,
                currency: p.currency,
                date: p.occurredOn,
                kind: "receipt",
                amountMinor: actualNet > 0 ? actualNet : p.amountMinor,
                category: "payout",
                reference: p.reference
            ))
        }
        
        return movements.sorted {
            let dateA = $0.date ?? ""
            let dateB = $1.date ?? ""
            if dateA != dateB {
                return dateA < dateB
            }
            return $0.id < $1.id
        }
    }
    
    /// Aggregates net spend, total payouts, and overall ROI across prop firm activities
    public static func cashSummary(rows: [CashMovementItem]) throws -> CashSummaryResult {
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
    
    /// Builds chronological cumulative net balance curve from cash movements
    public static func cashTimeline(rows: [CashMovementItem]) throws -> [CashTimelinePoint] {
        _ = try cashSummary(rows: rows)
        var daysMap: [String: Int64] = [:]
        for row in rows {
            guard let date = row.date else { continue }
            let mult: Int64 = (row.kind == "expense" || row.kind == "reversal") ? -1 : 1
            daysMap[date, default: 0] += row.amountMinor * mult
        }
        let sortedDates = daysMap.keys.sorted()
        var runningNet: Int64 = 0
        var points: [CashTimelinePoint] = []
        for d in sortedDates {
            runningNet += daysMap[d] ?? 0
            points.append(CashTimelinePoint(date: d, netMinor: runningNet))
        }
        return points
    }
    
    /// Evaluates payout request progress, remaining balances, and overdue status
    public static func payoutProgress(
        entries: [PropEntryItem],
        receipts: [PropReceiptItem],
        today: String
    ) -> [PayoutProgressResult] {
        var receivedMap: [String: Int64] = [:]
        for row in receipts where !row.voided {
            let signed = row.kind == "reversal" ? -row.amountMinor : row.amountMinor
            receivedMap[row.payoutId, default: 0] += signed
            let cleanPId = canonicalPayoutId(row.payoutId)
            if cleanPId != row.payoutId {
                receivedMap[cleanPId, default: 0] += signed
            }
            let accClean = row.payoutId.cleanAccountId
            if accClean != row.payoutId && accClean != cleanPId {
                receivedMap[accClean, default: 0] += signed
            }
        }
        
        var mapped = entries
            .filter { ($0.kind == "payout" || $0.category.lowercased() == "payout") && !$0.voided }
            .map { entry in
                let cleanEId = canonicalPayoutId(entry.id)
                let actualFromReceipts = receivedMap[entry.id] ?? receivedMap[cleanEId] ?? receivedMap[entry.id.cleanAccountId] ?? 0
                let expected = expectedPayout(entry: entry)
                // If entry is marked completed but has no separate receipt object, actual received is the expected net
                let actual = (entry.status == .completed && actualFromReceipts == 0) ? (expected > 0 ? expected : entry.amountMinor) : actualFromReceipts
                let isOpen = entry.status == .requested || entry.status == .approved
                let remaining = isOpen ? max(0, expected - actual) : 0
                let variance = actual - expected
                let isPartial = isOpen && actual > 0 && actual < expected
                let isOverdue = isOpen && (entry.dueOn.map { $0 < today } ?? false) && actual < expected
                
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
        
        // Include standalone receipts that have no matching payout entry
        var seenCanonEntryIds = Set<String>()
        for e in entries where (e.kind == "payout" || e.category.lowercased() == "payout") && !e.voided {
            seenCanonEntryIds.insert(canonicalPayoutId(e.id))
            seenCanonEntryIds.insert(e.id)
            seenCanonEntryIds.insert(e.id.cleanAccountId)
        }
        
        for rcpt in receipts where !rcpt.voided {
            let canonPayout = canonicalPayoutId(rcpt.payoutId)
            let canonRcpt = canonicalPayoutId(rcpt.id)
            if !seenCanonEntryIds.contains(canonPayout) && !seenCanonEntryIds.contains(rcpt.payoutId) && !seenCanonEntryIds.contains(canonRcpt) {
                let synId = rcpt.payoutId.isEmpty ? rcpt.id : rcpt.payoutId
                seenCanonEntryIds.insert(canonPayout)
                seenCanonEntryIds.insert(canonRcpt)
                seenCanonEntryIds.insert(synId)
                let syntheticEntry = PropEntryItem(
                    id: synId,
                    accountId: nil,
                    firm: "The5ers",
                    kind: "payout",
                    category: "payout",
                    currency: "USD",
                    amountMinor: rcpt.amountMinor,
                    splitBps: 8000,
                    feeMinor: 0,
                    occurredOn: rcpt.occurredOn,
                    status: .completed,
                    reference: rcpt.reference.isEmpty ? "Payout #\(rcpt.id.prefix(8))" : rcpt.reference,
                    notes: rcpt.notes
                )
                mapped.append(PayoutProgressResult(
                    entry: syntheticEntry,
                    actualMinor: rcpt.amountMinor,
                    expectedMinor: rcpt.amountMinor,
                    remainingMinor: 0,
                    varianceMinor: 0,
                    isPartial: false,
                    isOverdue: false
                ))
            }
        }
        
        return mapped
    }
    
    /// Computes percentage of challenge phases successfully passed
    public static func resolvedPhasePassRate(accounts: [PropAccountItem]) -> Double? {
        let relevant = accounts.filter {
            ($0.program == .evaluation || $0.program == .verification) &&
            ($0.status == .passed || $0.status == .breached)
        }
        if relevant.isEmpty { return nil }
        let passed = relevant.filter { $0.status == .passed }.count
        return Double(passed) / Double(relevant.count)
    }
    
    // MARK: - Generic Prop CSV Import
    
    /// Imports prop transactions from generic CSV matching the schema: id,kind,firm,account_id,currency,date,amount,category,expense_id,reference,notes
    public static func importPropCsv(
        csvText: String,
        preview: Bool,
        existingAccounts: [PropAccountItem],
        existingEntries: [PropEntryItem],
        existingReceipts: [PropReceiptItem],
        existingAudits: [PropAuditItem]
    ) throws -> (result: PropCsvImportResult, entries: [PropEntryItem], receipts: [PropReceiptItem], audits: [PropAuditItem]) {
        guard let data = csvText.data(using: .utf8), data.count <= 2 * 1024 * 1024 else {
            throw PropFirmError.validation("CSV must be 2 MB or smaller.")
        }
        let quoteCount = csvText.filter { $0 == "\"" }.count
        guard quoteCount % 2 == 0 else {
            throw PropFirmError.validation("CSV has an unterminated quoted field.")
        }
        
        let parsedRows = CSVParser.parse(csvText)
        guard let header = parsedRows.first else {
            throw PropFirmError.validation("Use the generic prop cash CSV header template.")
        }
        
        let requiredColumns = [
            "id", "kind", "firm", "account_id", "currency", "date",
            "amount", "category", "expense_id", "reference", "notes"
        ]
        
        guard header.count == requiredColumns.count &&
              Set(header).count == requiredColumns.count &&
              requiredColumns.allSatisfy({ header.contains($0) }) else {
            throw PropFirmError.validation("Use the generic prop cash CSV header template.")
        }
        
        let dataRows = Array(parsedRows.dropFirst()).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !dataRows.isEmpty && dataRows.count <= 1000 else {
            throw PropFirmError.validation("Import 1–1,000 rows at a time.")
        }
        
        var records: [[String: String]] = []
        for (i, row) in dataRows.enumerated() {
            guard row.count == header.count else {
                throw PropFirmError.validation("Row \(i + 2): column count differs from the header.")
            }
            var dict: [String: String] = [:]
            for (idx, col) in header.enumerated() {
                dict[col] = row[idx].trimmingCharacters(in: .whitespaces)
            }
            records.append(dict)
        }
        
        var seenIds = Set<String>()
        for row in records {
            let rowId = row["id"] ?? ""
            guard rowId.range(of: "^[a-zA-Z0-9_-]{1,100}$", options: .regularExpression) != nil && !seenIds.contains(rowId) else {
                throw PropFirmError.validation("Each CSV row needs a unique stable ID.")
            }
            seenIds.insert(rowId)
        }
        
        var updatedEntries = existingEntries
        var updatedReceipts = existingReceipts
        var updatedAudits = existingAudits
        var importedCount = 0
        var skippedCount = 0
        
        let accountMap = Dictionary(uniqueKeysWithValues: existingAccounts.map { ($0.id, $0) })
        
        for (index, row) in records.enumerated() {
            let kind = row["kind"] ?? ""
            guard ["expense", "refund", "payout"].contains(kind) else {
                throw PropFirmError.validation("Row \(index + 2): Kind must be expense, refund or payout (actual cash received).")
            }
            
            let rowId = row["id"]!
            let idHash = JournalIds.sha256(rowId)
            let entryId = "csv-\(idHash)"
            // Sorted keys are required: the fingerprint has to be stable across runs, otherwise a
            // re-import of the same file would look like "different data" and be rejected.
            let rowEncoder = JSONEncoder()
            rowEncoder.outputFormatting = .sortedKeys
            let rowJson = (try? String(data: rowEncoder.encode(row), encoding: .utf8)) ?? ""
            let fingerprint = "CSV import \(JournalIds.sha256(rowJson))"
            
            if let oldEntry = updatedEntries.first(where: { $0.id == entryId }) {
                let matchedAudit = updatedAudits.first { $0.entityId == entryId && $0.reason == fingerprint }
                guard matchedAudit != nil else {
                    throw PropFirmError.validation("Row \(index + 2): This CSV ID was already imported with different data. Edit the existing record or use a new ID for a separate transaction.")
                }
                skippedCount += 1
                continue
            }
            
            let accountId = row["account_id"]?.isEmpty == false ? row["account_id"]! : nil
            if kind == "payout" {
                guard let accId = accountId, let acc = accountMap[accId],
                      acc.program == .funded || acc.program == .instantFunded || acc.program == .live else {
                    throw PropFirmError.validation("Row \(index + 2): Payouts need a funded, instant-funded or live prop account.")
                }
            }
            
            let currency = row["currency"] ?? "USD"
            let amountMinor: Int64
            do {
                amountMinor = try toMinor(value: row["amount"], currency: currency)
            } catch {
                throw PropFirmError.validation("Row \(index + 2): \(error.localizedDescription)")
            }
            
            var parentIdValue: String? = nil
            if let expenseId = row["expense_id"], !expenseId.isEmpty {
                if updatedEntries.contains(where: { $0.id == expenseId }) {
                    parentIdValue = expenseId
                } else {
                    parentIdValue = "csv-\(JournalIds.sha256(expenseId))"
                }
            }
            
            if kind == "refund" {
                guard let pId = parentIdValue, let parentExpense = updatedEntries.first(where: { $0.id == pId }) else {
                    throw PropFirmError.validation("Row \(index + 2): Link this refund to a matching expense in the same account, firm and currency.")
                }
                let priorRefunds = updatedEntries
                    .filter { $0.parentId == pId && !$0.voided && $0.id != entryId }
                    .reduce(0) { $0 + $1.amountMinor }
                guard priorRefunds + amountMinor <= parentExpense.amountMinor else {
                    throw PropFirmError.validation("Row \(index + 2): Refunds cannot exceed the original expense.")
                }
            }
            
            let newEntry = PropEntryItem(
                id: entryId,
                accountId: accountId,
                firm: row["firm"] ?? "",
                kind: kind,
                category: kind == "expense" ? (row["category"] ?? "evaluation") : kind,
                currency: currency,
                amountMinor: amountMinor,
                splitBps: 10000,
                feeMinor: 0,
                occurredOn: row["date"] ?? "",
                status: kind == "payout" ? .completed : .completed,
                parentId: parentIdValue,
                reference: row["reference"] ?? "",
                notes: row["notes"] ?? "",
                voided: false,
                revision: kind == "payout" ? 2 : 1
            )
            
            updatedEntries.append(newEntry)
            
            if kind == "payout" {
                let receipt = PropReceiptItem(
                    id: "\(entryId)-cash",
                    payoutId: entryId,
                    kind: "receipt",
                    amountMinor: amountMinor,
                    occurredOn: row["date"] ?? "",
                    reference: row["reference"] ?? "",
                    notes: row["notes"] ?? "",
                    voided: false
                )
                updatedReceipts.append(receipt)
            }
            
            let audit = PropAuditItem(
                entityType: "entry",
                entityId: entryId,
                beforeJson: nil,
                afterJson: rowJson,
                reason: fingerprint
            )
            updatedAudits.append(audit)
            importedCount += 1
        }
        
        let sample = Array(records.prefix(5))
        let importResult = PropCsvImportResult(imported: importedCount, skipped: skippedCount, sample: sample)
        
        if preview {
            // Preview mode returns dry-run results without mutating persistent state
            return (importResult, existingEntries, existingReceipts, existingAudits)
        }
        
        return (importResult, updatedEntries, updatedReceipts, updatedAudits)
    }
}
