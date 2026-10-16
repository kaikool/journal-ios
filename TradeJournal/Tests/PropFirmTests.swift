import XCTest
@testable import TradeJournalKit

final class PropFirmTests: XCTestCase {
    
    func testToMinorConversion() throws {
        let minor = try PropFirmEngine.toMinor(value: "149.50", digits: 2)
        XCTAssertEqual(minor, 14950)
        
        let zero = try PropFirmEngine.toMinor(value: "0.00", digits: 2)
        XCTAssertEqual(zero, 0)
        
        let large = try PropFirmEngine.toMinor(value: "50000.00", digits: 2)
        XCTAssertEqual(large, 5000000)
    }
    
    func testExpectedPayoutCalculation() {
        // Entry: amount = 2,500.00 (250000 minor), 90% split (9000 bps), 25.00 fee (2500 minor)
        let entry = PropEntryItem(
            firm: "Topstep",
            kind: "payout",
            category: "payout",
            amountMinor: 250000,
            splitBps: 9000,
            feeMinor: 2500,
            occurredOn: "2026-10-01"
        )
        
        let expected = PropFirmEngine.expectedPayout(entry: entry)
        // (250000 * 9000 + 5000) / 10000 - 2500 = 225000 - 2500 = 222500 ($2,225.00)
        XCTAssertEqual(expected, 222500)
    }
    
    func testCashMovementsAndSummary() {
        let e1 = PropEntryItem(
            id: "e1", firm: "Topstep", kind: "expense", category: "activation",
            amountMinor: 14900, occurredOn: "2026-09-01"
        )
        let e2 = PropEntryItem(
            id: "e2", firm: "FTMO", kind: "expense", category: "evaluation",
            amountMinor: 54000, occurredOn: "2026-08-15"
        )
        let e3 = PropEntryItem(
            id: "e3", firm: "Topstep", kind: "payout", category: "payout",
            amountMinor: 250000, splitBps: 9000, feeMinor: 2500, occurredOn: "2026-10-01"
        )
        let r1 = PropReceiptItem(
            id: "r1", payoutId: "e3", kind: "receipt",
            amountMinor: 222500, occurredOn: "2026-10-03"
        )
        
        let movements = PropFirmEngine.cashMovements(entries: [e1, e2, e3], receipts: [r1])
        XCTAssertEqual(movements.count, 3) // e1, e2, and r1
        
        let summary = PropFirmEngine.cashSummary(rows: movements)
        XCTAssertEqual(summary.spentMinor, 68900) // 14900 + 54000
        XCTAssertEqual(summary.refundsMinor, 0)
        XCTAssertEqual(summary.receivedMinor, 222500)
        XCTAssertEqual(summary.netMinor, 153600) // 222500 - 68900 = +1536.00 USD
        XCTAssertNotNil(summary.roi)
        XCTAssertGreaterThan(summary.roi!, 2.0) // 153600 / 68900 = 2.229
    }
}
