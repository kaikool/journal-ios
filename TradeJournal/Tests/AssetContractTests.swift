import XCTest
@testable import TradeJournal

final class AssetContractTests: XCTestCase {
    
    // MARK: - 1. Gold (XAUUSD) Tests
    
    func testGoldQuarterLotFourPointsProfit() {
        // User scenario: Vàng 0.25 lot đi 4 giá lãi 100 đô
        // Buy 0.25 lot XAUUSD at 2000.00, Sell at 2004.00
        let pnl = AssetContractEngine.calculateGrossPnl(
            symbol: "XAUUSD",
            direction: .long,
            quantity: Decimal(string: "0.25")!,
            entryPrice: Decimal(string: "2000.00")!,
            exitPrice: Decimal(string: "2004.00")!
        )
        
        XCTAssertEqual(pnl, Decimal(100), "0.25 lot Gold moving 4 points must equal exactly $100.00 USD")
        
        let delta = AssetContractEngine.pipDelta(
            symbol: "XAUUSD",
            entryPrice: 2000,
            exitPrice: 2004,
            direction: .long
        )
        XCTAssertEqual(delta.points, Decimal(4), "4.00 points movement")
        XCTAssertEqual(delta.pips, Decimal(40), "40.0 pips movement (1 point = 10 pips)")
    }
    
    func testGoldShortTradeProfit() {
        // Sell 0.50 lot XAUUSD from 2650.00 down to 2640.00 (10 giá)
        let pnl = AssetContractEngine.calculateGrossPnl(
            symbol: "GOLD",
            direction: .short,
            quantity: Decimal(string: "0.50")!,
            entryPrice: Decimal(string: "2650.00")!,
            exitPrice: Decimal(string: "2640.00")!
        )
        // 0.50 lot * 10 points * 100 oz = $500.00 USD
        XCTAssertEqual(pnl, Decimal(500), "0.50 lot Gold falling 10 points must equal $500.00 USD")
    }
    
    // MARK: - 2. Forex (EURUSD) Tests
    
    func testForexMajorQuarterLotFortyPipsProfit() {
        // EURUSD 0.25 lot moving 40 pips (0.0040)
        // Buy 0.25 lot at 1.08000, Sell at 1.08400
        let pnl = AssetContractEngine.calculateGrossPnl(
            symbol: "EURUSD",
            direction: .long,
            quantity: Decimal(string: "0.25")!,
            entryPrice: Decimal(string: "1.08000")!,
            exitPrice: Decimal(string: "1.08400")!
        )
        // 0.25 * 0.0040 * 100,000 = $100.00 USD
        XCTAssertEqual(pnl, Decimal(100), "0.25 lot EURUSD moving 40 pips must equal exactly $100.00 USD")
        
        let delta = AssetContractEngine.pipDelta(
            symbol: "EURUSD",
            entryPrice: Decimal(string: "1.08000")!,
            exitPrice: Decimal(string: "1.08400")!,
            direction: .long
        )
        XCTAssertEqual(delta.pips, Decimal(40), "40.0 pips movement")
    }
    
    func testForexStandardLotTenPipsProfit() {
        // 1.00 standard lot EURUSD moving 10 pips (0.0010) = $100.00 USD
        let pnl = AssetContractEngine.calculateGrossPnl(
            symbol: "EURUSD",
            direction: .long,
            quantity: 1,
            entryPrice: Decimal(string: "1.05000")!,
            exitPrice: Decimal(string: "1.05100")!
        )
        XCTAssertEqual(pnl, Decimal(100), "1.00 standard lot moving 10 pips must equal $100.00 USD")
    }
    
    // MARK: - 3. Crypto & Index Tests
    
    func testCryptoBitcoinProfit() {
        // Buy 0.25 BTC at 60,000, Sell at 60,400 (+$400)
        let pnl = AssetContractEngine.calculateGrossPnl(
            symbol: "BTCUSDT",
            direction: .long,
            quantity: Decimal(string: "0.25")!,
            entryPrice: 60000,
            exitPrice: 60400
        )
        // 0.25 * 400 * 1 = $100.00 USD
        XCTAssertEqual(pnl, Decimal(100), "0.25 BTC moving $400 must equal $100.00 USD")
    }
    
    func testIndexUs30Profit() {
        // Buy 1.00 contract US30 at 43,000, Sell at 43,100 (+100 pts)
        let pnl = AssetContractEngine.calculateGrossPnl(
            symbol: "US30",
            direction: .long,
            quantity: 1,
            entryPrice: 43000,
            exitPrice: 43100
        )
        XCTAssertEqual(pnl, Decimal(100), "1 contract US30 moving 100 points must equal $100.00 USD")
    }
    
    // MARK: - 4. TradeReconstructionEngine End-to-End Reconstruction Tests
    
    func testTradeReconstructionForGoldManualTrade() {
        let openTime = Date()
        let closeTime = openTime.addingTimeInterval(1800)
        
        let buyFill = Execution(
            id: "fill-gold-1",
            accountId: "acc-gold",
            symbol: "XAUUSD",
            side: .buy,
            quantity: Decimal(string: "0.25")!,
            price: Decimal(string: "2000.00")!,
            fee: 0,
            executedAt: openTime,
            source: "manual"
        )
        
        let sellFill = Execution(
            id: "fill-gold-2",
            accountId: "acc-gold",
            symbol: "XAUUSD",
            side: .sell,
            quantity: Decimal(string: "0.25")!,
            price: Decimal(string: "2004.00")!,
            fee: 0,
            executedAt: closeTime,
            source: "manual"
        )
        
        let trades = TradeReconstructionEngine.buildRoundTrips(executions: [buyFill, sellFill])
        XCTAssertEqual(trades.count, 1, "Should reconstruct exactly 1 round-trip")
        
        let trade = trades[0]
        XCTAssertEqual(trade.grossPnl, Decimal(100), "Reconstructed Gold trade gross P&L must be $100.00")
        XCTAssertEqual(trade.netPnl, Decimal(100), "Reconstructed Gold trade net P&L must be $100.00")
        XCTAssertEqual(trade.contractMultiplier, Decimal(100), "Contract multiplier for Gold must be 100")
    }
    
    func testTradeReconstructionForForexManualTrade() {
        let openTime = Date()
        let closeTime = openTime.addingTimeInterval(3600)
        
        let buyFill = Execution(
            id: "fill-fx-1",
            accountId: "acc-fx",
            symbol: "EURUSD",
            side: .buy,
            quantity: Decimal(string: "0.25")!,
            price: Decimal(string: "1.08000")!,
            fee: 2,
            executedAt: openTime,
            source: "manual"
        )
        
        let sellFill = Execution(
            id: "fill-fx-2",
            accountId: "acc-fx",
            symbol: "EURUSD",
            side: .sell,
            quantity: Decimal(string: "0.25")!,
            price: Decimal(string: "1.08400")!,
            fee: 2,
            executedAt: closeTime,
            source: "manual"
        )
        
        let trades = TradeReconstructionEngine.buildRoundTrips(executions: [buyFill, sellFill])
        XCTAssertEqual(trades.count, 1)
        
        let trade = trades[0]
        XCTAssertEqual(trade.grossPnl, Decimal(100), "Reconstructed EURUSD trade gross P&L must be $100.00")
        XCTAssertEqual(trade.fees, Decimal(4), "Total fees must be $4.00")
        XCTAssertEqual(trade.netPnl, Decimal(96), "Reconstructed EURUSD trade net P&L must be $96.00")
        XCTAssertEqual(trade.contractMultiplier, Decimal(100_000), "Contract multiplier for Forex must be 100,000")
    }
}
