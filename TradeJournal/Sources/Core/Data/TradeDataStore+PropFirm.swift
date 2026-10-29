import Foundation
import SwiftUI

// MARK: - Prop Firm Management Extension
extension TradeDataStore {
    
    public func savePropAccount(item: PropAccountItem, reason: String = "User update") {
        let now = JournalIds.nowIso()
        var updated = item
        updated.updatedAt = now
        if let idx = propAccounts.firstIndex(where: { $0.id == item.id }) {
            let old = propAccounts[idx]
            updated.revision = old.revision + 1
            propAccounts[idx] = updated
            let audit = PropAuditItem(
                entityType: "account",
                entityId: item.id,
                beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: reason
            )
            propAudits.append(audit)
        } else {
            propAccounts.append(updated)
            let audit = PropAuditItem(
                entityType: "account",
                entityId: item.id,
                beforeJson: nil,
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: "Created"
            )
            propAudits.append(audit)
        }
        saveToDisk()
    }
    
    public func archivePropAccount(id: String, archived: Bool, reason: String = "User archive") {
        guard let idx = propAccounts.firstIndex(where: { $0.id == id }) else { return }
        let old = propAccounts[idx]
        var updated = old
        updated.archived = archived
        updated.revision = old.revision + 1
        updated.updatedAt = JournalIds.nowIso()
        propAccounts[idx] = updated
        let audit = PropAuditItem(
            entityType: "account",
            entityId: id,
            beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
            afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func savePropEntry(item: PropEntryItem, reason: String = "User update") {
        let now = JournalIds.nowIso()
        var updated = item
        updated.updatedAt = now
        if let idx = propEntries.firstIndex(where: { $0.id == item.id }) {
            let old = propEntries[idx]
            updated.revision = old.revision + 1
            propEntries[idx] = updated
            let audit = PropAuditItem(
                entityType: "entry",
                entityId: item.id,
                beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: reason
            )
            propAudits.append(audit)
        } else {
            propEntries.append(updated)
            let audit = PropAuditItem(
                entityType: "entry",
                entityId: item.id,
                beforeJson: nil,
                afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
                reason: "Created"
            )
            propAudits.append(audit)
        }
        saveToDisk()
    }
    
    public func deletePropAccount(id: String) {
        let entryIds = Set(propEntries.filter { $0.accountId == id }.map { $0.id })
        propAccounts.removeAll { $0.id == id }
        propEntries.removeAll { $0.accountId == id }
        propReceipts.removeAll { entryIds.contains($0.payoutId) }
        saveToDisk(immediate: true)
        Task {
            try? await SupabaseService.shared.deletePropAccount(id: id)
        }
    }

    public func deletePropEntry(id: String) {
        propEntries.removeAll { $0.id == id }
        propReceipts.removeAll { $0.payoutId == id }
        saveToDisk(immediate: true)
        Task {
            try? await SupabaseService.shared.deletePropEntry(id: id)
        }
    }

    public func voidPropEntry(id: String, voided: Bool, reason: String = "User void") throws {
        guard let idx = propEntries.firstIndex(where: { $0.id == id }) else {
            throw PropFirmError.notFound("Entry not found.")
        }
        let old = propEntries[idx]
        if voided {
            let activeRefunds = propEntries.filter { $0.parentId == id && !$0.voided }
            if !activeRefunds.isEmpty {
                throw PropFirmError.validation("Void linked refunds before voiding their expense.")
            }
        }
        var updated = old
        updated.voided = voided
        updated.revision = old.revision + 1
        updated.updatedAt = JournalIds.nowIso()
        propEntries[idx] = updated
        let audit = PropAuditItem(
            entityType: "entry",
            entityId: id,
            beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
            afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func addPropReceipt(item: PropReceiptItem, reason: String = "User receipt") throws {
        guard let payoutIdx = propEntries.firstIndex(where: { $0.id == item.payoutId }) else {
            throw PropFirmError.notFound("Payout not found.")
        }
        let payout = propEntries[payoutIdx]
        guard !payout.voided else {
            throw PropFirmError.validation("Cannot add receipt to voided payout.")
        }
        guard item.amountMinor > 0 else {
            throw PropFirmError.validation("Enter a positive receipt amount.")
        }
        
        propReceipts.append(item)
        
        let allReceiptsForPayout = propReceipts.filter { $0.payoutId == item.payoutId && !$0.voided }
        let totalNetReceived = allReceiptsForPayout.reduce(0) { sum, r in
            sum + (r.kind == "reversal" ? -r.amountMinor : r.amountMinor)
        }
        var updatedPayout = payout
        updatedPayout.revision = payout.revision + 1
        updatedPayout.updatedAt = JournalIds.nowIso()
        if totalNetReceived > 0 && updatedPayout.status == .requested {
            updatedPayout.status = .approved
        }
        propEntries[payoutIdx] = updatedPayout
        
        let audit = PropAuditItem(
            entityType: "receipt",
            entityId: item.id,
            beforeJson: nil,
            afterJson: (try? String(data: JSONEncoder().encode(item), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func voidPropReceipt(id: String, payoutId: String, voided: Bool, reason: String = "User void receipt") throws {
        guard let rIdx = propReceipts.firstIndex(where: { $0.id == id && $0.payoutId == payoutId }) else {
            throw PropFirmError.notFound("Receipt not found.")
        }
        let old = propReceipts[rIdx]
        var updated = old
        updated.voided = voided
        propReceipts[rIdx] = updated
        
        let receiptsForPayout = propReceipts.filter { $0.payoutId == payoutId && !$0.voided }
        let totalNet = receiptsForPayout.reduce(0) { $0 + ($1.kind == "reversal" ? -$1.amountMinor : $1.amountMinor) }
        if totalNet < 0 {
            propReceipts[rIdx] = old
            throw PropFirmError.validation("A reversal cannot exceed the money received by that date.")
        }
        
        if let pIdx = propEntries.firstIndex(where: { $0.id == payoutId }) {
            var payout = propEntries[pIdx]
            payout.revision += 1
            payout.updatedAt = JournalIds.nowIso()
            if totalNet == 0 && payout.status == .completed {
                payout.status = .approved
            }
            propEntries[pIdx] = payout
        }
        
        let audit = PropAuditItem(
            entityType: "receipt",
            entityId: id,
            beforeJson: try? String(data: JSONEncoder().encode(old), encoding: .utf8),
            afterJson: (try? String(data: JSONEncoder().encode(updated), encoding: .utf8)) ?? "",
            reason: reason
        )
        propAudits.append(audit)
        saveToDisk()
    }
    
    public func importPropCsvData(csvText: String, preview: Bool = false) throws -> PropCsvImportResult {
        let (res, newEntries, newReceipts, newAudits) = try PropFirmEngine.importPropCsv(
            csvText: csvText,
            preview: preview,
            existingAccounts: propAccounts,
            existingEntries: propEntries,
            existingReceipts: propReceipts,
            existingAudits: propAudits
        )
        if !preview {
            self.propEntries = newEntries
            self.propReceipts = newReceipts
            self.propAudits = newAudits
            saveToDisk(immediate: true)
        }
        return res
    }
}
