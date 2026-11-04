import Foundation
import CryptoKit

// MARK: - Engine Functions & Financial Math

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
        let wholeStr = parts.first.map(String.init) ?? ""
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
    
}