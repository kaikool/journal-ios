import XCTest
@testable import TradeJournal

/// Kiểm tra tính xác định và độ chính xác 1:1 của SHA-256 executionHash với Node.js.
final class JournalIdsTests: XCTestCase {
    
    func testExecutionHashMatchesNodeCrypto() {
        let hashAAPL = JournalIds.executionHash(
            symbol: "AAPL",
            side: "buy",
            quantity: 100,
            price: 10,
            executedAt: "2026-01-05T14:30:00Z"
        )
        XCTAssertEqual(hashAAPL, "f03fca9ac60c244066c810f2a546d0e7")

        let hashES = JournalIds.executionHash(
            symbol: "ES",
            side: "sell",
            quantity: Decimal(string: "2.5")!,
            price: Decimal(string: "5012.25")!,
            executedAt: "2026-04-01T15:00:00Z"
        )
        XCTAssertEqual(hashES, "d356c7ce7cce5bcaf050bbc744780462")

        let hashBTC = JournalIds.executionHash(
            symbol: "BTC",
            side: "buy",
            quantity: Decimal(string: "0.0054321")!,
            price: Decimal(string: "65432.1")!,
            executedAt: "2026-03-01T00:00:00Z"
        )
        XCTAssertEqual(hashBTC, "567776d092062a895941b3c8c4b8c87b")
    }
    
    func testToPrecision12() {
        XCTAssertEqual(JournalIds.toPrecision12(100), "100.000000000")
        XCTAssertEqual(JournalIds.toPrecision12(Decimal(string: "10.5")!), "10.5000000000")
        XCTAssertEqual(JournalIds.toPrecision12(Decimal(string: "0.00123")!), "0.00123000000000")
        XCTAssertEqual(JournalIds.toPrecision12(Decimal(string: "5012.25")!), "5012.25000000")
    }
}
