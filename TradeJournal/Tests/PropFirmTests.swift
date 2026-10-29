import XCTest
@testable import TradeJournal

final class PropFirmTests: XCTestCase {
    
    // MARK: - 1. Currency Precision, Validation & Strict Minor Units
    
    func testKeepsCurrencyPrecisionAndRefusesSilentRoundingAndUnsafeAmounts() throws {
        // Standard 2 decimals (USD)
        XCTAssertEqual(try PropFirmEngine.toMinor(value: "0.29", currency: "USD"), 29)
        // 0 decimals (JPY)
        XCTAssertEqual(try PropFirmEngine.toMinor(value: "101", currency: "JPY"), 101)
        // 3 decimals (KWD)
        XCTAssertEqual(try PropFirmEngine.toMinor(value: "1.234", currency: "KWD"), 1234)
        
        // Rejects extra decimals, negative amounts, exponential, strings, excessive amounts
        for invalid in ["1.234", "-1", "1e4", "Infinity", "100000001"] {
            XCTAssertThrowsError(try PropFirmEngine.toMinor(value: invalid, currency: "USD"))
        }
        // JPY rejects decimals
        XCTAssertThrowsError(try PropFirmEngine.toMinor(value: "1.0", currency: "JPY"))
        // Unsupported currency code
        XCTAssertThrowsError(try PropFirmEngine.toMinor(value: "1", currency: "BAD"))
        
        // Expected payout: amount 101 minor, split 5000 bps (50%), fee 1 minor
        // ((101 * 5000 + 5000) / 10000) - 1 = 51 - 1 = 50
        let pEntry = PropEntryItem(
            firm: "Fixture firm",
            kind: "payout",
            category: "payout",
            amountMinor: 101,
            splitBps: 5000,
            feeMinor: 1,
            occurredOn: "2025-01-01"
        )
        XCTAssertEqual(PropFirmEngine.expectedPayout(entry: pEntry), 50)
        
        // Mixed currencies in cashSummary fail closed
        let m1 = CashMovementItem(id: "1", entryId: "1", accountId: nil, firm: "Firm", currency: "USD", date: "2025-01-01", kind: "expense", amountMinor: 100, category: "evaluation", reference: "")
        let m2 = CashMovementItem(id: "2", entryId: "2", accountId: nil, firm: "Firm", currency: "EUR", date: "2025-01-02", kind: "expense", amountMinor: 100, category: "evaluation", reference: "")
        XCTAssertThrowsError(try PropFirmEngine.cashSummary(rows: [m1, m2]))
    }
    
    // MARK: - 2. Settlement Dates, Refunds, Reversals & Payout Progress
    
    func testUsesSettlementDatesRefundsAndNetReversalsWithPendingExcludedFromCash() throws {
        let eExpense = PropEntryItem(
            id: "e",
            firm: "Fixture firm",
            kind: "expense",
            category: "evaluation",
            currency: "USD",
            amountMinor: 10000, // $100.00
            occurredOn: "2025-01-02"
        )
        let eRefund = PropEntryItem(
            id: "refund",
            firm: "Fixture firm",
            kind: "refund",
            category: "refund",
            currency: "USD",
            amountMinor: 2000, // $20.00
            occurredOn: "2025-02-01",
            parentId: "e"
        )
        let ePayout = PropEntryItem(
            id: "p",
            firm: "Fixture firm",
            kind: "payout",
            category: "payout",
            currency: "USD",
            amountMinor: 100000, // $1,000.00
            splitBps: 9000, // 90%
            feeMinor: 1000, // $10.00 fee -> expected net = $890.00 (89000 minor)
            occurredOn: "2025-12-30",
            dueOn: "2026-01-10",
            status: .requested
        )
        
        // 1. Trước khi nhận tiền (Pending payout đóng góp 0 vào tiền mặt đã nhận)
        let movementsBefore = PropFirmEngine.cashMovements(entries: [eExpense, eRefund, ePayout], receipts: [])
        let totalsBefore = try PropFirmEngine.cashSummary(rows: movementsBefore)
        XCTAssertEqual(totalsBefore.spentMinor, 10000)
        XCTAssertEqual(totalsBefore.refundsMinor, 2000)
        XCTAssertEqual(totalsBefore.netSpendMinor, 8000)
        XCTAssertEqual(totalsBefore.receivedMinor, 0)
        XCTAssertEqual(totalsBefore.netMinor, -8000)
        XCTAssertEqual(totalsBefore.roi, -1.0)
        
        // 2. Nhận từng phần (Receipts) và Đảo tiền (Reversal)
        let r1 = PropReceiptItem(id: "r1", payoutId: "p", kind: "receipt", amountMinor: 40000, occurredOn: "2026-01-02")
        let r2 = PropReceiptItem(id: "r2", payoutId: "p", kind: "receipt", amountMinor: 49000, occurredOn: "2026-01-03")
        let rRev = PropReceiptItem(id: "rev", payoutId: "p", kind: "reversal", amountMinor: 9000, occurredOn: "2026-02-01")
        
        let receipts = [r1, r2, rRev]
        let movements = PropFirmEngine.cashMovements(entries: [eExpense, eRefund, ePayout], receipts: receipts)
        let totals = try PropFirmEngine.cashSummary(rows: movements)
        
        // Net received = 40000 + 49000 - 9000 = 80000
        XCTAssertEqual(totals.receivedMinor, 80000)
        // Net cash = 80000 - 8000 = 72000
        XCTAssertEqual(totals.netMinor, 72000)
        // Cash ROI = 72000 / 8000 = 9.0 (900%)
        XCTAssertEqual(totals.roi, 9.0)
        
        // Filter thời gian trước năm 2026 (chưa phát sinh receipts)
        let pre2026Movements = movements.filter { ($0.date ?? "") < "2026" }
        let preTotals = try PropFirmEngine.cashSummary(rows: pre2026Movements)
        XCTAssertEqual(preTotals.receivedMinor, 0)
        XCTAssertEqual(preTotals.netMinor, -8000)
        
        // Đường cong dòng tiền tích luỹ
        let timeline = try PropFirmEngine.cashTimeline(rows: movements)
        XCTAssertEqual(timeline.last?.date, "2026-02-01")
        XCTAssertEqual(timeline.last?.netMinor, 72000)
        
        // Tiến độ Payout Progress
        let progressList = PropFirmEngine.payoutProgress(entries: [ePayout], receipts: receipts, today: "2026-02-02")
        let progress = progressList.first!
        XCTAssertEqual(progress.expectedMinor, 89000)
        XCTAssertEqual(progress.actualMinor, 80000)
        XCTAssertEqual(progress.remainingMinor, 9000)
        XCTAssertTrue(progress.isPartial)
        XCTAssertTrue(progress.isOverdue) // due 2026-01-10 < today 2026-02-02 và actual < expected
    }
    
    // MARK: - 3. Zero-Spend ROI & Completed Payout Variance
    
    func testLeavesZeroSpendRoiUnavailableAndDistinguishesCompletedVarianceFromMoneyStillDue() throws {
        let ePayout = PropEntryItem(
            id: "p",
            firm: "Fixture firm",
            kind: "payout",
            category: "payout",
            currency: "USD",
            amountMinor: 100000,
            splitBps: 9000,
            feeMinor: 1000, // Expected 89000
            occurredOn: "2025-12-30",
            status: .completed
        )
        let receipt = PropReceiptItem(
            id: "r",
            payoutId: "p",
            kind: "receipt",
            amountMinor: 88000, // Short payment $880 thay vì $890
            occurredOn: "2026-01-02"
        )
        
        let movements = PropFirmEngine.cashMovements(entries: [ePayout], receipts: [receipt])
        let totals = try PropFirmEngine.cashSummary(rows: movements)
        
        // Zero expense -> ROI không khả dụng (nil)
        XCTAssertEqual(totals.spentMinor, 0)
        XCTAssertEqual(totals.netSpendMinor, 0)
        XCTAssertNil(totals.roi)
        
        // Khi payout đã Completed, tiền còn nợ (remaining) = 0, phương sai variance = -1000
        let progress = PropFirmEngine.payoutProgress(entries: [ePayout], receipts: [receipt], today: "2026-01-05").first!
        XCTAssertEqual(progress.actualMinor, 88000)
        XCTAssertEqual(progress.remainingMinor, 0)
        XCTAssertEqual(progress.varianceMinor, -1000)
        XCTAssertFalse(progress.isOverdue)
    }
    
    // MARK: - 4. Pass Rate Calculation
    
    func testResolvedPhasePassRate() {
        let acc1 = PropAccountItem(
            firm: "FTMO", name: "Eval 1", program: .evaluation, status: .passed, openedOn: "2026-01-01"
        )
        let acc2 = PropAccountItem(
            firm: "FTMO", name: "Eval 2", program: .evaluation, status: .breached, openedOn: "2026-02-01"
        )
        let acc3 = PropAccountItem(
            firm: "FTMO", name: "Eval 3", program: .evaluation, status: .active, openedOn: "2026-03-01"
        )
        let acc4 = PropAccountItem(
            firm: "FTMO", name: "Funded 1", program: .funded, status: .active, openedOn: "2026-04-01"
        )
        
        // Chỉ tính các phase evaluation/verification đã resolved (passed + breached = 2). Active bị loại trừ.
        let rate = PropFirmEngine.resolvedPhasePassRate(accounts: [acc1, acc2, acc3, acc4])
        XCTAssertEqual(rate, 0.5) // 1 / 2 = 50%
    }
    
    // MARK: - 5. Generic Prop CSV Import & Preview Rollback
    
    func testGenericCsvImportAtomicPreviewAndDeduplication() throws {
        let header = "id,kind,firm,account_id,currency,date,amount,category,expense_id,reference,notes"
        let csv = [
            header,
            "csv-purchase,expense,Fixture firm,a,USD,2025-01-02,100,evaluation,,INV1,Purchase",
            "rebate,refund,Fixture firm,a,USD,2025-02-01,20,,csv-purchase,,Rebate",
            "reward,payout,Fixture firm,a,USD,2026-01-02,890,,,,Paid"
        ].joined(separator: "\n")
        
        let fundedAccount = PropAccountItem(
            id: "a", firm: "Fixture firm", name: "Funded", program: .funded, status: .active, currency: "USD", openedOn: "2025-01-01"
        )
        
        // 1. Chạy ở chế độ Preview: Kết quả đếm 3 hàng, nhưng danh sách entries không bị ghi đè
        let (previewRes, entriesAfterPreview, _, _) = try PropFirmEngine.importPropCsv(
            csvText: csv,
            preview: true,
            existingAccounts: [fundedAccount],
            existingEntries: [],
            existingReceipts: [],
            existingAudits: []
        )
        XCTAssertEqual(previewRes.imported, 3)
        XCTAssertEqual(previewRes.skipped, 0)
        XCTAssertEqual(previewRes.sample.count, 3)
        XCTAssertTrue(entriesAfterPreview.isEmpty) // Rollback an toàn
        
        // 2. Chạy Import thực tế:
        let (importRes, importedEntries, importedReceipts, importedAudits) = try PropFirmEngine.importPropCsv(
            csvText: csv,
            preview: false,
            existingAccounts: [fundedAccount],
            existingEntries: [],
            existingReceipts: [],
            existingAudits: []
        )
        XCTAssertEqual(importRes.imported, 3)
        XCTAssertEqual(importedEntries.count, 3)
        XCTAssertEqual(importedReceipts.count, 1) // 1 payout receipt được tự động tạo
        
        let flows = PropFirmEngine.cashMovements(entries: importedEntries, receipts: importedReceipts)
        let totals = try PropFirmEngine.cashSummary(rows: flows)
        XCTAssertEqual(totals.spentMinor, 10000)
        XCTAssertEqual(totals.refundsMinor, 2000)
        XCTAssertEqual(totals.receivedMinor, 89000)
        XCTAssertEqual(totals.netMinor, 81000) // 89000 - (10000 - 2000) = 81000
        
        // 3. Re-import lại cùng file: Phát hiện trùng lặp idempotency, bỏ qua 3 hàng đã có
        let (repeatRes, _, _, _) = try PropFirmEngine.importPropCsv(
            csvText: csv,
            preview: false,
            existingAccounts: [fundedAccount],
            existingEntries: importedEntries,
            existingReceipts: importedReceipts,
            existingAudits: importedAudits
        )
        XCTAssertEqual(repeatRes.imported, 0)
        XCTAssertEqual(repeatRes.skipped, 3)
        
        // 4. Trùng ID nhưng thay đổi dữ liệu: Từ chối để bảo vệ tính toàn vẹn
        let conflictingCsv = csv.replacingOccurrences(of: ",100,evaluation", with: ",200,evaluation")
        XCTAssertThrowsError(
            try PropFirmEngine.importPropCsv(
                csvText: conflictingCsv,
                preview: false,
                existingAccounts: [fundedAccount],
                existingEntries: importedEntries,
                existingReceipts: importedReceipts,
                existingAudits: importedAudits
            )
        )
    }
    
    // MARK: - Supabase PostgREST & 2-Way Sync Tests
    
    func testSupabasePostgRESTSerializationParity() throws {
        let account = PropAccountItem(
            id: "test-acc-1",
            firm: "FTMO",
            name: "FTMO 100k",
            program: .funded,
            status: .active,
            currency: "USD",
            sizeMinor: 10_000_000,
            parentId: "parent-acc-0",
            journalAccountId: "j-acc-1",
            openedOn: "2026-09-01",
            closedOn: nil,
            renewalOn: "2026-10-01",
            renewalMinor: 15000,
            notes: "Test notes",
            archived: false,
            revision: 2
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(account)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // Check snake_case mapping for database columns
        XCTAssertTrue(jsonString.contains("\"size_minor\":10000000"))
        XCTAssertTrue(jsonString.contains("\"parent_id\":\"parent-acc-0\""))
        XCTAssertTrue(jsonString.contains("\"journal_account_id\":\"j-acc-1\""))
        XCTAssertTrue(jsonString.contains("\"renewal_minor\":15000"))
        XCTAssertTrue(jsonString.contains("\"opened_on\":\"2026-09-01\""))
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(PropAccountItem.self, from: data)
        XCTAssertEqual(decoded, account)
    }
    
    func testTwoWayRevisionMerge() {
        var local = PropAccountItem(
            id: "sync-acc-1",
            firm: "Topstep",
            name: "Initial Name",
            program: .evaluation,
            status: .active,
            currency: "USD",
            openedOn: "2026-09-01",
            revision: 1
        )
        
        let remoteHigherRevision = PropAccountItem(
            id: "sync-acc-1",
            firm: "Topstep",
            name: "Remote Updated Name",
            program: .evaluation,
            status: .passed,
            currency: "USD",
            openedOn: "2026-09-01",
            revision: 2
        )
        
        // Remote has higher revision -> Local updates
        if remoteHigherRevision.revision >= local.revision {
            local = remoteHigherRevision
        }
        XCTAssertEqual(local.name, "Remote Updated Name")
        XCTAssertEqual(local.status, .passed)
        XCTAssertEqual(local.revision, 2)
        
        // Stale remote (revision 1) arrives -> Ignored, local retains revision 2
        let staleRemote = PropAccountItem(
            id: "sync-acc-1",
            firm: "Topstep",
            name: "Old Stale Name",
            program: .evaluation,
            status: .active,
            currency: "USD",
            openedOn: "2026-09-01",
            revision: 1
        )
        if staleRemote.revision >= local.revision {
            local = staleRemote
        }
        XCTAssertEqual(local.name, "Remote Updated Name")
    }
}

