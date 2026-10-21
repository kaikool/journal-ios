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
        XCTAssertEqual(Formatters.percentage(0.542), "54.20%")
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
    
    func testIsoDayFormatting() {
        let utc = TimeZone(identifier: "UTC")!
        let testDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14 22:13:20 UTC
        let isoDay = Formatters.isoDayString(from: testDate, timeZone: utc)
        XCTAssertEqual(isoDay, "2023-11-14")
        
        let parsedDate = Formatters.date(fromIsoDay: "2023-11-14", timeZone: utc)
        XCTAssertNotNil(parsedDate)
        let roundTrip = Formatters.isoDayString(from: parsedDate!, timeZone: utc)
        XCTAssertEqual(roundTrip, "2023-11-14")
    }
    
    func testCleanAccountName() {
        let raw1 = "meta-trader-5 · …7657"
        XCTAssertEqual(Formatters.cleanAccountName(raw1), "MT5 · #7657")
        
        let raw2 = "Meta-Trade-4-......1234"
        XCTAssertEqual(Formatters.cleanAccountName(raw2), "MT4 · #1234")
        
        let customName = "My Swing Trading Account"
        XCTAssertEqual(Formatters.cleanAccountName(customName), customName)
    }
    
    func testSyncOptionsDefaultsForPullToRefresh() {
        let def = SyncOptions.default
        XCTAssertFalse(def.backupToCloud, "Pull-to-refresh quick sync must never block on Cloud backup by default")
        XCTAssertTrue(def.enabledProviderIds.contains("ctrader"))
        XCTAssertTrue(def.enabledProviderIds.contains("the5ers"))
        XCTAssertEqual(def.dateRangeMode, .last30Days)
    }
}

