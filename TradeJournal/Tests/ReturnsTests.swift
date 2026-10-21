import XCTest
@testable import TradeJournal

/// Port 1:1 từ `packages/core/tests/returns.test.ts`.
final class ReturnsTests: XCTestCase {
    
    private let equity = ReturnInputs(
        netPnl: 20,
        avgEntry: 100,
        quantity: 2,
        assetClass: "equity"
    )
    
    func testMeasuresFuturesAndOptionReturnsAgainstFullEntryValue() {
        let futures = ReturnInputs(
            netPnl: 283,
            avgEntry: Decimal(string: "31157.25")!,
            quantity: 4,
            assetClass: "futures",
            contractMultiplier: 2
        )
        let fReturn = NetReturnEngine.netReturnOnEntry(trade: futures)
        XCTAssertNotNil(fReturn)
        XCTAssertEqual(fReturn!, 283.0 / 249258.0, accuracy: 1e-12)
        
        let option = ReturnInputs(
            netPnl: Decimal(string: "-1.3")!,
            avgEntry: Decimal(string: "2.47")!,
            quantity: 1,
            assetClass: "option",
            contractMultiplier: 100
        )
        let optReturn = NetReturnEngine.netReturnOnEntry(trade: option)
        XCTAssertNotNil(optReturn)
        XCTAssertEqual(optReturn!, -1.3 / 247.0, accuracy: 1e-12)
    }
    
    func testRequiresKnownMultiplierForDerivatives() {
        for asset in ["futures", "option", "forex", "cfd"] {
            let noMult = ReturnInputs(
                netPnl: equity.netPnl,
                avgEntry: equity.avgEntry,
                quantity: equity.quantity,
                assetClass: asset,
                contractMultiplier: nil
            )
            XCTAssertNil(NetReturnEngine.netReturnOnEntry(trade: noMult))
            
            let withMult = ReturnInputs(
                netPnl: equity.netPnl,
                avgEntry: equity.avgEntry,
                quantity: equity.quantity,
                assetClass: asset,
                contractMultiplier: 10
            )
            XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: withMult)!, 0.01, accuracy: 1e-9)
        }
    }
    
    func testPreservesUnitPricingForEquitiesAndCrypto() {
        for asset in ["equity", "crypto", "other", nil] {
            let inp = ReturnInputs(
                netPnl: equity.netPnl,
                avgEntry: equity.avgEntry,
                quantity: equity.quantity,
                assetClass: asset
            )
            XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: inp)!, 0.1, accuracy: 1e-9)
            
            let withMult = ReturnInputs(
                netPnl: equity.netPnl,
                avgEntry: equity.avgEntry,
                quantity: equity.quantity,
                assetClass: asset,
                contractMultiplier: 2
            )
            XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: withMult)!, 0.05, accuracy: 1e-9)
        }
    }
    
    func testUsesAbsoluteEntryValueWhilePreservingSignOfNetPnl() {
        let negEntry = ReturnInputs(netPnl: 20, avgEntry: -100, quantity: 2, assetClass: "equity")
        XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: negEntry)!, 0.1, accuracy: 1e-9)
        
        let negBoth = ReturnInputs(netPnl: -20, avgEntry: -100, quantity: 2, assetClass: "equity")
        XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: negBoth)!, -0.1, accuracy: 1e-9)
        
        let zeroPnl = ReturnInputs(netPnl: 0, avgEntry: 100, quantity: 2, assetClass: "equity")
        XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: zeroPnl)!, 0.0, accuracy: 1e-9)
        
        let halfQty = ReturnInputs(netPnl: 20, avgEntry: 100, quantity: Decimal(string: "0.5")!, assetClass: "equity")
        XCTAssertEqual(NetReturnEngine.netReturnOnEntry(trade: halfQty)!, 0.4, accuracy: 1e-9)
    }
    
    func testLeavesZeroOrInvalidEntryValuesUnavailable() {
        let zeroEntry = ReturnInputs(netPnl: 20, avgEntry: 0, quantity: 2, assetClass: "equity")
        XCTAssertNil(NetReturnEngine.netReturnOnEntry(trade: zeroEntry))
        
        let zeroQty = ReturnInputs(netPnl: 20, avgEntry: 100, quantity: 0, assetClass: "equity")
        XCTAssertNil(NetReturnEngine.netReturnOnEntry(trade: zeroQty))
        
        let negQty = ReturnInputs(netPnl: 20, avgEntry: 100, quantity: -1, assetClass: "equity")
        XCTAssertNil(NetReturnEngine.netReturnOnEntry(trade: negQty))
    }
}
