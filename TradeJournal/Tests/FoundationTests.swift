import XCTest
@testable import TradeJournal

final class FoundationTests: XCTestCase {
    
    func testCurrencyFormatting() {
        let amount: Decimal = Decimal(string: "1234.56")!
        let formatted = Formatters.currency(amount, currencyCode: "USD", isPrivate: false)
        XCTAssertTrue(formatted.contains("1,234.56") || formatted.contains("1234.56"), "Format should contain currency digits")
    }
    
    func testPrivacyModeMasking() {
        let amount: Decimal = Decimal(string: "99999.99")!
        let formatted = Formatters.currency(amount, isPrivate: true)
        XCTAssertEqual(formatted, "••••••", "Privacy mode must mask currency values")
        
        let pnlFormatted = Formatters.pnl(amount, isPrivate: true)
        XCTAssertEqual(pnlFormatted, "••••••", "Privacy mode must mask PnL values")
    }
    
    func testSignedPnlFormatting() {
        let profit: Decimal = Decimal(string: "500.00")!
        let loss: Decimal = Decimal(string: "-250.00")!
        
        let profitStr = Formatters.pnl(profit, isPrivate: false)
        XCTAssertTrue(profitStr.hasPrefix("+"), "Positive PnL must have a '+' prefix")
        
        let lossStr = Formatters.pnl(loss, isPrivate: false)
        XCTAssertTrue(lossStr.contains("-"), "Negative PnL must reflect negative sign")
    }
    
    func testPercentageFormatting() {
        XCTAssertEqual(Formatters.percentage(0.542), "54.2%")
        XCTAssertEqual(Formatters.percentage(nil), "n/a")
    }
    
    func testFinancialInvariantsBreakeven() {
        let zero: Decimal = Decimal(string: "0.0")!
        let tinyPnl: Decimal = Decimal(string: "0.0000000001")!
        let nonBreakeven: Decimal = Decimal(string: "0.01")!
        
        XCTAssertTrue(FinancialInvariants.isBreakeven(netPnl: zero))
        XCTAssertTrue(FinancialInvariants.isBreakeven(netPnl: tinyPnl))
        XCTAssertFalse(FinancialInvariants.isBreakeven(netPnl: nonBreakeven))
    }
    
    func testExecutionModelInitialization() {
        let fill = Execution(
            accountId: "acc-1",
            symbol: "AAPL",
            side: .buy,
            quantity: 100,
            price: Decimal(string: "150.50")!,
            fee: Decimal(string: "1.00")!,
            executedAt: Date()
        )
        
        XCTAssertEqual(fill.symbol, "AAPL")
        XCTAssertEqual(fill.side, .buy)
        XCTAssertEqual(fill.quantity, 100)
        XCTAssertFalse(fill.contentHash.isEmpty, "Execution must carry a deterministic contentHash")
    }
    
    func testDateFormatting() {
        let testDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14
        let timeStr = Formatters.formatTime(testDate)
        XCTAssertFalse(timeStr.isEmpty)
        let dateTimeStr = Formatters.formatDateTime(testDate)
        XCTAssertFalse(dateTimeStr.isEmpty)
    }
}
