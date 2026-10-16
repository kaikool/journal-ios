import XCTest
@testable import TradeJournalKit

final class ImportTests: XCTestCase {
    
    func testCSVParserBasicAndQuotedFields() {
        let csv = """
        symbol,side,quantity,price,fee,date
        AAPL,buy,100,"150.25",1.00,"2026-04-01 14:30:00"
        "TSLA, INC",sell,50,210.50,1.50,2026-04-01 15:30:00
        """
        
        let rows = CSVParser.parse(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["symbol", "side", "quantity", "price", "fee", "date"])
        XCTAssertEqual(rows[1][0], "AAPL")
        XCTAssertEqual(rows[1][3], "150.25")
        XCTAssertEqual(rows[2][0], "TSLA, INC")
    }
    
    func testStandardCSVImporterValidRows() {
        let csv = """
        Ticker,Action,Shares,Price,Commission,Timestamp
        AAPL,BUY,100,$150.00,$1.00,2026-04-01 14:30:00
        AAPL,SELL,100,$155.00,$1.00,2026-04-01 15:30:00
        """
        
        let preview = StandardCSVImporter.preview(csvText: csv, accountId: "acc-test")
        XCTAssertTrue(preview.isValid)
        XCTAssertEqual(preview.usableExecutions.count, 2)
        XCTAssertEqual(preview.problems.count, 0)
        XCTAssertEqual(preview.duplicateCount, 0)
        
        let fills = preview.usableExecutions
        XCTAssertEqual(fills[0].symbol, "AAPL")
        XCTAssertEqual(fills[0].side, .buy)
        XCTAssertEqual(fills[0].quantity, 100)
        XCTAssertEqual(fills[0].price, 150)
        XCTAssertEqual(fills[0].fee, 1)
        
        XCTAssertEqual(fills[1].symbol, "AAPL")
        XCTAssertEqual(fills[1].side, .sell)
        XCTAssertEqual(fills[1].price, 155)
    }
    
    func testStandardCSVImporterMalformedRowsDetection() {
        let csv = """
        symbol,side,quantity,price,fee,date
        VALID,buy,10,100,0,2026-04-01 14:30:00
        ,buy,10,100,0,2026-04-01 14:30:00
        BAD_SIDE,hold,10,100,0,2026-04-01 14:30:00
        BAD_QTY,buy,-5,100,0,2026-04-01 14:30:00
        BAD_PRICE,buy,10,abc,0,2026-04-01 14:30:00
        BAD_DATE,buy,10,100,0,invalid-date-string
        """
        
        let preview = StandardCSVImporter.preview(csvText: csv, accountId: "acc-test")
        XCTAssertEqual(preview.usableExecutions.count, 1)
        XCTAssertEqual(preview.problems.count, 5)
        
        XCTAssertTrue(preview.problems.contains(where: { $0.reason.contains("bị trống") }))
        XCTAssertTrue(preview.problems.contains(where: { $0.reason.contains("Side") }))
        XCTAssertTrue(preview.problems.contains(where: { $0.reason.contains("Khối lượng") }))
        XCTAssertTrue(preview.problems.contains(where: { $0.reason.contains("Giá") }))
        XCTAssertTrue(preview.problems.contains(where: { $0.reason.contains("Thời gian") }))
    }
    
    func testDeduplicationOnReimport() {
        let csv = """
        symbol,side,quantity,price,fee,date
        AAPL,buy,100,150.00,1.00,2026-04-01 14:30:00
        """
        
        let preview1 = StandardCSVImporter.preview(csvText: csv, accountId: "acc-test")
        XCTAssertEqual(preview1.usableExecutions.count, 1)
        
        let existingHash = preview1.usableExecutions[0].contentHash
        
        // Nhập lại cùng nội dung với existingHashes
        let preview2 = StandardCSVImporter.preview(
            csvText: csv,
            accountId: "acc-test",
            existingHashes: [existingHash]
        )
        
        XCTAssertEqual(preview2.usableExecutions.count, 0)
        XCTAssertEqual(preview2.duplicateCount, 1)
    }
    
    @MainActor
    func testTradeDataStoreImportAndRebuildIntegration() {
        let store = TradeDataStore()
        let accountId = "test-store-acc"
        store.addAccount(name: "Test Acc", currency: "USD")
        
        let csv = """
        symbol,side,quantity,price,fee,date
        NVDA,buy,50,100.00,1.00,2026-04-10 14:30:00
        NVDA,sell,50,110.00,1.00,2026-04-10 15:30:00
        """
        
        let preview = StandardCSVImporter.preview(csvText: csv, accountId: accountId)
        XCTAssertEqual(preview.usableExecutions.count, 2)
        
        store.importExecutions(accountId: accountId, newExecutions: preview.usableExecutions)
        
        let accTrades = store.trades.filter { $0.accountId == accountId }
        XCTAssertEqual(accTrades.count, 1)
        
        let trade = accTrades[0]
        XCTAssertEqual(trade.symbol, "NVDA")
        XCTAssertEqual(trade.status, .win)
        XCTAssertEqual(trade.netPnl, 498) // (110 - 100)*50 - 2 fee = 500 - 2 = 498
    }
}
