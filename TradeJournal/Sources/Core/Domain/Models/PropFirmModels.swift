import Foundation
import CryptoKit

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
    
    // Authoritative Hub / Broker Metrics (synced from official API/MCP balance & statistics)
    public var balanceMinor: Int64?
    public var equityMinor: Int64?
    public var netPnlMinor: Int64?
    public var totalFeesMinor: Int64?
    public var totalTrades: Int?
    public var winRate: Double?
    public var profitFactor: Double?
    
    // Authoritative Program Objectives & Progress (synced from official the5ers_program / rules / journey)
    public var profitTargetMinor: Int64?
    public var maxLossMinor: Int64?
    public var maxDailyLossMinor: Int64?
    public var minTradingDays: Int?
    public var currentTradingDays: Int?
    public var winningDays: Int?
    public var currentStepName: String?
    
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
        updatedAt: String = JournalIds.nowIso(),
        balanceMinor: Int64? = nil,
        equityMinor: Int64? = nil,
        netPnlMinor: Int64? = nil,
        totalFeesMinor: Int64? = nil,
        totalTrades: Int? = nil,
        winRate: Double? = nil,
        profitFactor: Double? = nil,
        profitTargetMinor: Int64? = nil,
        maxLossMinor: Int64? = nil,
        maxDailyLossMinor: Int64? = nil,
        minTradingDays: Int? = nil,
        currentTradingDays: Int? = nil,
        winningDays: Int? = nil,
        currentStepName: String? = nil
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
        self.balanceMinor = balanceMinor
        self.equityMinor = equityMinor
        self.netPnlMinor = netPnlMinor
        self.totalFeesMinor = totalFeesMinor
        self.totalTrades = totalTrades
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.profitTargetMinor = profitTargetMinor
        self.maxLossMinor = maxLossMinor
        self.maxDailyLossMinor = maxDailyLossMinor
        self.minTradingDays = minTradingDays
        self.currentTradingDays = currentTradingDays
        self.winningDays = winningDays
        self.currentStepName = currentStepName
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
