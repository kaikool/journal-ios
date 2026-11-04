import Foundation

// MARK: - Supabase Account & Prop Firm DTOs
public struct SupabaseAccountRecord: Codable {
    public let id: String
    public let name: String
    public let broker: String
    public let kind: String
    public let currency: String
    public let initialBalance: Decimal
    public let profitCalcMethod: String
    public let autoSync: Bool
    public let lastSyncAt: String?
    public let archivedAt: String?
    public let createdAt: String
    
    private enum CodingKeys: String, CodingKey {
        case id, name, broker, kind, currency
        case initialBalance = "initial_balance"
        case profitCalcMethod = "profit_calc_method"
        case autoSync = "auto_sync"
        case lastSyncAt = "last_sync_at"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
    }
    
    public init(account: Account) {
        let fmt = ISO8601DateFormatter()
        self.id = account.id
        self.name = account.name
        self.broker = account.broker
        self.kind = account.kind.rawValue
        self.currency = account.currency
        self.initialBalance = account.initialBalance
        self.profitCalcMethod = account.profitCalcMethod.rawValue
        self.autoSync = account.autoSync
        self.lastSyncAt = account.lastSyncAt.map { fmt.string(from: $0) }
        self.archivedAt = account.archivedAt.map { fmt.string(from: $0) }
        self.createdAt = fmt.string(from: account.createdAt)
    }
    
    /// Balances are encoded as exact decimal strings (see `SupabaseTradeRecord.encode`).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(broker, forKey: .broker)
        try c.encode(kind, forKey: .kind)
        try c.encode(currency, forKey: .currency)
        try c.encode(supabaseDecimalString(initialBalance), forKey: .initialBalance)
        try c.encode(profitCalcMethod, forKey: .profitCalcMethod)
        try c.encode(autoSync, forKey: .autoSync)
        try c.encode(lastSyncAt, forKey: .lastSyncAt)
        try c.encode(archivedAt, forKey: .archivedAt)
        try c.encode(createdAt, forKey: .createdAt)
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.name = c.decodeString(forKeys: ["name"]) ?? "Account"
        self.broker = c.decodeString(forKeys: ["broker"]) ?? ""
        self.kind = c.decodeString(forKeys: ["kind", "type"]) ?? "trading"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.initialBalance = c.decodeDecimal(forKeys: ["initial_balance", "initialBalance", "balance", "starting_balance", "startingBalance"]) ?? 0
        self.profitCalcMethod = c.decodeString(forKeys: ["profit_calc_method", "profitCalcMethod"]) ?? "fifo"
        self.autoSync = c.decodeBool(forKeys: ["auto_sync", "autoSync"]) ?? false
        self.lastSyncAt = c.decodeString(forKeys: ["last_sync_at", "lastSyncAt"])
        self.archivedAt = c.decodeString(forKeys: ["archived_at", "archivedAt"])
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"]) ?? JournalIds.nowIso()
    }
    
    public func toAccount() -> Account {
        let parsedLastSync = FlexibleDateParser.parse(lastSyncAt)
        let parsedArchived = FlexibleDateParser.parse(archivedAt)
        let parsedCreated = FlexibleDateParser.parse(createdAt) ?? Date()
        
        return Account(
            id: id,
            name: name,
            broker: broker,
            kind: AccountKind(rawValue: kind) ?? .manual,
            currency: currency,
            initialBalance: initialBalance,
            profitCalcMethod: ProfitCalcMethod(rawValue: profitCalcMethod) ?? .fifo,
            autoSync: autoSync,
            lastSyncAt: parsedLastSync,
            archivedAt: parsedArchived,
            createdAt: parsedCreated
        )
    }
}

public struct SupabasePropAccountRecord: Codable {
    public let id: String
    public let firm: String
    public let name: String
    public let program: String
    public let status: String
    public let currency: String
    public let sizeMinor: Int64?
    public let parentId: String?
    public let journalAccountId: String?
    public let openedOn: String
    public let closedOn: String?
    public let renewalOn: String?
    public let renewalMinor: Int64?
    public let notes: String
    public let archived: Bool
    public let revision: Int
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firm, name, program, status, currency, notes, archived, revision
        case sizeMinor = "size_minor"
        case parentId = "parent_id"
        case journalAccountId = "journal_account_id"
        case openedOn = "opened_on"
        case closedOn = "closed_on"
        case renewalOn = "renewal_on"
        case renewalMinor = "renewal_minor"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(item: PropAccountItem) {
        self.id = item.id
        self.firm = item.firm
        self.name = item.name
        self.program = item.program.rawValue
        self.status = item.status.rawValue
        self.currency = item.currency
        self.sizeMinor = item.sizeMinor
        self.parentId = item.parentId
        self.journalAccountId = item.journalAccountId
        self.openedOn = item.openedOn
        self.closedOn = item.closedOn
        self.renewalOn = item.renewalOn
        self.renewalMinor = item.renewalMinor
        self.notes = item.notes
        self.archived = item.archived
        self.revision = item.revision
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.firm = c.decodeString(forKeys: ["firm"]) ?? "The5ers"
        self.name = c.decodeString(forKeys: ["name"]) ?? "Prop Account"
        self.program = c.decodeString(forKeys: ["program"]) ?? "evaluation"
        self.status = c.decodeString(forKeys: ["status"]) ?? "active"
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.sizeMinor = c.decodeInt64(forKeys: ["size_minor", "sizeMinor"])
        self.parentId = c.decodeString(forKeys: ["parent_id", "parentId"])
        self.journalAccountId = c.decodeString(forKeys: ["journal_account_id", "journalAccountId"])
        self.openedOn = c.decodeString(forKeys: ["opened_on", "openedOn", "created_at", "createdAt"]) ?? JournalIds.nowIso()
        self.closedOn = c.decodeString(forKeys: ["closed_on", "closedOn"])
        self.renewalOn = c.decodeString(forKeys: ["renewal_on", "renewalOn"])
        self.renewalMinor = c.decodeInt64(forKeys: ["renewal_minor", "renewalMinor"])
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.archived = c.decodeBool(forKeys: ["archived"]) ?? false
        self.revision = c.decodeInt(forKeys: ["revision"]) ?? 1
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func toItem() -> PropAccountItem {
        return PropAccountItem(
            id: id,
            firm: firm,
            name: name,
            program: PropProgram(rawValue: program) ?? .evaluation,
            status: PropStatus(rawValue: status) ?? .active,
            currency: currency,
            sizeMinor: sizeMinor,
            parentId: parentId,
            journalAccountId: journalAccountId,
            openedOn: openedOn,
            closedOn: closedOn,
            renewalOn: renewalOn,
            renewalMinor: renewalMinor,
            notes: notes,
            archived: archived,
            revision: revision,
            createdAt: createdAt ?? JournalIds.nowIso(),
            updatedAt: updatedAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropEntryRecord: Codable {
    public let id: String
    public let accountId: String?
    public let firm: String
    public let kind: String
    public let category: String
    public let currency: String
    public let amountMinor: Int64
    public let splitBps: Int
    public let feeMinor: Int64
    public let occurredOn: String
    public let dueOn: String?
    public let status: String
    public let parentId: String?
    public let reference: String
    public let notes: String
    public let voided: Bool
    public let revision: Int
    public let createdAt: String?
    public let updatedAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firm, kind, category, currency, reference, notes, voided, revision
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case splitBps = "split_bps"
        case feeMinor = "fee_minor"
        case occurredOn = "occurred_on"
        case incurredOn = "incurred_on"
        case dueOn = "due_on"
        case status
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(item: PropEntryItem) {
        self.id = item.id
        self.accountId = item.accountId
        self.firm = item.firm
        self.kind = item.kind
        self.category = item.category
        self.currency = item.currency
        self.amountMinor = item.amountMinor
        self.splitBps = item.splitBps
        self.feeMinor = item.feeMinor
        self.occurredOn = item.occurredOn
        self.dueOn = item.dueOn
        self.status = item.status.rawValue
        self.parentId = item.parentId
        self.reference = item.reference
        self.notes = item.notes
        self.voided = item.voided
        self.revision = item.revision
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.accountId = c.decodeString(forKeys: ["account_id", "accountId"])
        self.firm = c.decodeString(forKeys: ["firm"]) ?? "The5ers"
        let rawKind = (c.decodeString(forKeys: ["kind", "type"]) ?? "expense").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if rawKind == "withdrawal" || rawKind == "withdraw" || rawKind == "payout" {
            self.kind = "payout"
        } else if rawKind == "refund" {
            self.kind = "refund"
        } else {
            self.kind = "expense"
        }
        self.category = c.decodeString(forKeys: ["category"]) ?? (self.kind == "payout" ? "payout" : "challenge_fee")
        self.currency = c.decodeString(forKeys: ["currency"]) ?? "USD"
        self.amountMinor = c.decodeInt64(forKeys: ["amount_minor", "amountMinor"]) ?? 0
        self.splitBps = c.decodeInt(forKeys: ["split_bps", "splitBps"]) ?? 8000
        self.feeMinor = c.decodeInt64(forKeys: ["fee_minor", "feeMinor"]) ?? 0
        let occ = c.decodeString(forKeys: ["occurred_on", "occurredOn", "incurred_on", "incurredOn"])
        self.occurredOn = occ ?? JournalIds.nowIso()
        self.dueOn = c.decodeString(forKeys: ["due_on", "dueOn"])
        self.status = c.decodeString(forKeys: ["status"]) ?? "completed"
        self.parentId = c.decodeString(forKeys: ["parent_id", "parentId"])
        self.reference = c.decodeString(forKeys: ["reference"]) ?? ""
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.voided = c.decodeBool(forKeys: ["voided"]) ?? false
        self.revision = c.decodeInt(forKeys: ["revision"]) ?? 1
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
        self.updatedAt = c.decodeString(forKeys: ["updated_at", "updatedAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(accountId, forKey: .accountId)
        try c.encode(firm, forKey: .firm)
        try c.encode(kind, forKey: .kind)
        try c.encode(category, forKey: .category)
        try c.encode(currency, forKey: .currency)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(splitBps, forKey: .splitBps)
        try c.encode(feeMinor, forKey: .feeMinor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encodeIfPresent(dueOn, forKey: .dueOn)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encode(reference, forKey: .reference)
        try c.encode(notes, forKey: .notes)
        try c.encode(voided, forKey: .voided)
        try c.encode(revision, forKey: .revision)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    public func toItem() -> PropEntryItem {
        return PropEntryItem(
            id: id,
            accountId: accountId,
            firm: firm,
            kind: kind,
            category: category,
            currency: currency,
            amountMinor: amountMinor,
            splitBps: splitBps,
            feeMinor: feeMinor,
            occurredOn: occurredOn,
            dueOn: dueOn,
            status: PayoutStatus(rawValue: status) ?? .completed,
            parentId: parentId,
            reference: reference,
            notes: notes,
            voided: voided,
            revision: revision,
            createdAt: createdAt ?? JournalIds.nowIso(),
            updatedAt: updatedAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropReceiptRecord: Codable {
    public let id: String
    public let payoutId: String
    public let kind: String
    public let amountMinor: Int64
    public let occurredOn: String
    public let reference: String
    public let notes: String
    public let voided: Bool
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, kind, reference, notes, voided
        case payoutId = "payout_id"
        case accountId = "account_id"
        case amountMinor = "amount_minor"
        case netAmountMinor = "net_amount_minor"
        case occurredOn = "occurred_on"
        case receivedOn = "received_on"
        case createdAt = "created_at"
    }
    
    public init(item: PropReceiptItem) {
        self.id = item.id
        self.payoutId = item.payoutId
        self.kind = item.kind
        self.amountMinor = item.amountMinor
        self.occurredOn = item.occurredOn
        self.reference = item.reference
        self.notes = item.notes
        self.voided = item.voided
        self.createdAt = item.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.payoutId = c.decodeString(forKeys: ["payout_id", "payoutId", "account_id", "accountId"]) ?? ""
        let rawKind = (c.decodeString(forKeys: ["kind", "type"]) ?? "receipt").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = (rawKind == "reversal") ? "reversal" : "receipt"
        self.amountMinor = c.decodeInt64(forKeys: ["amount_minor", "amountMinor", "net_amount_minor", "netAmountMinor"]) ?? 0
        let occ = c.decodeString(forKeys: ["occurred_on", "occurredOn", "received_on", "receivedOn"])
        self.occurredOn = occ ?? JournalIds.nowIso()
        self.reference = c.decodeString(forKeys: ["reference"]) ?? ""
        self.notes = c.decodeString(forKeys: ["notes", "note"]) ?? ""
        self.voided = c.decodeBool(forKeys: ["voided"]) ?? false
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(payoutId, forKey: .payoutId)
        try c.encode(kind, forKey: .kind)
        try c.encode(amountMinor, forKey: .amountMinor)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encode(reference, forKey: .reference)
        try c.encode(notes, forKey: .notes)
        try c.encode(voided, forKey: .voided)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
    
    public func toItem() -> PropReceiptItem {
        return PropReceiptItem(
            id: id,
            payoutId: payoutId,
            kind: kind,
            amountMinor: amountMinor,
            occurredOn: occurredOn,
            reference: reference,
            notes: notes,
            voided: voided,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}

public struct SupabasePropAuditRecord: Codable {
    public let id: String
    public let entityType: String
    public let entityId: String
    public let beforeJson: String?
    public let afterJson: String
    public let reason: String
    public let createdAt: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, reason
        case entityType = "entity_type"
        case entityId = "entity_id"
        case beforeJson = "before_json"
        case afterJson = "after_json"
        case createdAt = "created_at"
    }
    
    public init(item: PropAuditItem) {
        self.id = item.id
        self.entityType = item.entityType
        self.entityId = item.entityId
        self.beforeJson = item.beforeJson
        self.afterJson = item.afterJson
        self.reason = item.reason
        self.createdAt = item.createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        self.id = c.decodeString(forKeys: ["id"]) ?? UUID().uuidString
        self.entityType = c.decodeString(forKeys: ["entity_type", "entityType"]) ?? "entry"
        self.entityId = c.decodeString(forKeys: ["entity_id", "entityId"]) ?? ""
        self.beforeJson = c.decodeString(forKeys: ["before_json", "beforeJson"])
        self.afterJson = c.decodeString(forKeys: ["after_json", "afterJson"]) ?? "{}"
        self.reason = c.decodeString(forKeys: ["reason"]) ?? "sync"
        self.createdAt = c.decodeString(forKeys: ["created_at", "createdAt"])
    }
    
    public func toItem() -> PropAuditItem {
        return PropAuditItem(
            id: id,
            entityType: entityType,
            entityId: entityId,
            beforeJson: beforeJson,
            afterJson: afterJson,
            reason: reason,
            createdAt: createdAt ?? JournalIds.nowIso()
        )
    }
}