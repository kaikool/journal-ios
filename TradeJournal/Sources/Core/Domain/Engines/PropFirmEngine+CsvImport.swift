import Foundation
import CryptoKit

// MARK: - Generic Prop CSV Import
extension PropFirmEngine {
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
            
            let rowId = row["id"] ?? ""
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
            
            let accountId = (row["account_id"]?.isEmpty == false) ? row["account_id"] : nil
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