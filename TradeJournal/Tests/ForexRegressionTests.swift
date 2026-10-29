import XCTest
@testable import TradeJournal

/// Regression tests for the forex financial logic:
/// - broker symbol suffixes must not change the contract size,
/// - P&L has to be converted into the reporting currency with the correct rate,
/// - swap / overnight interest has to be part of the net P&L.
final class ForexRegressionTests: XCTestCase {
    
    private let usdContext = CurrencyContext(reportingCurrency: "USD", rates: CurrencyConversion.default.rates, isEnabled: true)
    
    // MARK: - Symbol Classification
    
    func testBrokerSuffixesDoNotChangeTheContractSize() {
        for symbol in ["EURUSD", "EURUSDm", "EURUSD.m", "EURUSD.pro", "EURUSD_i", "EURUSDm2"] {
            let spec = AssetContractEngine.spec(for: symbol)
            XCTAssertEqual(spec.assetCategory, .forexMajor, "symbol: \(symbol)")
            XCTAssertEqual(spec.contractSize, 100_000, "symbol: \(symbol)")
            XCTAssertEqual(spec.baseCurrency, "EUR", "symbol: \(symbol)")
            XCTAssertEqual(spec.quoteCurrency, "USD", "symbol: \(symbol)")
            XCTAssertEqual(AssetContractEngine.canonicalSymbol(symbol), "EURUSD", "symbol: \(symbol)")
        }
    }
    
    func testCryptoAndIndexSymbolsAreNotMistakenForForex() {
        XCTAssertEqual(AssetContractEngine.spec(for: "XLMUSD").assetCategory, .crypto)
        XCTAssertEqual(AssetContractEngine.spec(for: "TRXUSD").assetCategory, .crypto)
        XCTAssertEqual(AssetContractEngine.spec(for: "BTCUSDT").assetCategory, .crypto)
        XCTAssertEqual(AssetContractEngine.spec(for: "US30").assetCategory, .index)
        XCTAssertEqual(AssetContractEngine.spec(for: "AES").assetCategory, .equity)
        XCTAssertEqual(AssetContractEngine.spec(for: "XAUUSDm").assetCategory, .goldAndMetals)
    }
    
    // MARK: - Gross P&L
    
    func testSuffixedForexSymbolProducesTheSamePnlAsThePlainSymbol() {
        let plain = AssetContractEngine.calculateGrossPnl(
            symbol: "EURUSD",
            direction: .long,
            quantity: Decimal(string: "0.25")!,
            entryPrice: Decimal(string: "1.08000")!,
            exitPrice: Decimal(string: "1.08400")!,
            context: usdContext
        )
        let suffixed = AssetContractEngine.calculateGrossPnl(
            symbol: "EURUSDm",
            direction: .long,
            quantity: Decimal(string: "0.25")!,
            entryPrice: Decimal(string: "1.08000")!,
            exitPrice: Decimal(string: "1.08400")!,
            context: usdContext
        )
        XCTAssertEqual(plain, 100)
        XCTAssertEqual(suffixed, 100)
    }
    
    func testJpyPairUsesTheExactTradeRate() {
        // 1 lot USDJPY, +10 pips = 10,000 JPY -> converted with the exit rate (155.100).
        let result = AssetContractEngine.calculateGrossPnlDetailed(
            symbol: "USDJPY",
            direction: .long,
            quantity: 1,
            entryPrice: Decimal(string: "155.000")!,
            exitPrice: Decimal(string: "155.100")!,
            context: usdContext
        )
        XCTAssertTrue(result.isConverted)
        XCTAssertEqual(result.quoteAmount, 10_000)
        XCTAssertEqual(result.amount, Decimal(10_000) / Decimal(string: "155.100")!)
    }
    
    func testCrossPairIsConvertedWithTheConfiguredRate() {
        // 1 lot EURGBP, +100 pips = 1,000 GBP -> 1,290 USD with GBP = 1.29.
        let result = AssetContractEngine.calculateGrossPnlDetailed(
            symbol: "EURGBP",
            direction: .long,
            quantity: 1,
            entryPrice: Decimal(string: "0.8500")!,
            exitPrice: Decimal(string: "0.8600")!,
            context: usdContext
        )
        XCTAssertTrue(result.isConverted)
        XCTAssertEqual(result.quoteAmount, 1_000)
        XCTAssertEqual(result.amount, Decimal(string: "1290")!)
    }
    
    func testCrossPairWithoutRateIsFlaggedInsteadOfSilentlyMislabeled() {
        let result = AssetContractEngine.calculateGrossPnlDetailed(
            symbol: "EURGBP",
            direction: .long,
            quantity: 1,
            entryPrice: Decimal(string: "0.8500")!,
            exitPrice: Decimal(string: "0.8600")!,
            context: CurrencyContext(reportingCurrency: "USD", rates: [:], isEnabled: true)
        )
        XCTAssertFalse(result.isConverted)
        XCTAssertEqual(result.quoteAmount, 1_000)
    }
    
    func testManualAndReconstructedPathsUseTheSameRates() {
        let manual = AssetContractEngine.calculateGrossPnl(
            symbol: "EURGBP",
            direction: .long,
            quantity: 1,
            entryPrice: Decimal(string: "0.8500")!,
            exitPrice: Decimal(string: "0.8600")!,
            conversionRates: CurrencyConversion.default.rates,
            reportingCurrency: "USD"
        )
        let reconstructed = TradeReconstructionEngine.buildRoundTrips(
            executions: [
                Execution(accountId: "acc-1", symbol: "EURGBP", side: .buy, quantity: 1, price: Decimal(string: "0.8500")!, executedAt: Date(timeIntervalSince1970: 1_000)),
                Execution(accountId: "acc-1", symbol: "EURGBP", side: .sell, quantity: 1, price: Decimal(string: "0.8600")!, executedAt: Date(timeIntervalSince1970: 2_000))
            ],
            options: .init(context: usdContext, accountCurrency: "USD")
        )
        XCTAssertEqual(reconstructed.count, 1)
        XCTAssertEqual(reconstructed[0].grossPnl, manual)
    }
    
    // MARK: - Swap
    
    func testSwapIsPartOfTheNetPnl() {
        let executions = [
            Execution(
                accountId: "acc-1",
                symbol: "EURUSD",
                side: .buy,
                quantity: 1,
                price: Decimal(string: "1.08000")!,
                fee: 2,
                swap: -5,
                executedAt: Date(timeIntervalSince1970: 1_000)
            ),
            Execution(
                accountId: "acc-1",
                symbol: "EURUSD",
                side: .sell,
                quantity: 1,
                price: Decimal(string: "1.08400")!,
                fee: 2,
                executedAt: Date(timeIntervalSince1970: 2_000)
            )
        ]
        let trades = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        XCTAssertEqual(trades.count, 1)
        let trade = trades[0]
        XCTAssertEqual(trade.grossPnl, 400)
        XCTAssertEqual(trade.fees, 4)
        XCTAssertEqual(trade.swapAmount, -5)
        XCTAssertEqual(trade.netPnl, 391)
    }
    
    func testBreakevenThresholdIsApplied() {
        let executions = [
            Execution(accountId: "acc-1", symbol: "EURUSD", side: .buy, quantity: 1, price: Decimal(string: "1.08000")!, fee: 1, executedAt: Date(timeIntervalSince1970: 1_000)),
            Execution(accountId: "acc-1", symbol: "EURUSD", side: .sell, quantity: 1, price: Decimal(string: "1.07950")!, fee: 1, executedAt: Date(timeIntervalSince1970: 2_000))
        ]
        // -50 USD gross - 2 USD fees = -52 USD net
        let withoutRule = TradeReconstructionEngine.buildRoundTrips(executions: executions)
        XCTAssertEqual(withoutRule[0].status, .loss)
        
        let withRule = TradeReconstructionEngine.buildRoundTrips(
            executions: executions,
            options: .init(defaults: JournalDefaults(breakeven: 100, breakevenMode: "money", feeRules: [], riskRules: []))
        )
        XCTAssertEqual(withRule[0].status, .breakeven)
    }
    
    // MARK: - Import
    
    func testMetaTraderStatementIsImported() {
        let csv = """
        Ticket,Open Time,Type,Volume,Symbol,Price,S/L,Commission,Swap,Profit
        1,2026.04.01 14:30:00,buy,0.25,EURUSDm,1.08000,0.0,-2.00,-3.50,0.00
        2,2026.04.01 15:30:00,sell,0.25,EURUSDm,1.08400,0.0,-2.00,0.00,100.00
        """
        let preview = StandardCSVImporter.preview(
            csvText: csv,
            accountId: "acc-mt5",
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertTrue(preview.isValid)
        XCTAssertEqual(preview.problems.count, 0)
        XCTAssertEqual(preview.usableExecutions.count, 2)
        XCTAssertEqual(preview.usableExecutions[0].symbol, "EURUSDM")
        XCTAssertEqual(preview.usableExecutions[0].quantity, Decimal(string: "0.25")!)
        XCTAssertEqual(preview.usableExecutions[0].fee, 2)
        XCTAssertEqual(preview.usableExecutions[0].swap, Decimal(string: "-3.5")!)
    }
    
    func testImportedMetaTraderStatementProducesCorrectForexPnl() {
        let csv = """
        Ticket,Open Time,Type,Volume,Symbol,Price,S/L,Commission,Swap,Profit
        1,2026.04.01 14:30:00,buy,0.25,EURUSDm,1.08000,0.0,-2.00,0.00,0.00
        2,2026.04.01 15:30:00,sell,0.25,EURUSDm,1.08400,0.0,-2.00,0.00,100.00
        """
        let preview = StandardCSVImporter.preview(
            csvText: csv,
            accountId: "acc-mt5",
            timeZone: TimeZone(identifier: "UTC")!
        )
        let trades = TradeReconstructionEngine.buildRoundTrips(
            executions: preview.usableExecutions,
            options: .init(context: usdContext, accountCurrency: "USD")
        )
        XCTAssertEqual(trades.count, 1)
        // 0.25 lot * 40 pips = 100 USD gross - 4 USD commission
        XCTAssertEqual(trades[0].grossPnl, 100)
        XCTAssertEqual(trades[0].fees, 4)
        XCTAssertEqual(trades[0].netPnl, 96)
        XCTAssertEqual(trades[0].status, .win)
    }
    
    func testContentHashIsStableAcrossDeviceTimezones() {
        let csv = """
        symbol,side,quantity,price,fee,date
        EURUSD,buy,0.25,1.08000,2.00,2026-04-01 14:30:00
        """
        let utc = StandardCSVImporter.preview(
            csvText: csv,
            accountId: "acc-1",
            timeZone: TimeZone(identifier: "UTC")!
        )
        let tokyo = StandardCSVImporter.preview(
            csvText: csv,
            accountId: "acc-1",
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )
        XCTAssertEqual(utc.usableExecutions.first?.contentHash, tokyo.usableExecutions.first?.contentHash)
    }
    
    // MARK: - Deduplication
    
    func testDistinctTradesOpenedSecondsApartAreNotMerged() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func makeTrade(key: String, offset: TimeInterval) -> Trade {
            Trade(
                key: key,
                accountId: "acc-1",
                symbol: "EURUSD",
                direction: .long,
                status: .win,
                openedAt: base.addingTimeInterval(offset),
                closedAt: base.addingTimeInterval(offset + 60),
                quantity: 1,
                openQuantity: 0,
                avgEntry: Decimal(string: "1.08000")!,
                avgExit: Decimal(string: "1.08400")!,
                grossPnl: 400,
                fees: 0,
                netPnl: 400,
                executionCount: 2,
                executionIds: []
            )
        }
        let trades = TradeDeduplicator.deduplicate([
            makeTrade(key: "a", offset: 0),
            makeTrade(key: "b", offset: 3)
        ])
        XCTAssertEqual(trades.count, 2, "Two scalps three seconds apart must both survive")
    }
    
    func testSameTradeWithDifferentKeyIsMerged() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func makeTrade(key: String, offset: TimeInterval, avgEntry: Decimal) -> Trade {
            Trade(
                key: key,
                accountId: "acc-1",
                symbol: "EURUSDm",
                direction: .long,
                status: .win,
                openedAt: base.addingTimeInterval(offset),
                closedAt: base.addingTimeInterval(offset + 60),
                quantity: 1,
                openQuantity: 0,
                avgEntry: avgEntry,
                avgExit: Decimal(string: "1.08400")!,
                grossPnl: 400,
                fees: 0,
                netPnl: 400,
                executionCount: 2,
                executionIds: []
            )
        }
        // Same trade imported twice: different key, sub-second timestamp difference, broker suffix variant.
        let trades = TradeDeduplicator.deduplicate([
            makeTrade(key: "a", offset: 0, avgEntry: Decimal(string: "1.08000")!),
            makeTrade(key: "b", offset: 0.2, avgEntry: Decimal(string: "1.08000")!)
        ])
        XCTAssertEqual(trades.count, 1, "The same trade must not be counted twice")
    }
    
    func testDuplicateExecutionsAreRemoved() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fill = Execution(
            id: "f1",
            accountId: "acc-1",
            symbol: "EURUSD",
            side: .buy,
            quantity: 1,
            price: Decimal(string: "1.08000")!,
            executedAt: base,
            contentHash: "hash-1"
        )
        let duplicate = Execution(
            id: "f2",
            accountId: "acc-1",
            symbol: "EURUSDm",
            side: .buy,
            quantity: 1,
            price: Decimal(string: "1.08000")!,
            executedAt: base,
            contentHash: "hash-1"
        )
        let cleaned = TradeDeduplicator.deduplicate([fill, duplicate])
        XCTAssertEqual(cleaned.count, 1)
    }
}
